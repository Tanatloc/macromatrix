// functions/_lib/backend.js: met een service binding API gaan de Supabase-aanroepen naar de eigen server, met
// hetzelfde antwoord; zonder binding verandert er niets.
// Draaien met: node --test test/js/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { backendFetch } from '../../functions/_lib/backend.js';
import { SUPABASE_URL, aiQuotaStatus, checkLogin } from '../../functions/_lib/ai.js';

const base = async (url) => new Response(`base:${url}`);
const api = {
  calls: [],
  async session(auth) {
    return auth === 'Bearer goed' ? { id: 'u-1', email: 'a@example.org' } : null;
  },
  async rpc(name, params, auth) {
    this.calls.push({ name, params, auth });
    if (name === 'ai_quota_use') return { status: 200, body: { allowed: true, used: 3, limit: 20, pro: false } };
    return { status: 404, body: { code: 'PGRST202', message: 'Could not find the function' } };
  },
};

test('zonder binding: gewoon de gewone fetch', async () => {
  assert.equal(backendFetch({}, base), base);
});

test('inloggen nakijken via de eigen server', async () => {
  const f = backendFetch({ API: api }, base);
  const ok = await checkLogin(new Request('https://x', { headers: { Authorization: 'Bearer goed' } }), f);
  assert.equal(ok.user, 'u-1');
  const bad = await checkLogin(new Request('https://x', { headers: { Authorization: 'Bearer slecht' } }), f);
  assert.equal(bad.error.status, 401);
});

test('functies als de gebruiker, met hetzelfde antwoord (ook PGRST202)', async () => {
  const f = backendFetch({ API: api }, base);
  assert.deepEqual(await aiQuotaStatus('Bearer goed', 'label', f), { quota: { allowed: true, used: 3, limit: 20, pro: false } });
  assert.deepEqual(api.calls.at(-1), { name: 'ai_quota_use', params: { p_kind: 'label' }, auth: 'Bearer goed' });
  assert.deepEqual(await aiQuotaStatus('Bearer goed', 'label', f, 'bestaat_niet'), { missing: true });
});

test('andere adressen (Google, Open Food Facts, ...) gaan gewoon door; onbekende Supabase-paden niet', async () => {
  const f = backendFetch({ API: api }, base);
  assert.equal(await (await f('https://world.openfoodfacts.org/x')).text(), 'base:https://world.openfoodfacts.org/x');
  const r = await f(`${SUPABASE_URL}/rest/v1/pro_status?select=*`, {});
  assert.equal(r.status, 404);
});
