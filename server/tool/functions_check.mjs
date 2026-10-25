// Controle van fase 4: de functies van de site (functions/api) op de staging-site, met de eigen server erachter
// (service binding API → ingang Internal). Gebruikt één AI-aanroep (een voedingstabel lezen).
//   node tool/functions_check.mjs https://api-staging.macromatrix.eu --env staging --web https://staging.macromatrix.eu --image label.jpg
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { account, call, cleanup, rest, sql, step, steps } from './checklib.mjs';

const web = rest[rest.indexOf('--web') + 1];
const image = readFileSync(rest[rest.indexOf('--image') + 1]);
const post = (path, body, token, headers = {}) =>
  fetch(`${web}${path}`, { method: 'POST', body, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers } });

try {
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit');
  const a = await account('fn');

  await step('zonder of met een ongeldig token: login (401)', async () => {
    assert.equal((await post('/api/photo', 'x')).status, 401);
    const r = await post('/api/photo', 'x', 'onzin');
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), { error: 'login' });
  });
  await step('voedingstabel lezen: AI-antwoord, en de dagteller op de eigen server telt', async () => {
    const form = new FormData();
    form.append('label', new Blob([image], { type: 'image/jpeg' }), 'label.jpg');
    const r = await post('/api/label', form, a.token);
    const body = await r.json();
    assert.equal(r.status, 200, JSON.stringify(body));
    assert.equal(body.quota.used, 1);
    const q = await call('POST', '/v1/rpc/ai_quota', { p_kind: 'label' }, a.token);
    assert.equal(q.data.used, 1);
    console.log(`      (gelezen: ${JSON.stringify(body.per100g ?? body.nutrients ?? body).slice(0, 120)})`);
  });
  await step('Google Play zonder sleutel op staging: not_configured (en nooit Supabase)', async () => {
    const r = await post('/api/play-verify', JSON.stringify({ purchaseToken: 'x'.repeat(20), productId: 'pro_yearly' }), a.token, { 'Content-Type': 'application/json' });
    assert.equal(r.status, 503);
    assert.equal((await r.json()).reason, 'not_configured');
  });
  await step('zoeken bij Open Food Facts (geen login nodig) werkt nog', async () => {
    const r = await fetch(`${web}/api/off/search?q=nutella&page_size=1`);
    assert.equal(r.status, 200);
  });
  console.log(`functions_check: ${steps.length} stappen geslaagd`);
} finally {
  cleanup();
}
process.exit(0);
