// Inloggen met Better Auth: e-mail + wachtwoord, bevestigen en wachtwoord vergeten met een code van 6 cijfers
// (15 minuten geldig), sessies als Bearer-token (de app gebruikt geen cookies).
//
// Gedrag zoals in Supabase:
// - wachtwoord: minstens 8 tekens, met letters en cijfers;
// - registreren met een adres dat nog niet bevestigd is: nieuw wachtwoord + nieuwe code; met een bevestigd adres een
//   mail "je hebt al een account" (de app krijgt in beide gevallen hetzelfde antwoord);
// - hoogstens 3 nieuwe accounts per uur en 10 per dag vanaf hetzelfde netwerk (was hook_before_user_created);
// - oude wachtwoorden uit Supabase (bcrypt) blijven werken en worden bij het inloggen omgezet.
import { betterAuth } from 'better-auth';
import { APIError, createAuthMiddleware } from 'better-auth/api';
import { hashPassword, verifyPassword } from 'better-auth/crypto';
import { bearer, emailOTP } from 'better-auth/plugins';
import bcrypt from 'bcryptjs';
import { hubFor } from './hub.js';
import { sendMail } from './mail.js';

/** Webversies die de API mogen aanspreken (de app zelf stuurt geen Origin). */
export const WEB_ORIGINS = ['https://macromatrix.eu', 'https://www.macromatrix.eu', 'https://app.divinenet.online'];

const DAY = 24 * 60 * 60;

/** Zelfde regel als in de app (auth_screens.dart) en in Supabase. */
export function passwordProblem(p) {
  if (typeof p !== 'string' || p.length < 8 || !/[A-Za-z]/.test(p) || !/[0-9]/.test(p)) {
    return 'Password must be at least 8 characters, with letters and numbers.';
  }
  return null;
}

/** Wachtwoorden: nieuwe met scrypt (standaard van Better Auth), die uit Supabase met bcrypt. */
export const passwords = {
  hash: (password) => hashPassword(password),
  verify: ({ hash, password }) => (/^\$2[aby]\$/.test(hash) ? bcrypt.compare(password, hash) : verifyPassword({ hash, password })),
};

