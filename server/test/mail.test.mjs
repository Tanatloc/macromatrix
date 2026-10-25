// Mails (src/mail.js): eerst Cloudflare Email Sending, bij een fout Brevo; testadressen naar test_outbox.
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { d1 } from './d1.mjs';
import { sendMail } from '../src/mail.js';

let brevo;
beforeEach(() => {
  brevo = [];
  globalThis.fetch = async (url, init) => {
    brevo.push({ url: String(url), body: JSON.parse(init.body), key: init.headers['api-key'] });
    return new Response('{"messageId":"x"}', { status: 201 });
  };
});

test('Cloudflare eerst: code ingevuld, afzender noreply@macromatrix.eu, met platte tekst', async () => {
  const sent = [];
  const env = { EMAIL: { send: async (m) => sent.push(m) }, BREVO_API_KEY: 'k' };
  assert.equal(await sendMail(env, { to: 'a@example.org', kind: 'confirmation', token: '123456' }), 'cloudflare');
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].from, { name: 'MacroMatrix', email: 'noreply@macromatrix.eu' });
  assert.equal(sent[0].subject, 'Your MacroMatrix code: 123456');
  assert.match(sent[0].html, /123456/);
  assert.match(sent[0].text, /123456/);
  assert.doesNotMatch(sent[0].text, /</);
  assert.equal(brevo.length, 0);
});

test('Cloudflare faalt (of quota op): dezelfde mail via Brevo', async () => {
  const env = { EMAIL: { send: async () => { throw new Error('daily quota exceeded'); } }, BREVO_API_KEY: 'k' };
  assert.equal(await sendMail(env, { to: 'a@example.org', kind: 'recovery', token: '654321' }), 'brevo');
  assert.equal(brevo[0].url, 'https://api.brevo.com/v3/smtp/email');
  assert.equal(brevo[0].key, 'k');
  assert.deepEqual(brevo[0].body.sender, { name: 'MacroMatrix', email: 'noreply@macromatrix.eu' });
  assert.match(brevo[0].body.htmlContent, /654321/);
});

test('zonder Cloudflare-binding meteen Brevo; zonder beide een fout', async () => {
  assert.equal(await sendMail({ BREVO_API_KEY: 'k' }, { to: 'a@example.org', kind: 'existing_account' }), 'brevo');
  await assert.rejects(sendMail({}, { to: 'a@example.org', kind: 'existing_account' }));
});

test('een adres in een melding wordt veilig in de HTML gezet', async () => {
  const sent = [];
  await sendMail({ EMAIL: { send: async (m) => sent.push(m) } }, { to: 'a"<b>@example.org', kind: 'password_changed_notification' });
  assert.match(sent[0].html, /a&quot;&lt;b&gt;@example.org/);
});

test('staging: testadressen gaan naar test_outbox, niet naar buiten', async () => {
  const db = d1();
  const env = { DB: db, TEST_OUTBOX_DOMAIN: 'test.macromatrix.invalid', EMAIL: { send: async () => assert.fail('niet versturen') } };
  assert.equal(await sendMail(env, { to: 'x@test.macromatrix.invalid', kind: 'confirmation', token: '111222' }), 'test');
  assert.equal(db.raw.prepare('SELECT token FROM test_outbox').get().token, '111222');
  assert.equal(brevo.length, 0);
});
