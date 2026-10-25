// Cloudflare Pages Function: de wekelijkse coach. De app stuurt een kleine samenvatting van je week in cijfers
// (dagen gelogd, Voedingsscore, energie en macro's tegenover je doel, de stoffen die het verst onder je doel zitten of
// boven een bovengrens, je gewichtstrend, je doel, de 5 producten met de meeste energie als gewone namen, en je
// voorkeuren en allergieën als codes, een paar gewone voedingsmiddelen met een portie die je tekorten aanvullen (uit het
// Orakel van de app) en de tips van vorige week met hoe die stoffen sindsdien veranderden). Geen dagboek, geen namen,
// geen notities. Een tekstmodel van Workers AI schrijft
// daarmee een korte samenvatting en 2 à 3 tips voor volgende week, in het Engels of het Nederlands.
// Alleen voor ingelogde gebruikers. Er wordt niets bewaard: niet wat de app stuurt, niet wat het model schrijft (tenzij
// de gebruiker de tekst in de app meldt: dan bewaart ai_report die, migratie 20261105000000_ai_reports).
// Dagteller ai_quota_use('coach'): 3 met Pro, 1 zonder Pro maar pas als de functie voor iedereen open staat
// (migratie 20261103000000_coach). Anders dan bij /api/label werkt dit niet zonder teller: die houdt ook de vroege
// toegang bij. Ontbreekt de migratie, dan not_configured (de app verbergt de coach dan).

import { aiQuotaStatus, checkLogin, hourly, json, modelObject, stripMarkdown, TimeoutError, withTimeout } from '../_lib/ai.js';
import { readBytes } from '../_lib/body.js';

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
    if (p) macros[k] = { ...p, unit: 'g', pct_of_target: p.goal ? Math.round((100 * p.avg) / p.goal) : null };
  }
  // Macro's onder hun doel als uitdrukkelijk tekort met %, zodat het model eiwit op 47 % niet als "een goede basis"
  // ziet (SU-2): het las de grammen eerder niet als tekort
  const macroGaps = Object.entries(macros)
    .filter(([, m]) => m.pct_of_target != null && m.pct_of_target < 90)
    .map(([k, m]) => ({ nutrient: k, pct_of_target: m.pct_of_target }))
    .sort((a, b) => a.pct_of_target - b.pct_of_target);
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
  const belowTarget = list(raw.low, 5, (x) => {
    const name = label(x?.name);
    const pct = num(x?.pct, 0, 1000);
    return name && pct != null ? { nutrient: name, pct_of_target: pct } : null;
  });
  // Hoeveel kcal per dag er ontbreekt, als het duidelijk minder is dan het doel: zo kan de tip even groot zijn
  const energyGap = ratio != null && ratio < 0.9 ? Math.round(energy.goal - energy.avg) : null;
  // Alles onder 80 % van het doel: dat mag de coach nooit prijzen
  const under80 = [
    ...(ratio != null && ratio < 0.8 ? ['energy'] : []),
    ...macroGaps.filter((m) => m.pct_of_target < 80).map((m) => m.nutrient),
    ...belowTarget.filter((b) => b.pct_of_target < 80).map((b) => b.nutrient),
  ];
  const week = {
    lang,
    days_logged: days,
    nutrient_score: num(raw.score, 0, 100),
    goal,
    energy_kcal: energy,
    energy_note: energyNote,
    energy_gap_kcal_per_day: energyGap,
    macros,
    macros_below_target: macroGaps,
    below_target: belowTarget,
    never_praise: under80,
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
    'macros_below_target lists the macros under target with their % of target; protein there is a real gap, as',
    'important as anything in below_target.',
    'Base the tips on the biggest gaps first: below_target, macros_below_target (protein and fibre), and anything in',
    'above_upper_limit (for sodium: less salty processed food, not "less food").',
    'never_praise lists everything under 80% of its target. Never call any of these good, steady, solid, enough or a',
    'base, and never say they "went well": they are things to work on. Only praise what is not in never_praise.',
    'When protein is in never_praise, the summary names protein as one of the things to work on.',
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
    'do not give a kcal number. If it is "far_below_goal", one tip is about eating enough instead, and its size must',
    'match energy_gap_kcal_per_day (the kcal per day still missing). For "maintain" or "gain" with a big gap (400 kcal',
    'or more), suggest additions that together come close to that amount, for example a fuller lunch plus a snack such',
    'as yoghurt with granola and a handful of nuts, and say "about N kcal more a day" (N is energy_gap_kcal_per_day',
    'rounded to 50). Never call a big gap "a bit more", "a little more" or "slightly larger", and one banana is not',
    'enough for it. For "lose", gently',
    'encourage eating enough (an extra snack or a fuller lunch).',
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
    '- In the app, nutrient_score is called "Nutrient score" in English and "Voedingsscore" in Dutch; use only that name.',
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
// "about 800 kcal more a day" is een aanvulling (SU-2), geen caloriedoel
const MORE = /\b(?:more|extra|additional|meer)\b/i;
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
    .filter((t) => t && t.length >= 10 && !DOSE.test(t) && !(KCAL_TARGET.test(t) && !MORE.test(t)))
    .slice(0, 3);
  if (tips.length === 0) return { error: 'bad_output' };
  return { summary, tips };
}

