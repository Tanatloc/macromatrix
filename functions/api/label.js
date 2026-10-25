// Cloudflare Pages Function: een foto van de voedingswaardetabel lezen, voor een barcode die nergens gevonden werd.
// De app stuurt (multipart) een verkleinde JPEG van de tabel ("label") en eventueel van de voorkant ("front", voor de
// naam en het merk). Het beeldmodel van Workers AI (zelfde als /api/photo) leest de tabel als strikte JSON; deze
// functie kijkt alles na en zet het om naar waarden per 100 g (kJ → kcal, zout ↔ natrium). De app opent daarmee het
// formulier voor een eigen product, zodat de gebruiker alles nakijkt voor het bewaard wordt.
// Alleen voor ingelogde gebruikers. De foto's worden hier niet bewaard.
// Dagteller ai_quota_use('label'): 1 gratis, 30 met Pro (migratie 20261027000000_ai_quota). Is die er nog niet,
// dan werkt het zoals /api/photo zonder teller: alleen de rem per uur. Antwoordt de teller niet (storing): 503.

import { AiDown, MAX_IMAGE_BYTES, aiDown, aiQuotaStatus, chargeQuota, checkLogin, dataUrl, hourly, imageType, json, modelObject, quotaBody, quotaDown, runModel } from '../_lib/ai.js';
import { backendFetch } from '../_lib/backend.js';
import { readForm as readBody } from '../_lib/body.js';

const PER_HOUR = 20;

const PROMPT = [
  'You read the nutrition facts table on a food package photo and answer with strict JSON only, no other text.',
  'Use exactly these keys (numbers as plain numbers with a dot, or null when not on the label):',
  '{"basis": "100g" | "100ml" | "portion", "portion_size": number or null, "portion_unit": "g" | "ml" | null,',
  ' "energy_kj": number, "energy_kcal": number, "fat": number, "saturated_fat": number, "carbohydrate": number,',
  ' "sugars": number, "fibre": number, "protein": number, "salt": number, "sodium": number,',
  ' "name": string or null, "brand": string or null}',
  'Rules: prefer the column per 100 g or per 100 ml. Only use "portion" when there is no per 100 column, and then give',
  'the portion size in grams or ml. Grams for nutrients, sodium in grams too. Write "<0.5" as 0.5.',
  'Do not guess values that are not visible: use null. If there is no nutrition table, answer {"basis": null}.',
].join('\n');

const FRONT_PROMPT = [
  'This is the front of a food package. Answer with strict JSON only, no other text:',
  '{"name": product name as printed (without the brand), "brand": brand name}. Use null for what you cannot read.',
].join('\n');

// Sleutels van het model → sleutels in ons antwoord (zoals Open Food Facts ze noemt)
const NUTRIENTS = [
  ['fat', 'fat'],
  ['saturated_fat', 'saturated_fat'],
  ['carbohydrate', 'carbohydrates'],
  ['sugars', 'sugars'],
  ['fibre', 'fiber'],
  ['protein', 'proteins'],
  ['salt', 'salt'],
  ['sodium', 'sodium'],
];

// "12,5", "12.5 g", "<0,5" of 12.5 → 12.5; iets anders → null
export function num(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v !== 'string') return null;
  const m = v.replace(',', '.').match(/-?\d+(?:\.\d+)?/);
  if (!m) return null;
  const n = Number(m[0]);
  return Number.isFinite(n) ? n : null;
}

const round = (v, d = 2) => (v == null ? null : Math.round(v * 10 ** d) / 10 ** d);

function text(v, max = 120) {
  if (typeof v !== 'string') return null;
  const t = v.replace(/\s+/g, ' ').trim();
  if (!t || /^(null|unknown|n\/a|none)$/i.test(t)) return null;
  return t.slice(0, max);
}

