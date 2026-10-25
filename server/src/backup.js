// Back-ups van D1 naar R2, en terugzetten.
//
// Bestand (daily/JJJJ-MM-DD.mmb, op de 1e ook monthly/JJJJ-MM.mmb):
//   "MMB1" + blokken van [lengte (4 bytes) | IV (12 bytes) | AES-256-GCM(gzip-gegevens)]
//   Elk blok heeft als extra gegevens (AAD) zijn volgnummer en of het het laatste is: blokken verwisselen of het
//   bestand inkorten valt op bij het ontsleutelen.
// Inhoud (na ontsleutelen en uitpakken) is NDJSON: {"t": tabel, "r": rij} per rij, en als laatste regel
// {"manifest": {at, tables: {naam: {rows, hash}}}}. De hash is een keten van SHA-256 over de rijen in rowid-volgorde,
// zodat een teruggezette kopie exact te vergelijken is.
//
// De sleutel (BACKUP_KEY, 32 bytes base64) staat alleen als Worker-secret en bij de eigenaar. Zonder sleutel is een
// back-up onleesbaar.

const MAGIC = new TextEncoder().encode('MMB1');
const BLOCK = 4 << 20; // 4 MiB gzip-gegevens per blok
const PAGE = 1000;

// Niet mee: kortstondig of opnieuw op te bouwen (sessies, codes, limieten, testpostvak) en de interne tabellen
const SKIP = new Set(['session', 'verification', 'rateLimit', 'test_outbox', 'signup_ips', 'import_mode', 'd1_migrations']);
// Eerst (andere tabellen verwijzen ernaar); de rest alfabetisch
const FIRST = ['user', 'account', 'features', 'roadmap_items', 'challenges'];

const enc = new TextEncoder();
const dec = new TextDecoder();
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

async function aesKey(b64) {
  const raw = Uint8Array.from(atob(b64 ?? ''), (c) => c.charCodeAt(0));
  if (raw.length !== 32) throw new Error('BACKUP_KEY moet 32 bytes zijn (base64)');
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

const aad = (i, last) => enc.encode(`mmb1:${i}:${last ? 1 : 0}`);

/** Tabellen in de volgorde waarin ze teruggezet moeten worden. */
export async function backupTables(db) {
  const { results } = await db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'").all();
  const names = results.map((r) => r.name).filter((n) => !SKIP.has(n));
  return [...FIRST.filter((n) => names.includes(n)), ...names.filter((n) => !FIRST.includes(n)).sort()];
}

/** Rijen van een tabel in rowid-volgorde, per pagina. */
async function* rows(db, table) {
  let after = -Infinity;
  for (;;) {
    const { results } = await db.prepare(`SELECT rowid AS "__rowid", * FROM "${table}" WHERE rowid > ? ORDER BY rowid LIMIT ?`).bind(after === -Infinity ? -9e15 : after, PAGE).all();
    if (!results.length) return;
    for (const r of results) {
      after = r.__rowid;
      delete r.__rowid;
      yield r;
    }
    if (results.length < PAGE) return;
  }
}

/** Kettinghash per tabel: h = sha256(h + json van een pagina rijen). */
async function chain(h, lines) {
  return hex(await crypto.subtle.digest('SHA-256', enc.encode(h + lines)));
}

/** Telling en hash per tabel van een database (voor het manifest en de controle na terugzetten). */
export async function fingerprint(db, tables) {
  const out = {};
  for (const t of tables) {
    let n = 0;
    let h = '';
    let page = '';
    for await (const r of rows(db, t)) {
      page += JSON.stringify(r) + '\n';
      if (++n % PAGE === 0) {
        h = await chain(h, page);
        page = '';
      }
    }
    if (page) h = await chain(h, page);
    out[t] = { rows: n, hash: h };
  }
  return out;
}

/** Versleutelt een stroom gzip-bytes in blokken; geeft een stroom van het .mmb-bestand. */
function encryptStream(key, block = BLOCK) {
  let i = 0;
  let parts = [];
  let size = 0;
  const take = () => {
    const all = new Uint8Array(size);
    let o = 0;
    for (const p of parts) {
      all.set(p, o);
      o += p.length;
    }
    return all;
  };
  const seal = async (ctl, data, last) => {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad(i++, last) }, key, data));
    const head = new Uint8Array(16);
    new DataView(head.buffer).setUint32(0, ct.length);
    head.set(iv, 4);
    ctl.enqueue(head);
    ctl.enqueue(ct);
  };
  return new TransformStream({
    start(ctl) {
      ctl.enqueue(MAGIC);
    },
    async transform(chunk, ctl) {
      parts.push(chunk);
      size += chunk.length;
      // Pas samenvoegen als er een heel blok is (niet bij elk stukje: dat zou alles telkens kopiëren)
      while (size > block) {
        const all = take();
        await seal(ctl, all.subarray(0, block), false);
        parts = [all.subarray(block)];
        size = all.length - block;
      }
    },
    async flush(ctl) {
      await seal(ctl, take(), true);
    },
  });
}

/** Een stroom van onbekende lengte in R2 zetten (multipart: delen van minstens 5 MiB, behalve de laatste). */
export async function putStream(bucket, key, stream, meta = {}) {
  const PART = 8 << 20;
  const upload = await bucket.createMultipartUpload(key, { customMetadata: meta });
  const done = [];
  let parts = [];
  let size = 0;
  const send = async () => {
    const all = new Uint8Array(size);
    let o = 0;
    for (const p of parts) {
      all.set(p, o);
      o += p.length;
    }
    done.push(await upload.uploadPart(done.length + 1, all));
    parts = [];
    size = 0;
  };
  try {
    for await (const chunk of stream) {
      parts.push(chunk);
      size += chunk.length;
      if (size >= PART) await send();
    }
    if (size || !done.length) await send();
    return await upload.complete(done);
  } catch (e) {
    await upload.abort().catch(() => {});
    throw e;
  }
}

