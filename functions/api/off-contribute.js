// Cloudflare Pages Function: een product dat iemand zelf van het etiket las, delen met Open Food Facts, zodat
// anderen het ook vinden. Alleen als de gebruiker daar uitdrukkelijk ja op zegt (de app vraagt het na het bewaren).
//
// Verstuurd wordt: de barcode, de naam, het merk, de voedingswaarden per 100 g en de foto van de voedingswaardetabel
// (en van de voorkant, als die er is). Niets over de gebruiker. Open Food Facts publiceert dat onder de ODbL.
//
// Met het account van de app bij Open Food Facts: de Cloudflare-secrets OFF_USER en OFF_PASSWORD (nooit in de code).
// Staan die er niet, dan antwoordt deze functie not_configured en toont de app de vraag niet.
// Schrijf-API (v2): POST /cgi/product_jqm2.pl (velden) en POST /cgi/product_image_upload.pl (foto's).

import { checkLogin, hourly, imageType, json, MAX_IMAGE_BYTES } from '../_lib/ai.js';
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

export async function onRequestGet({ env }) {
  return json({ configured: configured(env) });
}

export async function onRequestPost({ request, env }, fetcher = fetch) {
  if (!configured(env)) return json({ error: 'not_configured' }, 503);
  const who = await checkLogin(request, fetcher);
  if (who.error) return who.error;

  const declared = Number(request.headers.get('Content-Length') ?? 0);
  if (declared > MAX_IMAGE_BYTES * 2 + 40_000) return json({ error: 'too_big' }, 413);
  let form;
  try {
    form = await request.formData();
  } catch (_) {
    return json({ error: 'bad_request' }, 400);
  }
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
  await rate.count();

  const base = `https://${host(env)}`;
  const headers = { 'User-Agent': USER_AGENT };
  try {
    const fields = new FormData();
    fields.set('user_id', env.OFF_USER);
    fields.set('password', env.OFF_PASSWORD);
    for (const [k, v] of Object.entries(productFields({ code, name, brand, per100: checked.per100 }))) fields.set(k, v);
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
      if (!img) continue;
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
