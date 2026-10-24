// Cloudflare Pages Function: de wekelijkse coach. De app stuurt een kleine samenvatting van je week in cijfers
// (dagen gelogd, Voedingsscore, energie en macro's tegenover je doel, de stoffen die het verst onder je doel zitten of
// boven een bovengrens, je gewichtstrend, je doel, de 5 producten met de meeste energie als gewone namen, en je
// voorkeuren en allergieën als codes, een paar gewone voedingsmiddelen met een portie die je tekorten aanvullen (uit het
// Orakel van de app) en de tips van vorige week met hoe die stoffen sindsdien veranderden). Geen dagboek, geen namen,
// geen notities. Een tekstmodel van Workers AI schrijft
// daarmee een korte samenvatting en 2 à 3 tips voor volgende week, in het Engels of het Nederlands.
// Alleen voor ingelogde gebruikers. Er wordt niets bewaard: niet wat de app stuurt, niet wat het model schrijft.
// Dagteller ai_quota_use('coach'): 3 met Pro, 1 zonder Pro maar pas als de functie voor iedereen open staat
// (migratie 20261103000000_coach). Anders dan bij /api/label werkt dit niet zonder teller: die houdt ook de vroege
// toegang bij. Ontbreekt de migratie, dan not_configured (de app verbergt de coach dan).

import { aiQuotaStatus, checkLogin, hourly, json, modelObject, stripMarkdown, TimeoutError, withTimeout } from '../_lib/ai.js';

// Groot en goed in het Nederlands, en snel genoeg voor een paar honderd woorden
// Gekozen na een vergelijking op echte weekcijfers: concretere tips dan Llama 3.3 70B, en goedkoper per antwoord
export const TEXT_MODEL = '@cf/openai/gpt-oss-120b';

// Wat de app stuurt is 1 à 3 kB (met voorstellen en de tips van vorige week); alles boven deze grens is geen weekoverzicht
export const MAX_INPUT_BYTES = 6000;
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

