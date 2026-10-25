// Mails van de server: codes (bevestigen, wachtwoord vergeten) en meldingen. Sjablonen uit
// supabase/templates/make.py (mail-templates.json), dezelfde als in Supabase.
//
// Volgorde: testpostvak (alleen staging), Cloudflare Email Sending (binding EMAIL, als die er is), anders of bij een
// fout Brevo. Fase 4 maakt van Cloudflare de eerste keuze; tot dan heeft de Worker geen EMAIL-binding.
import templates from './mail-templates.json';

const FROM = { name: 'MacroMatrix', address: 'noreply@macromatrix.eu' };

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
export async function sendMail(env, { to, kind, token }) {
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
    body: JSON.stringify({ sender: { name: FROM.name, email: FROM.address }, to: [{ email: to }], subject, htmlContent: html, textContent: text }),
  });
  if (!r.ok) throw new Error(`Brevo ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return 'brevo';
}
