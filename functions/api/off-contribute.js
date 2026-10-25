// Cloudflare Pages Function: een product dat iemand zelf van het etiket las, delen met Open Food Facts, zodat
// anderen het ook vinden. Alleen als de gebruiker daar uitdrukkelijk ja op zegt (de app vraagt het na het bewaren).
//
// Verstuurd wordt: de barcode, de naam, het merk, de voedingswaarden per 100 g en de foto van de voedingswaardetabel
// (en van de voorkant, als die er is). Niets over de gebruiker. Open Food Facts publiceert dat onder de ODbL.
//
// Met het account van de app bij Open Food Facts: de Cloudflare-secrets OFF_USER en OFF_PASSWORD (nooit in de code).
// Staan die er niet, dan antwoordt deze functie not_configured en toont de app de vraag niet.
// Schrijf-API (v2): POST /cgi/product_jqm2.pl (velden) en POST /cgi/product_image_upload.pl (foto's).
//
// Alles gaat onder één gedeeld account, dus: alleen een product dat er nog niet is (of zonder naam en zonder
// voedingswaarden). Kent Open Food Facts het al, dan 409 exists en wordt er niets geschreven. Een merk of foto die er
// al staat, wordt niet overschreven. Naam en merk gaan eerst door het woordfilter van de server (text_blocked,
// migratie 20261105100000_moderation); antwoordt dat niet, dan wordt er niets gedeeld. Per account een dagteller
// ai_quota_use('off'): 10 per dag (migratie 20261107000000_quota_voice_off); zonder die migratie alleen de rem per uur.

import { ANON, SUPABASE_URL, checkLogin, hourly, imageType, json, quotaDown, useQuotaOrHourly, MAX_IMAGE_BYTES } from '../_lib/ai.js';
import { readForm } from '../_lib/body.js';
import { checkPer100, num } from './label.js';

const PER_HOUR = 10;
export const APP_VERSION = '1.13.0';
export const USER_AGENT = `MacroMatrix/${APP_VERSION} (macromatrix.eu)`;

// Onze sleutels → velden van Open Food Facts (nutriment_<naam> met een eenheid)
const FIELDS = [
  ['energy_kcal', 'energy-kcal', 'kcal'],
  ['energy_kj', 'energy-kj', 'kJ'],
  ['fat', 'fat', 'g'],
  ['saturated_fat', 'saturated-fat', 'g'],
  ['carbohydrates', 'carbohydrates', 'g'],
  ['sugars', 'sugars', 'g'],
  ['fiber', 'fiber', 'g'],
  ['proteins', 'proteins', 'g'],
  ['salt', 'salt', 'g'],
  ['sodium', 'sodium', 'g'],
];

const configured = (env) => Boolean(env.OFF_USER && env.OFF_PASSWORD);
const host = (env) => (env.OFF_HOST && /^[a-z0-9.-]+$/i.test(env.OFF_HOST) ? env.OFF_HOST : 'world.openfoodfacts.org');

// Een geldige EAN-8/12/13/14 (met controlecijfer)
export function validBarcode(code) {
  if (!/^\d{8}$|^\d{12,14}$/.test(code)) return false;
  const d = [...code].map(Number);
  const check = d.pop();
  const sum = d.reverse().reduce((a, n, i) => a + n * (i % 2 === 0 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10 === check;
}

const clean = (v, max) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, max) : '');

// De velden voor product_jqm2.pl (zonder het wachtwoord, voor de tests).
export function productFields({ code, name, brand, per100 }) {
  const f = {
    code,
    nutrition_data_per: '100g',
    comment: `Added from the nutrition label with ${USER_AGENT}`,
  };
  if (name) f.product_name = name;
  if (brand) f.brands = brand;
  for (const [ours, theirs, unit] of FIELDS) {
    if (per100[ours] == null) continue;
    f[`nutriment_${theirs}`] = String(per100[ours]);
    f[`nutriment_${theirs}_unit`] = unit;
  }
  return f;
}

// Naam en merk door het woordfilter van de server, met het token van de gebruiker. Geeft true (mag), false (een
// geweigerd woord) of null (het filter antwoordt niet: dan niets delen).
export async function textAllowed(auth, texts, fetcher = fetch) {
  for (const t of texts) {
    if (!t) continue;
    try {
      const r = await fetcher(`${SUPABASE_URL}/rest/v1/rpc/text_blocked`, {
        method: 'POST',
        headers: { apikey: ANON, Authorization: auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p: t }),
      });
      if (!r.ok) {
        console.log(`text_blocked: ${r.status}`);
        return null;
      }
      const blocked = await r.json();
      if (blocked === true) return false;
      if (blocked !== false) return null;
    } catch (e) {
      console.log(`text_blocked: ${e}`);
      return null;
    }
  }
  return true;
}

// Wat Open Food Facts al over deze barcode weet. Geeft {product} (null als het product er niet is), of null als het
// opzoeken mislukt.
export async function offProduct(base, code, fetcher = fetch) {
  try {
    const r = await fetcher(`${base}/api/v2/product/${code}.json?fields=code,product_name,brands,nutriments,images`, {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    });
    const j = await r.json().catch(() => null);
    // Een onbekende barcode: 404 met status 0
    if (r.status === 404 || (r.ok && j?.status === 0)) return { product: null };
    if (!r.ok || !j || typeof j.product !== 'object' || !j.product) return null;
    return { product: j.product };
  } catch (e) {
    console.log(`off product: ${e}`);
    return null;
  }
}

