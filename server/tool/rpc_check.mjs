// Controle van fase 3: de functies van de app over HTTP tegen een draaiende Worker (lokaal of staging), met twee
// testgebruikers. Een rookproef op de echte D1; de volledige regels staan in test/rpc_*.test.mjs.
//   node tool/rpc_check.mjs https://api-staging.macromatrix.eu --env staging
import assert from 'node:assert/strict';
import { account, call, cleanup, live, sql, step, steps } from './checklib.mjs';

const rpc = async (token, fn, params = {}) => {
  const r = await call('POST', `/v1/rpc/${fn}`, params, token);
  if (r.status >= 400) throw Object.assign(new Error(`${fn}: ${r.status} ${JSON.stringify(r.data)}`), { data: r.data, status: r.status });
  return r.data;
};
const today = new Date().toISOString().slice(0, 10);
const monday = (() => {
  const d = new Date(`${today}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
})();

try {
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit');
  const a = await account('rpc-a');
  const b = await account('rpc-b');
  const c = await account('rpc-c');
  const hubB = await live(b.token);
  let codeB;

  await step('friend_me: eigen code en naam', async () => {
    const [meA] = await rpc(a.token, 'friend_me', { p_name: 'Anna', p_avatar: null, p_level: 3 });
    const [meB] = await rpc(b.token, 'friend_me', { p_name: 'Bert', p_avatar: null, p_level: 1 });
    assert.equal(meA.name, 'Anna');
    assert.match(meB.code, /^[A-Z0-9]{8}$/);
    codeB = meB.code;
  });
  await step('vriendschap: verzoek (B krijgt live een seintje), aanvaarden, lijst', async () => {
    const [r] = await rpc(a.token, 'friend_add_v2', { p_code: codeB });
    assert.equal(r.result, 'requested');
    assert.deepEqual(JSON.parse(await hubB.next(5000)), { type: 'social' });
    await rpc(b.token, 'friend_respond', { p_other: a.id, p_accept: true });
    const list = await rpc(a.token, 'friend_list_v2', { p_week: monday });
    assert.equal(list.length, 1);
    assert.equal(list[0].name, 'Bert');
  });
  await step('weekscores: eigen score bewaren; een vriend ziet hem, een vreemde niet', async () => {
    await rpc(b.token, 'weekly_score_put', { p_week: monday, p_score: 77, p_days: 3, p_points: 120, p_mid_points: 60 });
    const list = await rpc(a.token, 'friend_list_v2', { p_week: monday });
    assert.equal(list[0].score, 77);
    assert.deepEqual(await rpc(c.token, 'friend_list_v2', { p_week: monday }), []);
  });
  await step('battle: uitdagen, aanvaarden, lijst', async () => {
    assert.equal(await rpc(a.token, 'battle_challenge', { p_other: b.id, p_week: monday }), 'created');
    const [bt] = await rpc(b.token, 'battle_list');
    await rpc(b.token, 'battle_respond', { p_id: bt.id, p_accept: true });
    assert.equal((await rpc(a.token, 'battle_list'))[0].accepted, true);
    assert.equal(await rpc(c.token, 'battle_challenge', { p_other: a.id, p_week: monday }), 'not_friends');
  });
  await step('challenge: maken met uitnodiging, aanvaarden, dag doorgeven; een buitenstaander mag niets', async () => {
    const id = await rpc(a.token, 'challenge_create', {
      p_template: 'protein', p_title: null, p_nutrient: 'protein', p_rule: 'min', p_amount: 100, p_days: 7, p_need: 5, p_start: today, p_invite: [b.id],
    });
    await rpc(b.token, 'challenge_respond', { p_id: id, p_accept: true });
    await rpc(b.token, 'challenge_days_put', { p_challenge: id, p_days: { [today]: true } });
    const [ch] = (await rpc(a.token, 'challenge_list')).filter((x) => x.id === id);
    assert.ok(ch);
    await assert.rejects(rpc(c.token, 'challenge_days_put', { p_challenge: id, p_days: { [today]: true } }), (e) => e.data.code === '42501');
    assert.deepEqual((await rpc(c.token, 'challenge_list')).filter((x) => x.id === id), []);
  });
  await step('Supporter, quota, roadmap, features, meldingen', async () => {
    const pro = await rpc(a.token, 'my_pro');
    assert.equal(pro.pro, false);
    const q = await rpc(a.token, 'ai_quota_use', { p_kind: 'label' });
    assert.equal(q.used, 1);
    assert.equal((await rpc(a.token, 'ai_quota', { p_kind: 'label' })).used, 1);
    assert.equal((await rpc(b.token, 'ai_quota', { p_kind: 'label' })).used, 0);
    assert.ok(Array.isArray(await rpc(a.token, 'roadmap_list')));
    assert.ok(Array.isArray(await rpc(a.token, 'my_features')));
    const token = await rpc(a.token, 'notify_register');
    const pending = await call('POST', '/v1/rpc/pending_challenges', { p_token: token });
    assert.equal(pending.status, 200);
    assert.ok(Array.isArray(pending.data));
    assert.equal((await call('POST', '/v1/rpc/pending_challenges', { p_token: crypto.randomUUID() })).data.length, 0);
  });
  await step('Duo: A koopt Duo (nagebootst in play_purchases), kiest vriend B, B is Supporter via de Duo', async () => {
    const until = new Date(Date.now() + 30 * 86_400_000).toISOString();
    sql(`INSERT INTO play_purchases (purchase_token, user_id, product, expiry) VALUES ('check-duo-${a.id}', '${a.id}', 'duo_monthly', '${until}');
         INSERT OR REPLACE INTO pro_status (user_id, until, source) VALUES ('${a.id}', '${until}', 'play')`);
    assert.equal((await rpc(c.token, 'duo_set_partner', { p_other: a.id })).result, 'no_duo');
    const r = await rpc(a.token, 'duo_set_partner', { p_other: b.id });
    assert.equal(r.result, 'ok');
    const pb = await rpc(b.token, 'my_pro');
    assert.deepEqual([pb.pro, pb.source], [true, 'duo']);
    assert.equal((await rpc(b.token, 'duo_status')).role, 'partner');
    await rpc(b.token, 'duo_leave');
    assert.equal((await rpc(b.token, 'my_pro')).pro, false);
  });
  await step('blokkeren: B blokkeert A, de vriendschap en battle verdwijnen', async () => {
    await rpc(b.token, 'friend_block', { p_other: a.id });
    assert.deepEqual(await rpc(a.token, 'friend_list_v2', { p_week: monday }), []);
    assert.equal((await rpc(b.token, 'friend_blocked_list')).length, 1);
  });
  await step('zonder sessie geen functies (behalve pending_challenges)', async () => {
    const r = await call('POST', '/v1/rpc/my_pro', {});
    assert.equal(r.status, 401);
  });
  hubB.ws.close();
  console.log(`rpc_check: ${steps.length} stappen geslaagd`);
} finally {
  cleanup();
}
process.exit(0);
