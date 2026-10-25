// Hulpfuncties die meerdere groepen RPC's gebruiken (vertaald uit Supabase: are_friends, blocked_words,
// blocked_stems, text_blocked, pro_active).

/** Zijn a en b vrienden (geaccepteerd)? Zoals are_friends: alleen als de vrager zelf a of b is. */
export async function areFriends(db, me, a, b) {
  if (me !== a && me !== b) return false;
  const r = await db
    .prepare('SELECT 1 FROM friendships WHERE accepted = 1 AND ((requester = ? AND addressee = ?) OR (requester = ? AND addressee = ?)) LIMIT 1')
    .bind(a, b, b, a)
    .first();
  return r !== null;
}

/** Heeft deze gebruiker nu een lopend Supporter-abonnement (pro_status.until in de toekomst)? */
export async function proActive(db, uid, now = new Date()) {
  return (await db.prepare('SELECT 1 FROM pro_status WHERE user_id = ? AND until > ? LIMIT 1').bind(uid, now.toISOString()).first()) !== null;
}

export const BLOCKED_STEMS = ['fuck', 'motherfuck', 'cunt', 'nigger', 'faggot', 'whore', 'slut', 'cocksuck', 'porn'];

export const BLOCKED_WORDS = [
  // Engels
  'shit', 'shits', 'shitty', 'shithead', 'bullshit', 'bitch', 'bitches', 'bitchy', 'asshole', 'assholes',
  'arsehole', 'arseholes', 'dickhead', 'dickheads', 'pussy', 'bastard', 'bastards', 'wanker', 'wankers', 'wanking',
  'twat', 'twats', 'retard', 'retarded', 'retards', 'tranny', 'trannies', 'kike', 'kikes', 'nazi', 'nazis',
  'hitler', 'kkk', 'nigga', 'niggas', 'niggaz', 'rapist', 'rapists', 'pedo', 'paedo', 'pedophile', 'paedophile', 'kys',
  'heil hitler', 'sieg heil', 'white power', 'kill yourself',
  // Nederlands
  'kut', 'kutje', 'kutwijf', 'kutwijven', 'klootzak', 'klootzakken', 'lul', 'hoer', 'hoeren', 'hoerig',
  'hoerenzoon', 'kankerlijer', 'kankerhoer', 'kankerjood', 'kankerwijf', 'kankerzooi', 'kankermongool',
  'kankerhomo', 'kankerneger', 'tering', 'teringlijer', 'tyfus', 'tyfuslijer', 'pleurislijer', 'godverdomme',
  'godverdomse', 'neuk', 'neuken', 'neuker', 'neukt', 'flikker', 'flikkers', 'nikker', 'nikkers', 'mongool',
  'mongolen', 'slet', 'sletten', 'sletje',
];

const FROM = 'áàâäãåéèêëíìîïóòôöõúùûüçñ013457@$';
const TO = 'aaaaaaeeeeiiiiooooouuuucnoieastas';

/** Zoals text_blocked in Supabase: scheldwoorden, ook met accenten, cijfers voor letters of herhaalde letters. */
export function textBlocked(p) {
  if (p == null || String(p).trim() === '') return false;
  let t = [...String(p).toLowerCase()].map((c) => (FROM.includes(c) ? TO[FROM.indexOf(c)] : c)).join('');
  t = t.replace(/(.)\1\1+/g, '$1');
  t = ` ${t.replace(/[^a-z]+/g, ' ').trim()} `;
  return BLOCKED_WORDS.some((w) => t.includes(` ${w} `)) || BLOCKED_STEMS.some((s) => t.includes(` ${s}`));
}
