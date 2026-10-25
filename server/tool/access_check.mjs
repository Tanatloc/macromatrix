// Toegangscontrole per endpoint tegen een draaiende Worker (staging of productie): account B kan niets lezen of
// wijzigen van account A, voor alle negen synctabellen en elke functie die naar iets van een ander verwijst. Na elke
// poging kijkt het script in de database dat er niets veranderde. Alleen testaccounts op het testdomein (codes uit
// test_outbox), die het script zelf weer wist.
//   node tool/access_check.mjs https://api-staging.macromatrix.eu --env staging
import assert from 'node:assert/strict';
import { account, call, cleanup, run, sql, step, steps } from './checklib.mjs';

const rpc = async (token, fn, params = {}) => call('POST', `/v1/rpc/${fn}`, params, token);
const push = (token, table, rows) => call('POST', '/v1/sync/push', { table, rows }, token);
const pull = (token, table) => call('GET', `/v1/sync/pull?table=${table}&limit=1000`, undefined, token);
const today = new Date().toISOString().slice(0, 10);
const monday = (() => {
  const d = new Date(`${today}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
})();

// Eén geldige rij per synctabel; [v] verandert een veld, zodat een overschrijving te zien zou zijn
const now = Date.now();
const key = `acc-${run}`;
const ROWS = {
  settings: (v) => ({ key, value: JSON.stringify({ v }), updated_at: now }),
  foods: (v) => ({ id: key, source: 'custom', name: `Eigen product ${v}`, nutrients: '{}', updated_at: now }),
  diary: (v) => ({ id: key, day: today, meal: 1, food_ref: 'ciqual:1', name: `Banaan ${v}`, grams: 100, quantity: 1, nutrients: '{}', created_at: now, updated_at: now }),
  meals: (v) => ({ id: key, name: `Maaltijd ${v}`, items: '[]', updated_at: now }),
  biometrics: (v) => ({ id: key, day: today, type: 'weight', value: 70 + v, updated_at: now }),
  notes: (v) => ({ day: `2099-01-${String(v + 1).padStart(2, '0')}`, text: `notitie ${v}`, updated_at: now }),
  exercise: (v) => ({ id: key, day: today, name: `Lopen ${v}`, kcal: 100 + v, updated_at: now }),
  fasts: (v) => ({ id: key, start: now, goal_hours: 16 + v, updated_at: now }),
  repeats: (v) => ({ id: key, meal: 1, item: `{"v":${v}}`, weekdays: 127, start_day: today, updated_at: now }),
};
const KEY = { settings: 'key', notes: 'day' };
const keyOf = (t, row) => row[KEY[t] ?? 'id'];

try {
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit; DELETE FROM login_limits');
  const a = await account('acc-a');
  const b = await account('acc-b');
  const c = await account('acc-c');

  await step('zonder of met een vals token: 401 op elk endpoint', async () => {
    const paths = [
      ['GET', '/v1/sync/pull?table=diary'],
      ['POST', '/v1/sync/pull-all'],
      ['POST', '/v1/sync/push'],
      ['POST', '/v1/sync/fetch'],
      ['POST', '/v1/live/ticket'],
      ['POST', '/v1/rpc/my_pro'],
      ['POST', '/v1/rpc/delete_account'],
    ];
    for (const [m, p] of paths) {
      for (const token of [undefined, 'onzin', `${a.token}x`]) assert.equal((await call(m, p, m === 'GET' ? undefined : {}, token)).status, 401, `${m} ${p}`);
    }
  });

  await step('synctabellen (alle negen): B ziet niets van A, ook niet via fetch of pull-all, en kan niets overschrijven', async () => {
    for (const [t, row] of Object.entries(ROWS)) {
      const mine = row(1);
      const r = await push(a.token, t, [mine]);
      assert.equal(r.status, 200, `${t}: ${JSON.stringify(r.data)}`);
      // Lezen als B
      assert.ok(!(await pull(b.token, t)).data.some((x) => keyOf(t, x) === keyOf(t, mine)), `${t}: pull`);
      const f = await call('POST', '/v1/sync/fetch', { table: t, keys: [keyOf(t, mine)] }, b.token);
      assert.deepEqual(f.data, [], `${t}: fetch`);
      // Schrijven als B met dezelfde sleutel (en zelfs met user_id van A): komt bij B terecht, A blijft gelijk
      await push(b.token, t, [{ ...row(2), updated_at: now + 60_000, user_id: a.id }]);
      const own = sql(`SELECT user_id FROM "${t}" WHERE "${KEY[t] ?? 'id'}" = '${keyOf(t, row(2))}' AND user_id = '${b.id}'`);
      assert.equal(own.length, 1, `${t}: rij van B bij B`);
      const back = (await call('POST', '/v1/sync/fetch', { table: t, keys: [keyOf(t, mine)] }, a.token)).data;
      assert.equal(back.length, 1, `${t}: rij van A`);
      assert.equal(back[0].user_id, a.id);
      for (const [k, v] of Object.entries(mine)) if (k !== 'updated_at') assert.equal(String(back[0][k]), String(v), `${t}.${k} van A ongewijzigd`);
    }
    // Zoals de app: alle tabellen vanaf het begin; en zonder tabellen een leeg antwoord
    const all = await call('POST', '/v1/sync/pull-all', { cursors: Object.fromEntries(Object.keys(ROWS).map((t) => [t, 0])) }, b.token);
    assert.equal(all.status, 200);
    for (const rows of Object.values(all.data)) assert.ok(rows.every((x) => x.user_id !== a.id), 'pull-all');
    assert.deepEqual((await call('POST', '/v1/sync/pull-all', { cursors: {} }, b.token)).data, {});
  });

  // A en C zijn vrienden, met een battle en een uitdaging; B staat erbuiten
  let codeC, battleId, challengeId;
  await step('voorbereiding: A en C vrienden, battle en uitdaging van A', async () => {
    await rpc(a.token, 'friend_me', { p_name: 'Anna', p_avatar: null, p_level: 1 });
    await rpc(b.token, 'friend_me', { p_name: 'Bert', p_avatar: null, p_level: 1 });
    codeC = (await rpc(c.token, 'friend_me', { p_name: 'Cleo', p_avatar: null, p_level: 1 })).data[0].code;
    await rpc(a.token, 'friend_add_v2', { p_code: codeC });
    await rpc(c.token, 'friend_respond', { p_other: a.id, p_accept: true });
    assert.equal((await rpc(a.token, 'battle_challenge', { p_other: c.id, p_week: monday })).data, 'created');
    battleId = (await rpc(a.token, 'battle_list')).data[0].id;
    challengeId = (await rpc(a.token, 'challenge_create', {
      p_template: 'protein', p_title: null, p_nutrient: 'protein', p_rule: 'min', p_amount: 100, p_days: 7, p_need: 5, p_start: today, p_invite: [c.id],
    })).data;
    assert.match(challengeId, /^[0-9a-f-]{36}$/);
  });

  await step('vrienden: B kan geen verzoek van A aanvaarden, de vriendschap A–C niet wissen en ziet A nergens', async () => {
    await rpc(b.token, 'friend_respond', { p_other: a.id, p_accept: true });
    await rpc(b.token, 'friend_respond', { p_other: c.id, p_accept: false });
    await rpc(b.token, 'friend_remove', { p_other: a.id });
    assert.equal(sql(`SELECT count(*) n FROM friendships WHERE accepted = 1 AND ((requester = '${a.id}' AND addressee = '${c.id}') OR (requester = '${c.id}' AND addressee = '${a.id}'))`)[0].n, 1);
    assert.equal(sql(`SELECT count(*) n FROM friendships WHERE requester = '${b.id}' OR addressee = '${b.id}'`)[0].n, 0);
    assert.deepEqual((await rpc(b.token, 'friend_list_v2', { p_week: monday })).data, []);
    // Profiel bijwerken raakt alleen het eigen profiel
    await rpc(b.token, 'friend_extra', { p_title: 'gehackt', p_badges: 'x' });
    assert.equal(sql(`SELECT title FROM friend_profiles WHERE user_id = '${a.id}'`)[0].title, null);
  });

  await step('blokkeren en melden: B kan A niet blokkeren of melden zonder band (en ziet geen naam)', async () => {
    await rpc(b.token, 'friend_block', { p_other: a.id });
    assert.deepEqual((await rpc(b.token, 'friend_blocked_list')).data, []);
    assert.equal((await rpc(b.token, 'friend_report', { p_other: a.id, p_reason: 'spam', p_note: null })).data, 'not_found');
    assert.equal(sql(`SELECT count(*) n FROM user_blocks WHERE blocker = '${b.id}'`)[0].n, 0);
  });

  await step('battles: B kan de battle van A en C niet aanvaarden, intrekken of zien', async () => {
    await rpc(b.token, 'battle_respond', { p_id: battleId, p_accept: true });
    await rpc(b.token, 'battle_respond', { p_id: battleId, p_accept: false });
    await rpc(b.token, 'battle_cancel', { p_id: battleId });
    const [bt] = sql(`SELECT accepted FROM battles WHERE id = '${battleId}'`);
    assert.equal(bt?.accepted, 0, 'battle bestaat nog en is niet aanvaard');
    assert.deepEqual((await rpc(b.token, 'battle_list')).data, []);
    assert.equal((await rpc(b.token, 'battle_challenge', { p_other: a.id, p_week: monday })).data, 'not_friends');
  });

  await step('uitdagingen: B kan niet meedoen, uitnodigen, dagen doorgeven, verlaten of de uitdaging zien', async () => {
    await rpc(b.token, 'challenge_respond', { p_id: challengeId, p_accept: true });
    assert.equal((await rpc(b.token, 'challenge_invite', { p_id: challengeId, p_other: b.id })).data, 'not_member');
    const days = await rpc(b.token, 'challenge_days_put', { p_challenge: challengeId, p_days: { [today]: true } });
    assert.equal(days.status, 403, JSON.stringify(days.data));
    await rpc(b.token, 'challenge_leave', { p_id: challengeId });
    assert.equal(sql(`SELECT count(*) n FROM challenge_members WHERE challenge_id = '${challengeId}' AND user_id = '${b.id}'`)[0].n, 0);
    assert.equal(sql(`SELECT count(*) n FROM challenges WHERE id = '${challengeId}'`)[0].n, 1, 'uitdaging van A bestaat nog');
    assert.ok(!(await rpc(b.token, 'challenge_list')).data.some((x) => x.id === challengeId));
  });

  await step('weekscore, Supporter, Duo, meldingen en tellers: alleen het eigen account', async () => {
    await rpc(a.token, 'weekly_score_put', { p_week: monday, p_score: 80, p_days: 5, p_points: 300, p_mid_points: 150 });
    await rpc(b.token, 'weekly_score_put', { p_week: monday, p_score: 1, p_days: 1, p_points: 1, p_mid_points: 1 });
    assert.equal(sql(`SELECT score FROM weekly_scores WHERE user_id = '${a.id}' AND week = '${monday}'`)[0].score, 80);
    assert.equal((await rpc(b.token, 'duo_set_partner', { p_other: a.id })).data.result, 'no_duo');
    await rpc(b.token, 'duo_remove');
    await rpc(b.token, 'duo_leave');
    assert.equal(sql(`SELECT count(*) n FROM duo_members WHERE owner = '${b.id}' OR partner = '${b.id}'`)[0].n, 0);
    const tokenA = (await rpc(a.token, 'notify_register')).data;
    await rpc(b.token, 'notify_unregister', { p_token: tokenA });
    assert.equal(sql(`SELECT count(*) n FROM notify_tokens WHERE token = '${tokenA}' AND user_id = '${a.id}'`)[0].n, 1, 'meldingstoken van A blijft');
    await rpc(b.token, 'ai_quota_use', { p_kind: 'label' });
    assert.equal(sql(`SELECT count(*) n FROM ai_usage WHERE user_id = '${a.id}'`)[0].n, 0);
    assert.equal((await rpc(b.token, 'my_pro')).data.pro, false);
  });

  await step('live: een ticket van B met de id van A erin werkt niet', async () => {
    const { data } = await call('POST', '/v1/live/ticket', {}, b.token);
    const forged = data.ticket.replace(b.id, a.id);
    const u = new URL('/v1/live', process.argv[2]);
    u.searchParams.set('ticket', forged);
    assert.equal((await call('GET', `${u.pathname}${u.search}`, undefined)).status, 401);
  });

  await step('interne ingang (service binding) is niet bereikbaar vanaf het internet', async () => {
    for (const p of ['/internal', '/v1/internal/session', '/v1/rpc/session', '/v1/rpc/grantPro']) {
      const r = await call('POST', p, {}, b.token);
      assert.ok([404, 400].includes(r.status), `${p}: ${r.status}`);
    }
    assert.equal(sql(`SELECT count(*) n FROM pro_status WHERE user_id = '${b.id}'`)[0].n, 0);
  });

  await step('account verwijderen door B wist alleen B', async () => {
    assert.equal((await rpc(b.token, 'delete_account')).status, 200);
    assert.equal(sql(`SELECT count(*) n FROM "user" WHERE id = '${a.id}'`)[0].n, 1);
    assert.equal(sql(`SELECT count(*) n FROM diary WHERE user_id = '${a.id}'`)[0].n, 1);
    assert.equal(sql(`SELECT count(*) n FROM diary WHERE user_id = '${b.id}'`)[0].n, 0);
    assert.equal((await rpc(b.token, 'my_pro')).status, 401);
  });

  console.log(`access_check: ${steps.length} stappen geslaagd`);
} finally {
  cleanup();
}
process.exit(0);
