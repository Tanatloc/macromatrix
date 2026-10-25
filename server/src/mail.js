// Mails van de server: codes (bevestigen, wachtwoord vergeten) en meldingen. Sjablonen uit
// supabase/templates/make.py (mail-templates.json), dezelfde als in Supabase.
//
// Volgorde: testpostvak (alleen staging), Cloudflare Email Sending (binding EMAIL, als die er is), anders of bij een
// fout Brevo (bv. het dagquotum van Cloudflare op).
import templates from './mail-templates.json' with { type: 'json' };

const FROM = { name: 'MacroMatrix', email: 'noreply@macromatrix.eu' };

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

async function deliver(env, { to, kind, token }) {
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
      await env.EMAIL.send({ to, from: FROM, subject, html, text });
      return 'cloudflare';
    } catch (e) {
      console.warn('Email Sending mislukt, naar Brevo:', e?.message ?? e);
    }
  }
  return sendBrevo(env, { to, subject, html, text });
}

async function sendBrevo(env, { to, subject, html, text }) {
  if (!env.BREVO_API_KEY) throw new Error('geen mailroute (BREVO_API_KEY ontbreekt)');
  const r = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': env.BREVO_API_KEY, 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: FROM, to: [{ email: to }], subject, htmlContent: html, textContent: text }),
  });
  if (!r.ok) throw new Error(`Brevo ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return 'brevo';
}

/** Een waarschuwing voor de beheerder (ADMIN_EMAIL), bv. als een back-up mislukt. Platte tekst. */
export async function sendAlert(env, subject, text) {
  if (!env.ADMIN_EMAIL) return console.error(`waarschuwing zonder ADMIN_EMAIL: ${subject}`);
  const mail = { to: env.ADMIN_EMAIL, subject: `[MacroMatrix] ${subject}`, text, html: `<pre>${escapeHtml(text)}</pre>` };
  if (env.EMAIL) {
    try {
      await env.EMAIL.send({ ...mail, from: FROM });
      return;
    } catch (e) {
      console.warn('waarschuwing via Cloudflare mislukt, naar Brevo:', e?.message ?? e);
    }
  }
  await sendBrevo(env, mail);
}