/** Ontsleutelt een .mmb-bestand (ArrayBuffer of Uint8Array) naar de gzip-bytes; gooit bij elke afwijking. */
async function decrypt(file, keyB64) {
  const key = await aesKey(keyB64);
  const bytes = file instanceof Uint8Array ? file : new Uint8Array(file);
  if (dec.decode(bytes.slice(0, 4)) !== 'MMB1') throw new Error('geen MacroMatrix-back-up');
  const parts = [];
  let pos = 4;
  let i = 0;
  while (pos < bytes.length) {
    const len = new DataView(bytes.buffer, bytes.byteOffset + pos, 4).getUint32(0);
    const iv = bytes.slice(pos + 4, pos + 16);
    const ct = bytes.slice(pos + 16, pos + 16 + len);
    if (ct.length !== len) throw new Error('back-up is ingekort');
    const last = pos + 16 + len === bytes.length;
    parts.push(new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData: aad(i++, last) }, key, ct)));
    pos += 16 + len;
  }
  return new Blob(parts).stream();
}

/** Alle regels van een back-up als objecten (rij of manifest). */
export async function* readBackup(file, keyB64) {
  const text = (await decrypt(file, keyB64)).pipeThrough(new DecompressionStream('gzip')).pipeThrough(new TextDecoderStream());
  let rest = '';
  for await (const chunk of text) {
    rest += chunk;
    let nl;
    while ((nl = rest.indexOf('\n')) >= 0) {
      const line = rest.slice(0, nl);
      rest = rest.slice(nl + 1);
      if (line) yield JSON.parse(line);
    }
  }
  if (rest) yield JSON.parse(rest);
}

/** Maakt een back-up van [db] als stroom (het .mmb-bestand) en geeft ook het manifest. */
export async function makeBackup(db, keyB64, now = new Date(), { block } = {}) {
  const key = await aesKey(keyB64);
  const tables = await backupTables(db);
  const manifest = { at: now.toISOString(), tables: {} };
  const ndjson = new ReadableStream({
    async start(ctl) {
      try {
        for (const t of tables) {
          let n = 0;
          let h = '';
          let page = '';
          for await (const r of rows(db, t)) {
            const line = JSON.stringify(r) + '\n';
            page += line;
            ctl.enqueue(enc.encode(`{"t":${JSON.stringify(t)},"r":${line.slice(0, -1)}}\n`));
            if (++n % PAGE === 0) {
              h = await chain(h, page);
              page = '';
            }
          }
          if (page) h = await chain(h, page);
          manifest.tables[t] = { rows: n, hash: h };
        }
        ctl.enqueue(enc.encode(JSON.stringify({ manifest }) + '\n'));
        ctl.close();
      } catch (e) {
        ctl.error(e);
      }
    },
  });
  return { stream: ndjson.pipeThrough(new CompressionStream('gzip')).pipeThrough(encryptStream(key, block)), manifest };
}

/**
 * Een back-up terugzetten in [db] (een lege of te overschrijven database met hetzelfde schema). Wist eerst de
 * tabellen uit de back-up. Geeft het manifest. Alleen voor een herstel- of testdatabase: nooit op de echte.
 */
export async function restoreBackup(db, file, keyB64) {
  let manifest = null;
  let wiped = false;
  let pending = [];
  const flush = async () => {
    if (!pending.length) return;
    await db.batch([db.prepare('UPDATE import_mode SET active = 1'), ...pending, db.prepare('UPDATE import_mode SET active = 0')]);
    pending = [];
  };
  for await (const line of readBackup(file, keyB64)) {
    if (line.manifest) {
      manifest = line.manifest;
      continue;
    }
    if (!wiped) {
      // Pas na de eerste rij (de sleutel klopt dan): leegmaken in omgekeerde volgorde
      const tables = await backupTables(db);
      await db.batch([db.prepare('UPDATE import_mode SET active = 1'), ...[...tables].reverse().filter((t) => t !== 'sync_seq').map((t) => db.prepare(`DELETE FROM "${t}"`)), db.prepare('UPDATE import_mode SET active = 0')]);
      wiped = true;
    }
    const cols = Object.keys(line.r);
    if (line.t === 'sync_seq') {
      pending.push(db.prepare('UPDATE sync_seq SET seq = ? WHERE id = ?').bind(line.r.seq, line.r.id));
    } else {
      pending.push(db.prepare(`INSERT INTO "${line.t}" (${cols.map((c) => `"${c}"`).join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`).bind(...cols.map((c) => line.r[c])));
    }
    if (pending.length >= 50) await flush();
  }
  await flush();
  if (!manifest) throw new Error('back-up zonder manifest (onvolledig)');
  return manifest;
}

/** Vergelijkt een teruggezette database met het manifest. Geeft een lijst verschillen (leeg = gelijk). */
export async function verifyRestore(db, manifest) {
  const got = await fingerprint(db, Object.keys(manifest.tables));
  const diffs = [];
  for (const [t, want] of Object.entries(manifest.tables)) {
    if (got[t].rows !== want.rows) diffs.push(`${t}: ${got[t].rows} rijen in plaats van ${want.rows}`);
    else if (got[t].hash !== want.hash) diffs.push(`${t}: inhoud verschilt`);
  }
  return diffs;
}
