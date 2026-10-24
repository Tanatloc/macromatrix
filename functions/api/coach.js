// Cloudflare Pages Function: de wekelijkse coach. De app stuurt een kleine samenvatting van je week in cijfers
// (dagen gelogd, Voedingsscore, energie en macro's tegenover je doel, de stoffen die het verst onder je doel zitten of
// boven een bovengrens, je gewichtstrend, je doel, de 5 producten met de meeste energie als gewone namen, en je
// voorkeuren en allergieën als codes). Geen dagboek, geen namen, geen notities. Een tekstmodel van Workers AI schrijft
// daarmee een korte samenvatting en 2 à 3 tips voor volgende week, in het Engels of het Nederlands.
// Alleen voor ingelogde gebruikers. Er wordt niets bewaard: niet wat de app stuurt, niet wat het model schrijft.
// Dagteller ai_quota_use('coach'): 3 met Pro, 1 zonder Pro maar pas als de functie voor iedereen open staat
// (migratie 20261103000000_coach). Anders dan bij /api/label werkt dit niet zonder teller: die houdt ook de vroege
// toegang bij. Ontbreekt de migratie, dan not_configured (de app verbergt de coach dan).

import { aiQuotaStatus, checkLogin, hourly, json, modelObject, stripMarkdown, TimeoutError, withTimeout } from '../_lib/ai.js';

// Groot en goed in het Nederlands, en snel genoeg voor een paar honderd woorden
export const TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';

// Wat de app stuurt is een paar honderd bytes; alles boven deze grens is geen weekoverzicht
export const MAX_INPUT_BYTES = 4000;
const PER_HOUR = 6;
// Langer wachten heeft geen zin: de app geeft het na 60 s op. Te wijzigen met COACH_TIMEOUT_MS (in tests).
const TIMEOUT_MS = 25_000;

const GOALS = new Set(['lose', 'maintain', 'gain']);

// Een getal binnen redelijke grenzen, of null
function num(v, min, max, digits = 0) {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const c = Math.min(max, Math.max(min, v));
  const f = 10 ** digits;
  return Math.round(c * f) / f;
}

