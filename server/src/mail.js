// Mails van de server: codes (bevestigen, wachtwoord vergeten) en meldingen. Sjablonen uit
// supabase/templates/make.py (mail-templates.json), dezelfde als in Supabase.
//
// Volgorde: testpostvak (alleen staging), Cloudflare Email Sending (binding EMAIL, als die er is), anders, bij een
// fout of na 5 s zonder antwoord Brevo (bv. het dagquotum van Cloudflare op, of een storing).
//
// Elke mail krijgt één id (UUID): bij Cloudflare als X-Entity-Ref-ID (Cloudflare kent geen idempotentiesleutel), bij
// Brevo als idempotencyKey. Wat overblijft: antwoordt Cloudflare te laat maar verstuurt het toch, dan komt de mail twee
// keer aan (met dezelfde code).
import templates from './mail-templates.json' with { type: 'json' };

const FROM = { name: 'MacroMatrix', email: 'noreply@macromatrix.eu' };

// Zo lang wachten op Cloudflare Email Sending, daarna Brevo (te wijzigen met env.MAIL_TIMEOUT_MS, voor tests)
const CF_TIMEOUT_MS = 5_000;
const BREVO_TIMEOUT_MS = 10_000;

const fill = (s, vars) => s.replaceAll('{{ .Token }}', vars.token ?? '').replaceAll('{{ .Email }}', escapeHtml(vars.email ?? ''));
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/** Platte tekst bij de HTML (sommige mailapps en spamfilters willen die). */
function plain(html) {
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(td|tr|p|div)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .join('\n');
}

/**
 * Een mail sturen volgens een sjabloon. [kind]: confirmation | recovery | password_changed_notification |
 * existing_account.
 */
export async function sendMail(env, mail) {
  try {
    const route = await deliver(env, mail);
    console.log(`mail ${mail.kind}: ${route}`);
    return route;
  } catch (e) {
    console.error(`mail ${mail.kind} mislukt: ${e?.message ?? e}`);
    throw e;
  }
}

async function deliver(env, { to, kind, token, id = crypto.randomUUID() }) {
  const t = templates[kind];
  if (!t) throw new Error(`onbekend sjabloon ${kind}`);
  const testDomain = env.TEST_OUTBOX_DOMAIN;
  if (testDomain && to.toLowerCase().endsWith(`@${testDomain}`)) {
    await env.DB.prepare('INSERT INTO test_outbox ("to", kind, token) VALUES (?, ?, ?)').bind(to, kind, token ?? null).run();
    return 'test';
  }
  const subject = fill(t.subject, { token, email: to });
  const html = fill(t.html, { token, email: to });
  const text = plain(html);
  if (env.EMAIL) {
    try {
      await sendCloudflare(env, { to, subject, html, text }, id);
      return 'cloudflare';
    } catch (e) {
      console.warn(`Email Sending mislukt (mail ${id}), naar Brevo:`, e?.message ?? e);
    }
  }
  return sendBrevo(env, { to, subject, html, text }, id);
}

/** Via Cloudflare, met een tijdslimiet; het mail-id als X-Entity-Ref-ID (X-headers mogen, Message-ID niet). */
function sendCloudflare(env, msg, id) {
  const ms = Number(env.MAIL_TIMEOUT_MS) || CF_TIMEOUT_MS;
  let timer;
  const late = new Promise((_, reject) => (timer = setTimeout(() => reject(new Error(`geen antwoord na ${ms} ms`)), ms)));
  return Promise.race([env.EMAIL.send({ ...msg, from: FROM, headers: { 'X-Entity-Ref-ID': id } }), late]).finally(() => clearTimeout(timer));
}

async function sendBrevo(env, { to, subject, html, text }, id) {
  if (!env.BREVO_API_KEY) throw new Error('geen mailroute (BREVO_API_KEY ontbreekt)');
  const r = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': env.BREVO_API_KEY, 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({
      sender: FROM,
      to: [{ email: to }],
      subject,
      htmlContent: html,
      textContent: text,
      // Brevo verstuurt dezelfde sleutel (een UUID) binnen 30 min niet nog eens
      headers: { idempotencyKey: id, 'X-Entity-Ref-ID': id },
    }),
    signal: AbortSignal.timeout(BREVO_TIMEOUT_MS),
  });
  if (r.ok) return 'brevo';
  const body = (await r.text()).slice(0, 200);
  // Deze sleutel was al verstuurd (een eerdere poging kwam toch aan): niet nog eens, en geen fout
  if (r.status === 400 && /duplicate_parameter/.test(body)) return 'brevo (al verstuurd)';
  throw new Error(`Brevo ${r.status}: ${body}`);
}

/** Een waarschuwing voor de beheerder (ADMIN_EMAIL), bv. als een back-up mislukt. Platte tekst. */
export async function sendAlert(env, subject, text) {
  if (!env.ADMIN_EMAIL) return console.error(`waarschuwing zonder ADMIN_EMAIL: ${subject}`);
  const mail = { to: env.ADMIN_EMAIL, subject: `[MacroMatrix] ${subject}`, text, html: `<pre>${escapeHtml(text)}</pre>` };
  const id = crypto.randomUUID();
  if (env.EMAIL) {
    try {
      await sendCloudflare(env, mail, id);
      return;
    } catch (e) {
      console.warn('waarschuwing via Cloudflare mislukt, naar Brevo:', e?.message ?? e);
    }
  }
  await sendBrevo(env, mail, id);
}