const filled = (v) => typeof v === 'string' && v.trim() !== '';

// Heeft het product al een naam of voedingswaarden? Dan schrijven we er niet overheen.
export function hasData(product) {
  if (!product) return false;
  if (filled(product.product_name)) return true;
  const n = product.nutriments && typeof product.nutriments === 'object' ? product.nutriments : {};
  return FIELDS.some(([, theirs]) => [n[`${theirs}_100g`], n[theirs]].some((v) => v != null && v !== '' && Number.isFinite(Number(v))));
}

export async function onRequestGet({ env }) {
  return json({ configured: configured(env) });
}

export async function onRequestPost({ request, env }, fetcher = fetch) {
  if (!configured(env)) return json({ error: 'not_configured' }, 503);
  const who = await checkLogin(request, fetcher);
  if (who.error) return who.error;

  const read = await readForm(request, MAX_IMAGE_BYTES * 2 + 40_000);
  if (read.error) return read.error;
  if (read.bad) return json({ error: 'bad_request' }, 400);
  const form = read.form;
  const code = clean(form.get('code'), 14);
  if (!validBarcode(code)) return json({ error: 'bad_barcode' }, 400);
  const name = clean(form.get('name'), 120);
  const brand = clean(form.get('brand'), 80);
  if (!name) return json({ error: 'bad_request' }, 400);
  let raw;
  try {
    raw = JSON.parse(String(form.get('nutriments') ?? '{}'));
  } catch (_) {
    return json({ error: 'bad_request' }, 400);
  }
  const values = {};
  for (const [ours] of FIELDS) values[ours] = num(raw?.[ours]);
  const checked = checkPer100(values);
  if (checked.error) return json({ error: 'implausible' }, 400);

  const file = async (key) => {
    const f = form.get(key);
    if (!f || typeof f === 'string') return null;
    const bytes = new Uint8Array(await f.arrayBuffer());
    const type = imageType(bytes);
    return type ? { bytes, type } : null;
  };
  const label = await file('label');
  const front = await file('front');

  const rate = await hourly('off', who.user, PER_HOUR);
  if (!rate.allowed) return json({ error: 'too_many' }, 429);

  const allowed = await textAllowed(who.auth, [name, brand], fetcher);
  if (allowed === null) return quotaDown();
  if (!allowed) return json({ error: 'not_allowed' }, 400);

  // De dagteller in één stap in de database (veilig bij veel verzoeken tegelijk); telt ook de rem per uur
  const q = await useQuotaOrHourly(who.auth, 'off', rate, fetcher, () => ({ error: 'too_many' }));
  if (q.error) return q.error;

  const base = `https://${host(env)}`;
  const headers = { 'User-Agent': USER_AGENT };
  const known = await offProduct(base, code, fetcher);
  if (!known) return json({ error: 'failed' }, 502);
  if (hasData(known.product)) return json({ error: 'exists', url: `https://world.openfoodfacts.org/product/${code}` }, 409);
  // Een product zonder naam en voedingswaarden mag aangevuld worden, maar een merk of foto die er staat, blijft
  const theirs = known.product ?? {};
  const keepBrand = filled(theirs.brands);
  const hasImage = (field) => Boolean(theirs.images && typeof theirs.images === 'object' && theirs.images[field]);
  try {
    const fields = new FormData();
    fields.set('user_id', env.OFF_USER);
    fields.set('password', env.OFF_PASSWORD);
    for (const [k, v] of Object.entries(productFields({ code, name, brand: keepBrand ? '' : brand, per100: checked.per100 }))) fields.set(k, v);
    const r = await fetcher(`${base}/cgi/product_jqm2.pl`, { method: 'POST', headers, body: fields });
    const j = await r.json().catch(() => null);
    if (!r.ok || j?.status !== 1) {
      console.log(`off product_jqm2: ${r.status} ${j?.status_verbose ?? ''}`);
      return json({ error: 'failed' }, 502);
    }
    // De foto's: een mislukte foto maakt het product niet ongedaan
    let images = 0;
    for (const [img, field] of [
      [label, 'nutrition_en'],
      [front, 'front_en'],
    ]) {
      if (!img || hasImage(field)) continue;
      const up = new FormData();
      up.set('user_id', env.OFF_USER);
      up.set('password', env.OFF_PASSWORD);
      up.set('code', code);
      up.set('imagefield', field);
      up.set(`imgupload_${field}`, new Blob([img.bytes], { type: img.type }), `${field}.${img.type === 'image/png' ? 'png' : 'jpg'}`);
      try {
        const ur = await fetcher(`${base}/cgi/product_image_upload.pl`, { method: 'POST', headers, body: up });
        const uj = await ur.json().catch(() => null);
        if (ur.ok && uj?.status === 'status ok') images++;
        else console.log(`off image ${field}: ${ur.status} ${uj?.debug ?? ''}`);
      } catch (e) {
        console.log(`off image ${field}: ${e}`);
      }
    }
    return json({ ok: true, images, url: `https://world.openfoodfacts.org/product/${code}` });
  } catch (e) {
    console.log(`off contribute: ${e}`);
    return json({ error: 'failed' }, 502);
  }
}