// Een korte naam (stof of product): alleen letters, cijfers en wat leestekens, nooit een zin of iets met een link
function label(v, max = 40) {
  if (typeof v !== 'string') return null;
  const t = v
    .normalize('NFC')
    .replace(/[^\p{L}\p{N} ,.'()%/&+-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!t || /https?|www\./i.test(t)) return null;
  return t.slice(0, max);
}

// Een code zoals 'vegetarian' of 'peanuts'
const code = (v) => (typeof v === 'string' && /^[a-zA-Z][a-zA-Z0-9_]{0,30}$/.test(v) ? v : null);

const list = (v, max, f) => (Array.isArray(v) ? v.slice(0, max).map(f).filter((x) => x != null) : []);

// Wat de app stuurde nakijken en terugbrengen tot de velden die we kennen, met redelijke waarden. Geeft {week} of
// {error}. Zo komt er nooit vrije tekst van de gebruiker in het verzoek aan het model.
export function cleanWeek(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { error: 'bad_input' };
  const days = num(raw.days, 0, 7);
  if (days == null || days < 3) return { error: 'too_few_days' };
  const lang = raw.lang === 'nl' ? 'nl' : 'en';
  const pair = (o, max) =>
    o && typeof o === 'object' && num(o.avg, 0, max) != null ? { avg: num(o.avg, 0, max), goal: num(o.goal, 0, max) } : null;
  const macros = {};
  for (const k of ['protein', 'carbs', 'fat', 'fiber']) {
    const p = pair(raw.macros?.[k], 2000);
    if (p) macros[k] = { ...p, unit: 'g' };
  }
  const weight =
    raw.weight && typeof raw.weight === 'object'
      ? {
          change_kg: num(raw.weight.change_kg, -10, 10, 1),
          trend: ['down', 'stable', 'up'].includes(raw.weight.trend) ? raw.weight.trend : null,
        }
      : null;
  const week = {
    lang,
    days_logged: days,
    nutrient_score: num(raw.score, 0, 100),
    goal: GOALS.has(raw.goal) ? raw.goal : 'maintain',
    energy_kcal: pair(raw.energy, 10000),
    macros,
    below_target: list(raw.low, 5, (x) => {
      const name = label(x?.name);
      const pct = num(x?.pct, 0, 1000);
      return name && pct != null ? { nutrient: name, pct_of_target: pct } : null;
    }),
    above_upper_limit: list(raw.high, 5, (x) => {
      const name = label(x?.name);
      const pct = num(x?.pct, 0, 5000);
      return name && pct != null ? { nutrient: name, pct_of_upper_limit: pct } : null;
    }),
    weight: weight && (weight.change_kg != null || weight.trend) ? weight : null,
    top_foods_by_energy: list(raw.foods, 5, (x) => label(x, 50)),
    diet: list(raw.diet, 12, code),
    allergies: list(raw.allergies, 15, code),
  };
  return { week };
}

const LANG = {
  en: 'Write in plain, everyday English and talk to the reader as "you".',
  nl: 'Schrijf in eenvoudig, alledaags Nederlands (zoals in Vlaanderen en Nederland gesproken wordt). Spreek de lezer aan met "je" en schrijf actief ("je at", niet "er werd gegeten"). Alle tekst in het Nederlands.',
};

// De systeemprompt: kort, vriendelijk, concreet, veilig
export function systemPrompt(lang) {
  return [
    'You write the weekly check-in inside a food diary app. You get one week of numbers as JSON and answer with strict JSON only:',
    '{"summary": "...", "tips": ["...", "..."]}',
    '',
    'summary: at most 120 words. Say plainly how the week went, starting with something that went well. Use the numbers,',
    'but round them and keep it readable. No greeting, no sign-off, no headings, no lists, no emoji, no markdown.',
    'tips: 2 or 3 tips for next week. Each tip is one or two short sentences about a concrete food or meal change',
    '(for example "add a handful of lentils to your soup or salad a few times this week"), aimed at the biggest gaps.',
    '',
    'About the data: energy_kcal.goal already includes the plan in "goal" (for "lose" it is already a gentle deficit),',
    'so eating close to it is right; never push below it. nutrient_score (0-100) is how close the vitamins and minerals',
    'came to their targets. below_target lists the nutrients furthest under target (in % of target); above_upper_limit',
    'lists what went over a safe upper limit (in % of that limit). Macros are grams per day against the target.',
    'Base the tips on the biggest gaps first: below_target, protein and fibre under target, and anything in above_upper_limit',
    '(for sodium: less salty processed food, not "less food"). Name specific, ordinary foods for each tip.',
    'Do not call foods "high calorie" or "bad". Never suggest salt, seaweed or iodised salt when sodium is over its limit.',
    'In the summary, pick the two or three numbers that matter most instead of listing them all.',
    '',
    'Rules:',
    '- Sound like a calm, kind person, not a marketing text. No hype, no exclamation marks, no "great job!", no "journey".',
    '- Never shame or blame. Missing a target is normal; talk about what to try next.',
    '- No medical advice, no diagnosis, no talk of diseases or deficiencies as a condition.',
    '- Supplements: at most say "consider" one, never a dose or amount.',
    '- Never suggest eating less than the energy goal, skipping meals, fasting, detoxes or any extreme or restrictive diet.',
    '- If the goal is "lose", keep the deficit gentle. If energy is far below the goal, encourage eating enough.',
    '- Only if values are far off (energy under 60% of the goal, or a nutrient over 200% of its upper limit),',
    '  add one short, calm line suggesting to talk with a doctor or dietitian. Otherwise do not mention them.',
    '- Respect every item in "diet" and "allergies": never suggest a food that conflicts with them.',
    '  For example: vegetarian means no meat or fish, vegan also no dairy, eggs or honey, gluten_free no wheat, rye or barley.',
    '- Use the foods in "top_foods_by_energy" only to make tips fit what this person already eats.',
    '- Do not invent numbers that are not in the data.',
    LANG[lang] ?? LANG.en,
  ].join('\n');
}

// Een tip met een dosis ("400 mg", "1000 IU") of een caloriedoel past niet bij wat we beloven: die valt weg
const DOSE = /\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|iu|ie)\b/i;
const KCAL_TARGET = /\b(?:eat|aim for|eet|mik op|houd)\b[^.]{0,30}\b\d{3,4}\s*(?:kcal|calories|calorieën)\b/i;

function cleanText(v, max) {
  if (typeof v !== 'string') return null;
  const t = stripMarkdown(v).replace(/^["']|["']$/g, '').trim();
  return t ? t.slice(0, max) : null;
}

// Het antwoord van het model nakijken: {summary, tips} met 1 tot 3 tips. Geeft {summary, tips} of {error}.
export function cleanCoach(raw) {
  if (!raw || typeof raw !== 'object') return { error: 'bad_output' };
  const summary = cleanText(raw.summary, 1000);
  if (!summary || summary.length < 20) return { error: 'bad_output' };
  const tips = (Array.isArray(raw.tips) ? raw.tips : [])
    .map((t) => cleanText(typeof t === 'object' && t ? (t.tip ?? t.text) : t, 320))
    .filter((t) => t && t.length >= 10 && !DOSE.test(t) && !KCAL_TARGET.test(t))
    .slice(0, 3);
  if (tips.length === 0) return { error: 'bad_output' };
  return { summary, tips };
}

const SCHEMA = {
  type: 'object',
  properties: { summary: { type: 'string' }, tips: { type: 'array', items: { type: 'string' } } },
  required: ['summary', 'tips'],
};

// De vraag aan het model (ook bruikbaar om de prompt los te proberen)
export function coachInput(week) {
  return {
    messages: [
      { role: 'system', content: systemPrompt(week.lang) },
      { role: 'user', content: JSON.stringify(week) },
    ],
    response_format: { type: 'json_schema', json_schema: SCHEMA },
    max_tokens: 600,
    temperature: 0.4,
  };
}

async function readWeek(request) {
  const declared = Number(request.headers.get('Content-Length') ?? 0);
  if (declared > MAX_INPUT_BYTES) return { error: json({ error: 'too_big' }, 413) };
  let text;
  try {
    text = await request.text();
  } catch (_) {
    return { error: json({ error: 'bad_input' }, 400) };
  }
  if (new TextEncoder().encode(text).length > MAX_INPUT_BYTES) return { error: json({ error: 'too_big' }, 413) };
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (_) {
    return { error: json({ error: 'bad_input' }, 400) };
  }
  const c = cleanWeek(raw);
  if (c.error) return { error: json({ error: c.error }, 400) };
  return { week: c.week };
}

export async function onRequestPost({ request, env }) {
  if (!env.AI) return json({ error: 'not_configured' }, 503);
  const who = await checkLogin(request);
  if (who.error) return who.error;

  const input = await readWeek(request);
  if (input.error) return input.error;

  const rate = await hourly('coach', who.user, PER_HOUR);
  if (!rate.allowed) return json({ error: 'too_many' }, 429);

  // De dagteller pas na de controles hierboven. Zonder teller geen coach: die zegt ook of je al mag (vroege toegang).
  const q = await aiQuotaStatus(who.auth, 'coach');
  if (q.missing) return json({ error: 'not_configured' }, 503);
  if (!q.quota) return json({ error: 'failed' }, 502);
  const quota = { used: q.quota.used, limit: q.quota.limit, pro: q.quota.pro };
  if (!q.quota.allowed) return json({ error: 'quota', ...quota }, 429);
  await rate.count();

  try {
    const r = await withTimeout(env.AI.run(TEXT_MODEL, coachInput(input.week)), Number(env.COACH_TIMEOUT_MS) || TIMEOUT_MS);
    const out = cleanCoach(modelObject(r));
    if (out.error) return json({ error: out.error, quota }, 502);
    return json({ ...out, lang: input.week.lang, quota });
  } catch (e) {
    if (e instanceof TimeoutError) return json({ error: 'timeout', quota }, 504);
    return json({ error: 'failed', quota }, 502);
  }
}