const SCHEMA = {
  type: 'object',
  properties: { summary: { type: 'string' }, tips: { type: 'array', items: { type: 'string' } } },
  required: ['summary', 'tips'],
};

// --- Nakijken of de samenvatting de cijfers tegenspreekt (SU-2): "a steady base of protein" bij 47 % eiwit, of
// "a bit more energy" bij 800 kcal per dag tekort. Bewust eenvoudig: per zin een woord voor de stof met in de buurt
// een lovend woord en geen woord dat het tekort benoemt.

const ESC = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Woorden voor de macro's en voor energie, in beide talen
const NUTRIENT_WORDS = {
  energy: 'energy|energie|kcal|calories?|calorieën|intake|inname',
  protein: 'proteins?|eiwit(?:ten)?',
  fiber: 'fib(?:er|re)s?|vezels?',
  carbs: 'carbs?|carbohydrates?|koolhydraten',
  fat: 'fats?|vetten|vet',
};
const POSITIVE =
  /\b(?:good|great|steady|solid|strong|enough|plenty|ample|nice|healthy|decent|balanced|base|went well|did well|on track|goede?|stevige?|degelijke?|voldoende|genoeg|mooie?|basis|prima|sterke?)\b/i;
const NEGATIVE =
  /\b(?:low|lower|below|under|short|less|lack\w*|miss\w*|few|deficit|gap|not|far|more|increase|raise|work on|lage?|onder|weinig|tekort|meer|niet|mist|ver)\b/i;
// "a bit more energy" bij een groot tekort
const SMALL = /\b(?:a bit|a little|slightly|somewhat|a touch|a tad|een beetje|een tikje|iets meer|wat meer)\b/i;

// Het stuk van de zin rond elke vermelding van [re]
function windows(sentence, re) {
  const out = [];
  for (const m of sentence.matchAll(new RegExp(`\\b(?:${re})\\b`, 'gi'))) {
    out.push(sentence.slice(Math.max(0, m.index - 35), m.index + m[0].length + 40));
  }
  return out;
}

