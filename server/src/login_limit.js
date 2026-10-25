// Inloglimiet per IP + e-mailadres: hoogstens [PER_MINUTE] mislukte pogingen (of verstuurde codes) per minuut voor
// dezelfde combinatie, exact (een teller in D1, migratie 0005). Better Auth telt zelf alleen per IP en pad; die limiet staat ruim (src/auth.js), alleen
// tegen grof misbruik vanaf één netwerk. Zo sluit één persoon op een gedeeld netwerk de anderen niet buiten.
const PER_MINUTE = 10;
const WINDOW_MS = 60_000;

/** De paden waar een e-mailadres in zit en die geraden of misbruikt kunnen worden. */
export const LIMITED_PATHS = new Set([
  '/auth/sign-in/email',
  '/auth/email-otp/send-verification-otp',
  '/auth/email-otp/verify-email',
  '/auth/forget-password/email-otp',
  '/auth/email-otp/reset-password',
]);

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

/** Het e-mailadres uit het verzoek (zonder het verzoek zelf te verbruiken), of '' als er geen is. */
async function emailOf(request) {
  try {
    const b = await request.clone().json();
    return typeof b?.email === 'string' ? b.email.trim().toLowerCase().slice(0, 320) : '';
  } catch {
    return '';
  }
}

/** De sleutel: een hash van IP en e-mailadres (met een eigen voorvoegsel, zodat hij nergens anders op lijkt). */
export async function loginKey(ip, email) {
  return hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`login\n${ip}\n${email}`)));
}

/** Paden die een mail versturen: daar telt elke aanvraag (het misbruik is de mail zelf). Elders alleen mislukte. */
const SENDS_MAIL = new Set(['/auth/email-otp/send-verification-otp', '/auth/forget-password/email-otp']);

/**
 * Vóór Better Auth: zit deze combinatie van IP en e-mailadres al aan de limiet? Geeft null voor andere paden, anders
 * { blocked, done(ok) }: na het antwoord done(res.ok) oproepen, dat telt de poging als ze mislukte (of een mail
 * verstuurde). Zo telt een geslaagde inlog niet mee, en een reeks foute wachtwoorden wel.
 */
export async function loginGate(db, request, path, ip, now = Date.now()) {
  if (request.method !== 'POST' || !LIMITED_PATHS.has(path)) return null;
  const key = await loginKey(ip, await emailOf(request));
  const start = Math.floor(now / WINDOW_MS) * WINDOW_MS;
  const count = (await db.prepare('SELECT count FROM login_limits WHERE key = ? AND window_start = ?').bind(key, start).first('count')) ?? 0;
  return {
    blocked: count >= PER_MINUTE,
    async done(ok) {
      if (ok && !SENDS_MAIL.has(path)) return;
      await db
        .prepare(
          `INSERT INTO login_limits (key, window_start, count) VALUES (?, ?, 1)
           ON CONFLICT (key) DO UPDATE SET count = CASE WHEN window_start = excluded.window_start THEN count + 1 ELSE 1 END,
             window_start = excluded.window_start`,
        )
        .bind(key, start)
        .run();
    },
  };
}