/** IP-adres als hash (nooit het adres zelf bewaren). */
async function ipHash(env, ip) {
  const data = new TextEncoder().encode(`macromatrix-signup:${env.BETTER_AUTH_SECRET}:${ip}`);
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', data))].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Registratielimiet per netwerk; gooit een 429 als het te veel is, anders telt dit verzoek mee. */
export async function checkSignupLimit(env, ip) {
  if (!ip) return;
  const h = await ipHash(env, ip);
  const now = Date.now();
  const iso = (ms) => new Date(ms).toISOString();
  await env.DB.prepare('DELETE FROM signup_ips WHERE at < ?').bind(iso(now - DAY * 1000)).run();
  // Tellen en bijschrijven in één opdracht: gelijktijdige registraties kunnen er niet samen door
  const r = await env.DB.prepare(
    `INSERT INTO signup_ips (ip_hash, at) SELECT ?1, ?2
     WHERE (SELECT count(*) FROM signup_ips WHERE ip_hash = ?1 AND at > ?3) < 3
       AND (SELECT count(*) FROM signup_ips WHERE ip_hash = ?1) < 10`,
  )
    .bind(h, iso(now), iso(now - 3600 * 1000))
    .run();
  if (r.meta.changes === 0) {
    throw new APIError('TOO_MANY_REQUESTS', { code: 'SIGNUP_IP_LIMIT', message: 'Too many new accounts from this network. Try again later.' });
  }
}

// Eén Better Auth per Worker-instantie (env blijft dezelfde), niet bij elk verzoek opnieuw opbouwen
const instances = new WeakMap();

export function createAuth(env) {
  if (!instances.has(env)) instances.set(env, buildAuth(env));
  return instances.get(env);
}

function buildAuth(env) {
  const auth = betterAuth({
    appName: 'MacroMatrix',
    database: env.DB,
    basePath: '/auth',
    baseURL: env.BASE_URL,
    secret: env.BETTER_AUTH_SECRET,
    trustedOrigins: [...WEB_ORIGINS, ...(env.EXTRA_ORIGINS ? env.EXTRA_ORIGINS.split(',') : [])],
    user: {
      additionalFields: {
        termsVersion: { type: 'string', required: false },
        termsAcceptedAt: { type: 'string', required: false, input: false },
      },
    },
    session: { expiresIn: 90 * DAY, updateAge: DAY },
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      minPasswordLength: 8,
      maxPasswordLength: 128,
      revokeSessionsOnPasswordReset: true,
      password: passwords,
      async onExistingUserSignUp({ user }, request) {
        if (user.emailVerified) {
          await sendMail(env, { to: user.email, kind: 'existing_account' });
          return;
        }
        // Nog nooit bevestigd: zoals Supabase het nieuwe wachtwoord nemen en een nieuwe code sturen
        const body = await request?.json().catch(() => null);
        if (body && !passwordProblem(body.password)) {
          const ctx = await auth.$context;
          await ctx.internalAdapter.updatePassword(user.id, await passwords.hash(body.password));
        }
        await auth.api.sendVerificationOTP({ body: { email: user.email, type: 'email-verification' } });
      },
      async onPasswordReset({ user }) {
        await sendMail(env, { to: user.email, kind: 'password_changed_notification' });
      },
    },
    emailVerification: { autoSignInAfterVerification: true },
    databaseHooks: {
      user: {
        create: {
          // Alleen echt nieuwe accounts tellen voor de limiet per netwerk (zoals de hook in Supabase). Het tijdstip
          // waarop de voorwaarden aanvaard werden, bepaalt de server, niet de app.
          before: async (user, ctx) => {
            await checkSignupLimit(env, ctx?.request?.headers.get('cf-connecting-ip'));
            return { data: { ...user, termsAcceptedAt: user.termsVersion ? new Date().toISOString() : null } };
          },
        },
      },
    },
    hooks: {
      before: createAuthMiddleware(async (ctx) => {
        const p = ctx.path;
        const pw = p === '/sign-up/email' || p === '/email-otp/reset-password' ? ctx.body?.password : p === '/change-password' ? ctx.body?.newPassword : undefined;
        // Staging bevat een kopie van echte accounts: daar alleen de adressen uit STAGING_EMAILS en het testdomein
        const email = typeof ctx.body?.email === 'string' ? ctx.body.email.trim().toLowerCase() : null;
        if (env.STAGING_EMAILS && email && !email.endsWith(`@${env.TEST_OUTBOX_DOMAIN}`) && !env.STAGING_EMAILS.toLowerCase().split(',').includes(email)) {
          throw new APIError('FORBIDDEN', { code: 'STAGING_ONLY', message: 'This is a test server.' });
        }
        if (pw !== undefined) {
          const problem = passwordProblem(pw);
          if (problem) throw new APIError('BAD_REQUEST', { code: 'WEAK_PASSWORD', message: problem });
        }
      }),
      after: createAuthMiddleware(async (ctx) => {
        // Ingelogd met een wachtwoord uit Supabase: meteen omzetten naar scrypt
        if (ctx.path === '/sign-in/email' && ctx.context.newSession) {
          const uid = ctx.context.newSession.user.id;
          const accounts = await ctx.context.internalAdapter.findAccounts(uid);
          const cred = accounts.find((a) => a.providerId === 'credential');
          if (cred?.password && /^\$2[aby]\$/.test(cred.password)) {
            await ctx.context.internalAdapter.updatePassword(uid, await passwords.hash(ctx.body.password));
          }
        }
        // Alle sessies weg (overal uitloggen, wachtwoord vergeten): ook de live verbindingen sluiten
        if (!(ctx.context.returned instanceof APIError)) {
          let uid = null;
          if (ctx.path === '/revoke-sessions' || (ctx.path === '/change-password' && ctx.body?.revokeOtherSessions)) uid = ctx.context.session?.user.id;
          if (ctx.path === '/email-otp/reset-password' && ctx.body?.email) uid = (await ctx.context.internalAdapter.findUserByEmail(ctx.body.email.toLowerCase()))?.user.id;
          if (uid) await hubFor(env, uid).closeAll().catch(() => {});
        }
        if (ctx.path === '/change-password' && ctx.context.session && !(ctx.context.returned instanceof APIError)) {
          await sendMail(env, { to: ctx.context.session.user.email, kind: 'password_changed_notification' });
        }
      }),
    },
    plugins: [
      emailOTP({
        otpLength: 6,
        expiresIn: 15 * 60,
        allowedAttempts: 5,
        storeOTP: 'hashed',
        // Per IP en pad; veel mensen delen een IP (gsm-netwerken). Codes raden blokkeert allowedAttempts al.
        rateLimit: { window: 60, max: 10 },
        overrideDefaultEmailVerification: true,
        async sendVerificationOTP({ email, otp, type }) {
          if (type === 'email-verification') await sendMail(env, { to: email, kind: 'confirmation', token: otp });
          else if (type === 'forget-password') await sendMail(env, { to: email, kind: 'recovery', token: otp });
        },
      }),
      bearer(),
    ],
    rateLimit: {
      enabled: true,
      storage: 'database',
      window: 60,
      max: 100,
      customRules: { '/sign-in/email': { window: 60, max: 10 }, '/sign-up/email': { window: 60, max: 10 } },
    },
    advanced: {
      ipAddress: { ipAddressHeaders: ['cf-connecting-ip'] },
      database: { generateId: 'uuid' },
    },
    telemetry: { enabled: false },
  });
  return auth;
}