const splitSentences = (t) => (t.match(/[^.!?]+(?:[.!?]+["')]*|$)\s*/g) ?? [t]).map((z) => z.trim()).filter(Boolean);

// De zinnen van [summary] die iets onder 80 % van het doel prijzen, of een groot energietekort klein maken
export function contradictions(summary, week) {
  const low = week.never_praise ?? [];
  if (!low.length) return [];
  const words = low.map((n) => NUTRIENT_WORDS[n] ?? ESC(String(n).toLowerCase()));
  const ratio = week.energy_kcal?.goal ? week.energy_kcal.avg / week.energy_kcal.goal : null;
  const bigGap = ratio != null && ratio < 0.75;
  return splitSentences(summary).filter((z) => {
    if (words.some((w) => windows(z, w).some((x) => POSITIVE.test(x) && !NEGATIVE.test(x)))) return true;
    return bigGap && windows(z, NUTRIENT_WORDS.energy).some((x) => SMALL.test(x));
  });
}

// De tips die een groot energietekort klein maken ("a slightly larger serving", "a bit more rice") bij behouden of
// aankomen: daar hoort een tip van de grootte van het tekort
export function smallEnergyTips(tips, week) {
  const gap = week.energy_gap_kcal_per_day ?? 0;
  if (week.goal === 'lose' || gap < 400) return [];
  const energy = new RegExp(`\\b(?:${NUTRIENT_WORDS.energy})\\b`, 'i');
  return tips.filter((t) => energy.test(t) && SMALL.test(t));
}

// De correctie bij de tweede poging: wat fout was en de echte cijfers
export function correctionText(bad, week) {
  const facts = [
    ...(week.energy_kcal?.goal && week.energy_gap_kcal_per_day
      ? [`energy is ${Math.round((100 * week.energy_kcal.avg) / week.energy_kcal.goal)}% of the goal (${week.energy_gap_kcal_per_day} kcal a day short)`]
      : []),
    ...(week.macros_below_target ?? []).map((m) => `${m.nutrient} is ${m.pct_of_target}% of target`),
    ...(week.below_target ?? []).map((b) => `${b.nutrient} is ${b.pct_of_target}% of target`),
  ];
  return [
    `Your previous answer contradicted the data: ${bad.map((z) => `"${z}"`).join(' ')}`,
    `The facts: ${facts.join('; ')}.`,
    'Write it again. Do not praise anything in never_praise, and size the energy tip to the real gap.',
  ].join('\n');
}

// De vraag aan het model (ook bruikbaar om de prompt los te proberen). [retry]: tweede poging na een antwoord in de
// verkeerde taal, met die taal nog eens apart gevraagd. [correction]: tweede poging na een tegenspraak.
export function coachInput(week, { retry = false, correction = null } = {}) {
  const system =
    systemPrompt(week.lang) +
    (retry ? `\nAnswer only in ${LANG_NAME[week.lang] ?? 'English'}.` : '') +
    (correction ? `\n\n${correction}` : '');
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

// Model vragen en nakijken, met hoogstens één nieuwe poging: als het in de verkeerde taal antwoordde, of als de
// samenvatting de cijfers tegensprak. Spreekt ook de tweede die nog tegen, dan vallen die zinnen weg. Gooit
// TimeoutError als [ms] samen op is.
export async function askCoach(ai, week, ms) {
  const deadline = Date.now() + ms;
  let opts = {};
  for (const last of [false, true]) {
    const left = deadline - Date.now();
    if (left <= 0) throw new TimeoutError(`na ${ms} ms`);
    const r = await withTimeout(ai.run(TEXT_MODEL, coachInput(week, opts)), left);
    const out = cleanCoach(modelObject(r));
    if (out.error) return out;
    if (wrongLanguage(`${out.summary} ${out.tips.join(' ')}`, week.lang)) {
      if (last) return { error: 'bad_output' };
      opts = { retry: true };
      continue;
    }
    const bad = contradictions(out.summary, week);
    const small = smallEnergyTips(out.tips, week);
    if (!bad.length && !small.length) return out;
    if (!last) {
      opts = { correction: correctionText([...bad, ...small], week) };
      continue;
    }
    const summary = splitSentences(out.summary)
      .filter((z) => !bad.includes(z))
      .join(' ');
    // Een te kleine energietip valt weg, zolang er een andere tip overblijft
    const tips = out.tips.length > small.length ? out.tips.filter((t) => !small.includes(t)) : out.tips;
    return summary.length >= 20 ? { summary, tips } : { error: 'bad_output' };
  }
  return { error: 'bad_output' };
}

async function readWeek(request) {
  const read = await readBytes(request, MAX_INPUT_BYTES);
  if (read.error) return { error: read.error };
  if (read.bad) return { error: json({ error: 'bad_input' }, 400) };
  let raw;
  try {
    raw = JSON.parse(new TextDecoder().decode(read.bytes));
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
    // Het model gaat mee, zodat een melding van de tekst (ai_report) zegt welk model hem schreef
    return json({ ...out, lang: input.week.lang, model: TEXT_MODEL, quota });
  } catch (e) {
    if (e instanceof TimeoutError) return json({ error: 'timeout', quota }, 504);
    return json({ error: 'failed', quota }, 502);
  }
}