// Waarden per 100 g nakijken: wat niet kan, valt weg; is het geheel onmogelijk, dan een fout.
// Geeft {per100, warnings} terug, of {error}.
export function checkPer100(input) {
  const v = { ...input };
  const warnings = [];
  for (const k of ['fat', 'saturated_fat', 'carbohydrates', 'sugars', 'fiber', 'proteins', 'salt', 'sodium']) {
    if (v[k] == null) continue;
    if (!(v[k] >= 0) || v[k] > 100) {
      v[k] = null;
      warnings.push(`dropped_${k}`);
    }
  }
  // Een deel kan niet groter zijn dan het geheel
  if (v.saturated_fat != null && v.fat != null && v.saturated_fat > v.fat + 0.5) {
    v.saturated_fat = null;
    warnings.push('dropped_saturated_fat');
  }
  if (v.sugars != null && v.carbohydrates != null && v.sugars > v.carbohydrates + 0.5) {
    v.sugars = null;
    warnings.push('dropped_sugars');
  }
  // Energie: het model haalt kJ en kcal soms door elkaar
  let kcal = v.energy_kcal;
  let kj = v.energy_kj;
  if (kcal != null && kj != null && kcal > kj) [kcal, kj] = [kj, kcal];
  if (kcal != null && (kcal < 0 || kcal > 900)) kcal = null;
  if (kj != null && (kj < 0 || kj > 3800)) kj = null;
  if (kcal == null && kj != null) kcal = kj / 4.184;
  else if (kcal != null && kj != null && Math.abs(kcal * 4.184 - kj) > kj * 0.15 + 20) {
    // Spreken ze elkaar tegen, dan geldt de kJ (staat op een Europees etiket altijd eerst)
    kcal = kj / 4.184;
    warnings.push('energy_mismatch');
  }
  if (kj == null && kcal != null) kj = kcal * 4.184;
  v.energy_kcal = kcal;
  v.energy_kj = kj;
  // Zout en natrium: zout = natrium × 2,5
  if (v.salt == null && v.sodium != null) v.salt = v.sodium * 2.5;
  if (v.sodium == null && v.salt != null) v.sodium = v.salt / 2.5;
  if (v.salt != null && v.salt > 100) return { error: 'implausible' };

  const mass = ['fat', 'carbohydrates', 'proteins', 'fiber', 'salt'].reduce((a, k) => a + (v[k] ?? 0), 0);
  if (mass > 105) return { error: 'implausible' };
  const macros = ['fat', 'carbohydrates', 'proteins'].filter((k) => v[k] != null).length;
  if (v.energy_kcal == null && macros < 2) return { error: 'unreadable' };
  // Veel meer energie dan vet, koolhydraten en eiwit samen kunnen geven: verdacht, maar laat de gebruiker beslissen
  if (v.energy_kcal != null && macros === 3) {
    const est = 9 * v.fat + 4 * v.carbohydrates + 4 * v.proteins + 2 * (v.fiber ?? 0);
    if (v.energy_kcal > est * 1.6 + 60 || v.energy_kcal < est * 0.5 - 40) warnings.push('energy_vs_macros');
  }
  const per100 = {};
  for (const k of ['energy_kcal', 'energy_kj', 'fat', 'saturated_fat', 'carbohydrates', 'sugars', 'fiber', 'proteins', 'salt', 'sodium']) {
    per100[k] = round(v[k], k === 'energy_kcal' || k === 'energy_kj' ? 0 : k === 'sodium' ? 3 : 2);
  }
  return { per100, warnings: [...new Set(warnings)] };
}

// Het JSON-antwoord van het model nakijken en omzetten naar waarden per 100 g of 100 ml.
// Geeft {name, brand, basis, from_portion, portion_size, per100, warnings} terug, of {error}.
export function normaliseLabel(raw) {
  if (!raw || typeof raw !== 'object') return { error: 'unreadable' };
  const basisRaw = String(raw.basis ?? '').toLowerCase().replace(/\s+/g, '');
  let basis;
  if (/100ml/.test(basisRaw)) basis = '100ml';
  else if (/100g/.test(basisRaw)) basis = '100g';
  else if (/portion|serving|portie/.test(basisRaw)) basis = 'portion';
  else return { error: 'unreadable' };

  let factor = 1;
  let portion = null;
  let unit = null;
  if (basis === 'portion') {
    portion = num(raw.portion_size);
    unit = /ml/i.test(String(raw.portion_unit ?? '')) ? 'ml' : 'g';
    if (portion == null || portion < 1 || portion > 2000) return { error: 'no_per100' };
    factor = 100 / portion;
  } else {
    // Een portiegrootte mag mee voor het formulier (gewicht van één portie)
    const p = num(raw.portion_size);
    if (p != null && p >= 1 && p <= 2000) {
      portion = p;
      unit = /ml/i.test(String(raw.portion_unit ?? '')) ? 'ml' : 'g';
    }
  }

  const v = {
    energy_kcal: num(raw.energy_kcal),
    energy_kj: num(raw.energy_kj),
  };
  for (const [from, to] of NUTRIENTS) v[to] = num(raw[from]);
  for (const k of Object.keys(v)) if (v[k] != null) v[k] *= factor;
  const checked = checkPer100(v);
  if (checked.error) return checked;
  return {
    name: text(raw.name),
    brand: text(raw.brand, 80),
    basis: basis === 'portion' ? (unit === 'ml' ? '100ml' : '100g') : basis,
    from_portion: basis === 'portion',
    portion_size: portion == null ? null : round(portion, 1),
    portion_unit: portion == null ? null : unit,
    per100: checked.per100,
    warnings: checked.warnings,
  };
}

