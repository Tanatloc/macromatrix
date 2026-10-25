// Controle van fase 3 tegen een draaiende Worker (lokaal of staging): twee "toestellen" van hetzelfde testaccount
// en een tweede gebruiker. Meet hoe snel een wijziging van A via de WebSocket bij B aankomt, en kijkt of samenvoegen
// na offline werken (laatste wijziging wint), insertOnly en de afscherming tussen gebruikers kloppen.
// Maakt testaccounts op het testdomein en ruimt ze op.
//   node tool/sync_check.mjs http://127.0.0.1:8787 --env staging --local
//   node tool/sync_check.mjs https://api-staging.macromatrix.eu --env staging
import assert from 'node:assert/strict';
import { account, call, cleanup, live, login, sql, step, steps } from './checklib.mjs';

const entry = (id, at, extra = {}) => ({ id, day: '2026-10-25', meal: 1, food_ref: 'ciqual:1', name: 'Banaan', grams: 100, quantity: 100, nutrients: '{}', created_at: 1, updated_at: at, deleted: 0, ...extra });
const push = (token, table, rows, insertOnly = false) => call('POST', '/v1/sync/push', { table, rows, insertOnly }, token);
const pull = (token, table, since = 0) => call('GET', `/v1/sync/pull?table=${table}&since=${since}&limit=500`, undefined, token);


try {
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit');
  const me = await account('sync');
  const other = await account('ander');
  const a = me.token;
  const b = await login(me.email);
  const hubB = await live(b);

  await step('niet ingelogd: 401 (PGRST301)', async () => {
    const r = await pull(null, 'diary');
    assert.equal(r.status, 401);
    assert.equal(r.data.code, 'PGRST301');
  });
  await step('A logt iets: B krijgt binnen 5 s een melding en haalt het op', async () => {
    const t0 = Date.now();
    const r = await push(a, 'diary', [entry('e1', Date.now())]);
    assert.equal(r.status, 200);
    const msg = JSON.parse(await hubB.next(5000));
    const ms = Date.now() - t0;
    assert.deepEqual(msg, { type: 'changes', tables: ['diary'] });
    const rows = (await pull(b, 'diary')).data;
    assert.deepEqual(rows.map((x) => x.id), ['e1']);
    console.log(`      (push → melding bij B in ${ms} ms)`);
  });
  await step('offline gewerkt: de laatste wijziging wint, een oudere wordt genegeerd', async () => {
    const t = Date.now();
    await push(b, 'diary', [entry('e1', t + 1000, { grams: 222 })]);
    const r = await push(a, 'diary', [entry('e1', t + 500, { grams: 111 })]); // A was offline, oudere wijziging
    assert.deepEqual(r.data, {});
    const row = (await pull(a, 'diary')).data.find((x) => x.id === 'e1');
    assert.equal(row.grams, 222);
  });
  await step('cursor: alleen wat na server_seq kwam', async () => {
    const all = (await pull(a, 'diary')).data;
    const last = all.at(-1).server_seq;
    assert.deepEqual((await pull(a, 'diary', last)).data, []);
    await push(a, 'notes', [{ day: '2026-10-25', text: 'hoi', updated_at: Date.now() }]);
    assert.equal((await pull(a, 'notes', 0)).data.length, 1);
  });
  await step('insertOnly laat een bestaande instelling staan', async () => {
    await push(a, 'settings', [{ key: 'profile', value: '{"v":1}', updated_at: 1 }]);
    const r = await push(b, 'settings', [{ key: 'profile', value: '{"v":2}', updated_at: 2 }], true);
    assert.deepEqual(r.data, {});
  });
  await step('een ander ziet niets en kan niets overschrijven', async () => {
    assert.deepEqual((await pull(other.token, 'diary')).data, []);
    await push(other.token, 'diary', [{ ...entry('e1', Date.now() + 9999, { grams: 1 }), user_id: me.id }]);
    const row = (await pull(a, 'diary')).data.find((x) => x.id === 'e1');
    assert.equal(row.grams, 222);
    const f = await call('POST', '/v1/sync/fetch', { table: 'diary', keys: ['e1'] }, other.token);
    assert.equal(f.data.length, 1);
    assert.equal(f.data[0].user_id, other.id);
  });
  await step('foutcodes zoals Postgres', async () => {
    const r = await push(a, 'notes', [{ day: '2026-10-26', text: 'x'.repeat(20001), updated_at: 1 }]);
    assert.equal(r.status, 400);
    assert.equal(r.data.code, '23514');
    assert.equal((await call('POST', '/v1/rpc/bestaat_niet', {}, a)).data.code, 'PGRST202');
  });
  await step('uitloggen op één toestel sluit alleen de live verbinding van dat toestel', async () => {
    const c = await login(me.email);
    const hubC = await live(c);
    assert.equal((await call('POST', '/auth/sign-out', {}, c)).status, 200);
    const t0 = Date.now();
    while (hubC.ws.readyState < 2 && Date.now() - t0 < 5000) await new Promise((ok) => setTimeout(ok, 100));
    assert.ok(hubC.ws.readyState >= 2, 'verbinding van C bleef open');
    assert.equal(hubB.ws.readyState, 1, 'verbinding van B werd ook gesloten');
    const t = await call('POST', '/v1/live/ticket', {}, c);
    assert.equal(t.status, 401);
  });
  await step('account verwijderen: alles weg en de live verbinding dicht', async () => {
    assert.equal((await call('POST', '/v1/rpc/delete_account', {}, a)).status, 200);
    // De hub sluit de verbinding (sluitbericht ontvangen: CLOSING of CLOSED)
    const t0 = Date.now();
    while (hubB.ws.readyState < 2 && Date.now() - t0 < 5000) await new Promise((ok) => setTimeout(ok, 100));
    assert.ok(hubB.ws.readyState >= 2, 'verbinding niet gesloten');
    assert.equal(sql(`SELECT count(*) n FROM diary WHERE user_id = '${me.id}'`)[0].n, 0);
    assert.equal((await pull(b, 'diary')).status, 401);
  });
  console.log(`sync_check: ${steps.length} stappen geslaagd`);
} finally {
  cleanup();
}
process.exit(0);