// Een zin van de coach van vorige week (die de app bewaarde): gewone tekst zonder links of opmaak
function sentence(v, max = 200) {
  if (typeof v !== 'string') return null;
  const t = v
    .normalize('NFC')
    .replace(/[^\p{L}\p{N} ,.;:'"()%/&+?!-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length < 5 || /https?|www\./i.test(t)) return null;
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
  // Voorstellen per tekort: {stof: [{food, portion, pct}]}, hoogstens 5 stoffen met elk 4 voedingsmiddelen
  const options = {};
  if (raw.options && typeof raw.options === 'object' && !Array.isArray(raw.options)) {
    for (const [k, v] of Object.entries(raw.options).slice(0, 5)) {
      const name = label(k);
      const foods = list(v, 4, (x) => {
        const food = label(x?.food, 50);
        const portion = label(x?.portion, 30);
        const pct = num(x?.pct, 0, 2000);
        return food && portion && pct != null ? { food, portion, pct } : null;
      });
      if (name && foods.length) options[name] = foods;
    }
  }
  // Vorige week: de tips van toen en hoe die stoffen veranderden (in % van het doel)
  let lastWeek = null;
  if (raw.last_week && typeof raw.last_week === 'object' && !Array.isArray(raw.last_week)) {
    const tips = list(raw.last_week.tips, 3, (x) => sentence(x));
    const changes = list(raw.last_week.changes, 5, (x) => {
      const nutrient = label(x?.nutrient);
      const before = num(x?.before_pct, 0, 1000);
      const now = num(x?.now_pct, 0, 1000);
      return nutrient && before != null && now != null ? { nutrient, before_pct: before, now_pct: now } : null;
    });
    if (tips.length || changes.length) lastWeek = { tips, changes };
  }
  const energy = pair(raw.energy, 10000);
  const goal = GOALS.has(raw.goal) ? raw.goal : 'maintain';
  // Al uitgerekend, zodat het model niet zelf moet rekenen: duidelijk boven het doel (afvallen of behouden) of ver eronder
  const ratio = energy?.goal ? energy.avg / energy.goal : null;
  const energyNote =
    ratio == null ? null : ratio > 1.1 && goal !== 'gain' ? 'clearly_above_goal' : ratio < 0.75 ? 'far_below_goal' : null;
  const week = {
    lang,
    days_logged: days,
    nutrient_score: num(raw.score, 0, 100),
    goal,
    energy_kcal: energy,
    energy_note: energyNote,
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
    options,
    last_week: lastWeek,
  };
  return { week };
}

const LANG = {
  en: 'Write in plain, everyday English and talk to the reader as "you". All text in English, also the food names.',
  nl: 'Schrijf in eenvoudig, alledaags Nederlands (zoals in Vlaanderen en Nederland gesproken wordt). Spreek de lezer aan met "je" en schrijf actief ("je at", niet "er werd gegeten"). Gebruik gewone woorden ("groenten", "peulvruchten", "een handvol") en geen Engelse woorden zoals "target", "boost" of "focussen" (zeg "doel", "extra", "let op"). Alle tekst in het Nederlands, ook de namen van voedingsmiddelen.',
};

// Eén voorbeeld in de gevraagde taal (nooit beide: dan antwoordt het model soms in de verkeerde taal). Rustig, concreet,
// korte zinnen, geen cijfers die al boven de tekst staan.
export const EXAMPLES = {
  en: '{"summary": "Last week you planned more fibre, and it went from 67% to 80% of your target. Your muesli breakfasts gave the week a steady base. Next week, vitamin K and potassium are worth some attention.", "tips": ["Stir 80 g of cooked spinach into your pasta with meat sauce two or three times this week.", "Sprinkle a handful of sunflower seeds over your muesli in the morning.", "Have a smaller portion of sweet potato fries with a side salad, and drink water with dinner."]}',
  nl: '{"summary": "Vorige week wilde je meer vezels eten, en dat lukte: van 67% naar 80% van je doel. Je ontbijt met muesli gaf de week een goede basis. Volgende week loont het om op vitamine K en kalium te letten.", "tips": ["Roer deze week twee of drie keer 80 g gekookte spinazie door je pasta met gehaktsaus.", "Strooi \'s ochtends een handvol zonnebloempitten over je muesli.", "Neem een kleinere portie zoete-aardappelfrietjes met een slaatje erbij, en drink water bij het avondeten."]}',
};

export const LANG_NAME = { en: 'English', nl: 'Dutch' };

// De systeemprompt: kort, vriendelijk, concreet, veilig
export function systemPrompt(lang) {
  const l = LANG[lang] ? lang : 'en';
  return [
    'You write the weekly check-in inside a food diary app. You get one week of numbers as JSON and answer with strict JSON only:',
    '{"summary": "...", "tips": ["...", "..."]}',
    '',
    'summary: 2 or 3 short sentences, at most 60 words in total. Hard limit: never more than 3 sentences, and keep each',
    'sentence under 20 words. The app already shows the nutrient score, the average energy against the goal and the',
    'biggest gap right above your text, so do not repeat those numbers, and do not list which macros were above or below',
    'their goal. Do not mention energy, kcal, carbs or fat in the summary at all: energy gets one tip of its own when',
    'energy_note asks for it. Say each thing only once. Say what went well and which one or two nutrients are worth',
    'focusing on next week, in plain words. No percentages in the summary, except the one before/now pair from last_week.',
    'No greeting, no sign-off, no headings, no lists, no emoji, no markdown.',
    'Write "kcal", never "calories". Write foods as ordinary lowercase words ("muesli", "pasta with meat sauce"), not as',
    'database names.',
    'tips: 2 or 3 tips for next week. Each tip is one or two short sentences about a concrete food or meal change,',
    'with a normal amount, aimed at the biggest gaps.',
    '',
    'About the data: energy_kcal.goal already includes the plan in "goal" (for "lose" it is already a gentle deficit),',
    'so eating close to it is right; never push below it. nutrient_score (0-100) is how close the vitamins and minerals',
    'came to their targets. below_target lists the nutrients furthest under target (in % of target); above_upper_limit',
    'lists what went over a safe upper limit (in % of that limit). Macros are grams per day against the target.',
    'Base the tips on the biggest gaps first: below_target, protein and fibre under target, and anything in above_upper_limit',
    '(for sodium: less salty processed food, not "less food").',
    'Do not call foods "high calorie" or "bad". Never suggest salt, seaweed or iodised salt when sodium is over its limit.',
    '',
    'options: for each gap nutrient, a few everyday foods that already fit this person\'s diet and allergies, each with a',
    'normal portion and how much of that nutrient\'s daily target that portion gives (pct). When options is not empty,',
    'every tip must use one or more foods from options, with their portion, and may combine them with a food from',
    'top_foods_by_energy (for example "stir 80 g of cooked spinach into your pasta with meat sauce"). Do not suggest any',
    'other food to fill a gap. Never write the pct number itself; at most say it in plain words ("about half of your',
    'daily vitamin E", "all the vitamin K you need for the day").',
    'When options is empty, choose ordinary, specific foods yourself.',
    '',
    'energy_note: if it is "clearly_above_goal", one of the tips is about energy: a mild, concrete swap based on',
    'top_foods_by_energy or options, such as a smaller portion of fries with a side salad, water instead of a sweet drink,',
    'or half the usual pasta with extra vegetables. Never suggest eating below the goal, skipping meals or fasting, and',
    'do not give a kcal number. If it is "far_below_goal", gently encourage eating enough (for example an extra snack',
    'or a fuller lunch) instead.',
    '',
    'last_week: if present, these are the tips from last week and, per nutrient, the average before and now (in % of',
    'target). Then the summary starts with one short sentence on how last week\'s plan went, using one before/now pair',
    '(preferably the one that improved most), honest and kind. If nothing improved, say so gently ("fibre stayed about',
    'the same") and move on. Never shame.',
    'Without last_week, do not talk about last week.',
    '',
    'Rules:',
    '- Sound like a calm, kind person, not a marketing text. No hype, no exclamation marks, no "great job", no "journey".',
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
    '',
    'Example of the tone and length (this person had last_week, fibre as a past gap and energy clearly above the goal;',
    'use your own data, not these foods or numbers):',
    EXAMPLES[l],
    '',
    LANG[l],
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

// Hoogstens zoveel woorden in de samenvatting; de prompt vraagt er 60, maar het model schrijft soms veel meer
export const MAX_SUMMARY_WORDS = 90;

const words = (t) => t.split(/\s+/).filter(Boolean).length;

// Een te lange samenvatting inkorten op het einde van een zin. Is de eerste zin al te lang, dan die op een woord.
export function trimSummary(t, max = MAX_SUMMARY_WORDS) {
  if (words(t) <= max) return t;
  const sentences = t.match(/[^.!?]+(?:[.!?]+["')]*|$)\s*/g) ?? [t];
  let out = '';
  for (const z of sentences) {
    if (words(out + z) > max) break;
    out += z;
  }
  if (out.trim()) return out.trim();
  return `${t.split(/\s+/).slice(0, max).join(' ').replace(/[,;:]$/, '')}…`;
}

// Gewone woordjes per taal, om te zien of het model in de gevraagde taal schreef
const STOP = {
  nl: new Set(['de', 'het', 'een', 'je', 'en', 'van', 'met', 'voor', 'niet', 'wat']),
  en: new Set(['the', 'a', 'and', 'you', 'your', 'with', 'for', 'of', 'to']),
};

// Duidelijk in de andere taal geschreven: minstens 4 woordjes van die taal en meer dan dubbel zoveel als van de eigen
export function wrongLanguage(text, lang) {
  const want = lang === 'nl' ? 'nl' : 'en';
  const other = want === 'nl' ? 'en' : 'nl';
  const n = { nl: 0, en: 0 };
  for (const w of String(text ?? '').toLowerCase().split(/[^\p{L}']+/u)) {
    if (STOP.nl.has(w)) n.nl++;
    if (STOP.en.has(w)) n.en++;
  }
  return n[other] >= 4 && n[other] > 2 * n[want];
}

// Het antwoord van het model nakijken: {summary, tips} met 1 tot 3 tips. Geeft {summary, tips} of {error}.
export function cleanCoach(raw) {
  if (!raw || typeof raw !== 'object') return { error: 'bad_output' };
  const text = cleanText(raw.summary, 1000);
  const summary = text && trimSummary(text);
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

// De vraag aan het model (ook bruikbaar om de prompt los te proberen). [retry]: tweede poging na een antwoord in de
// verkeerde taal, met die taal nog eens apart gevraagd.
export function coachInput(week, { retry = false } = {}) {
  const system = systemPrompt(week.lang) + (retry ? `\nAnswer only in ${LANG_NAME[week.lang] ?? 'English'}.` : '');
  return {
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: JSON.stringify(week) },
    ],
    response_format: { type: 'json_schema', json_schema: SCHEMA },
    // Dit model denkt eerst na. Met weinig nadenken is het antwoord er in 3 à 6 s in plaats van 10 à 20 s, met even
    // goede tips (gemeten met wrangler); 'reasoning: {effort}' maakte het eerder trager.
    reasoning_effort: 'low',
    // Het nadenken telt mee; met 600 viel het antwoord soms weg
    max_tokens: 1200,
    temperature: 0.4,
  };
}

// Model vragen en nakijken, met één nieuwe poging als het in de verkeerde taal antwoordde. Gooit TimeoutError als
// [ms] samen op is.
export async function askCoach(ai, week, ms) {
  const deadline = Date.now() + ms;
  let out;
  for (const retry of [false, true]) {
    const left = deadline - Date.now();
    if (left <= 0) throw new TimeoutError(`na ${ms} ms`);
    const r = await withTimeout(ai.run(TEXT_MODEL, coachInput(week, { retry })), left);
    out = cleanCoach(modelObject(r));
    if (out.error) return out;
    if (!wrongLanguage(`${out.summary} ${out.tips.join(' ')}`, week.lang)) return out;
  }
  return { error: 'bad_output' };
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
    const out = await askCoach(env.AI, input.week, Number(env.COACH_TIMEOUT_MS) || TIMEOUT_MS);
    if (out.error) return json({ error: out.error, quota }, 502);
    return json({ ...out, lang: input.week.lang, quota });
  } catch (e) {
    if (e instanceof TimeoutError) return json({ error: 'timeout', quota }, 504);
    return json({ error: 'failed', quota }, 502);
  }
}