async function readForm(request) {
  const read = await readBody(request, MAX_IMAGE_BYTES * 2 + 20_000);
  if (read.error) return { error: read.error };
  if (read.bad) return { error: json({ error: 'bad_image' }, 400) };
  const form = read.form;
  const file = async (name) => {
    const f = form.get(name);
    if (!f || typeof f === 'string') return null;
    return new Uint8Array(await f.arrayBuffer());
  };
  const label = await file('label');
  const front = await file('front');
  if (!label) return { error: json({ error: 'bad_image' }, 400) };
  if (label.length > MAX_IMAGE_BYTES || (front && front.length > MAX_IMAGE_BYTES)) return { error: json({ error: 'too_big' }, 413) };
  const labelType = imageType(label);
  const frontType = front ? imageType(front) : null;
  if (!labelType || (front && !frontType)) return { error: json({ error: 'bad_image' }, 400) };
  return { label, labelType, front, frontType };
}

// Met het reservemodel als het beeldmodel uitvalt (runModel); gooit AiDown als geen van beide antwoordt
async function ask(env, prompt, bytes, mime, maxTokens) {
  const { result } = await runModel(
    env.AI,
    {
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: dataUrl(bytes, mime) } },
          ],
        },
      ],
      max_tokens: maxTokens,
      temperature: 0,
    },
    { ms: Number(env.AI_TIMEOUT_MS) || undefined },
  );
  return modelObject(result);
}

export async function onRequestPost({ request, env }) {
  if (!env.AI) return json({ error: 'not_configured' }, 503);
  const fetcher = backendFetch(env);
  const who = await checkLogin(request, fetcher);
  if (who.error) return who.error;

  const form = await readForm(request);
  if (form.error) return form.error;

  const rate = await hourly('label', who.user, PER_HOUR);
  if (!rate.allowed) return json({ error: 'too_many' }, 429);

  // De dagteller na de controles hierboven alleen lezen; hij gaat pas omhoog als er waarden uit het etiket komen.
  // Geen teller (migratie niet uitgevoerd): verder zoals zonder teller. Een storing bij de teller: 503.
  const q = await aiQuotaStatus(who.auth, 'label', fetcher, 'ai_quota');
  if (q.down) return quotaDown();
  const before = q.quota ?? null;
  if (before && !before.allowed) return json({ error: 'quota', used: before.used, limit: before.limit, pro: before.pro }, 429);
  await rate.count();

  let table, front;
  try {
    [table, front] = await Promise.all([
      ask(env, PROMPT, form.label, form.labelType, 400),
      form.front ? ask(env, FRONT_PROMPT, form.front, form.frontType, 80).catch(() => null) : null,
    ]);
  } catch (e) {
    if (e instanceof AiDown) return aiDown(before);
    throw e;
  }
  const out = normaliseLabel(table);
  // Onleesbaar: niets geteld (de rem per uur blijft)
  if (out.error) return json({ error: out.error, ...(before ? { quota: quotaBody(before) } : {}) }, 422);
  // Naam en merk van de voorkant gaan voor (daar staan ze groot); anders wat in de tabel stond
  if (front && typeof front === 'object') {
    out.name = text(front.name) ?? out.name;
    out.brand = text(front.brand, 80) ?? out.brand;
  }
  const quota = await chargeQuota(who.auth, 'label', before, fetcher);
  if (quota) out.quota = quotaBody(quota);
  return json(out);
}
