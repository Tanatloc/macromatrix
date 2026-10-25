// /v1/sync (src/sync.js): pull, push en fetch per gebruiker, zoals PostgREST met RLS in Supabase.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';
import { fetchRows, pull, push } from '../src/sync.js';

const entry = (id, at, extra = {}) => ({ id, day: '2026-10-25', meal: 1, food_ref: 'ciqual:1', name: 'Banaan', grams: 100, quantity: 100, nutrients: '{}', created_at: 1, updated_at: at, deleted: 0, ...extra });

function setup() {
  const db = d1();
  addUser(db, 'a');
  addUser(db, 'b');
  return db;
}

test('push en pull: alleen je eigen rijen, oplopend op server_seq, met een cursor', async () => {
  const db = setup();
  assert.deepEqual(await push(db, 'a', 'diary', [entry('1', 10), entry('2', 20)]), { 1: 10, 2: 20 });
  await push(db, 'b', 'diary', [entry('1', 30)]);
  const rows = await pull(db, 'a', 'diary', null, 500);
  assert.deepEqual(rows.map((r) => r.id), ['1', '2']);
  assert.ok(rows.every((r) => r.user_id === 'a'));
  assert.ok(rows[1].server_seq > rows[0].server_seq);
  assert.deepEqual(await pull(db, 'a', 'diary', String(rows[0].server_seq), 500).then((r) => r.map((x) => x.id)), ['2']);
  assert.deepEqual(await pull(db, 'a', 'diary', String(rows[1].server_seq), 500), []);
});

test('user_id in de rij telt niet: je kan niet voor een ander schrijven', async () => {
  const db = setup();
  await push(db, 'a', 'diary', [{ ...entry('x', 5), user_id: 'b' }]);
  assert.equal((await pull(db, 'b', 'diary', null, 500)).length, 0);
  assert.equal((await pull(db, 'a', 'diary', null, 500)).length, 1);
});

test('een oudere versie wordt niet opgeslagen en ontbreekt in het antwoord', async () => {
  const db = setup();
  await push(db, 'a', 'diary', [entry('1', 100, { grams: 50 })]);
  assert.deepEqual(await push(db, 'a', 'diary', [entry('1', 90, { grams: 1 }), entry('2', 5)]), { 2: 5 });
  assert.equal((await fetchRows(db, 'a', 'diary', ['1']))[0].grams, 50);
});

test('insertOnly: een bestaande rij blijft staan', async () => {
  const db = setup();
  await push(db, 'a', 'settings', [{ key: 'profile', value: '{"a":1}', updated_at: 1 }]);
  assert.deepEqual(await push(db, 'a', 'settings', [{ key: 'profile', value: '{"a":2}', updated_at: 2 }, { key: 'x', value: '{}', updated_at: 2 }], { insertOnly: true }), { x: 2 });
  assert.equal((await fetchRows(db, 'a', 'settings', ['profile']))[0].value, '{"a":1}');
});

test('een klok die voorloopt: het antwoord geeft de begrensde tijd', async () => {
  const db = setup();
  const now = Date.now();
  const saved = await push(db, 'a', 'diary', [entry('1', now + 3_600_000)]);
  assert.ok(saved['1'] <= Date.now() + 300_000 && saved['1'] >= now + 290_000);
});

test('fouten met de codes van Postgres: één slechte rij laat de hele push mislukken (de app halveert dan)', async () => {
  const db = setup();
  await assert.rejects(push(db, 'a', 'notes', [{ day: '2026-10-25', text: 'x'.repeat(20001), updated_at: 1 }, { day: '2026-10-26', text: 'ok', updated_at: 1 }]), { code: '23514' });
  assert.equal((await pull(db, 'a', 'notes', null, 500)).length, 0);
  await assert.rejects(push(db, 'a', 'diary', [entry('1', 'gisteren')]), { code: '22P02' });
  await assert.rejects(push(db, 'a', 'diary', [entry('1', 1, { geheim: 1 })]), { code: 'PGRST204' });
  await assert.rejects(push(db, 'a', 'labs', [entry('1', 1)]), { code: '42P01' });
  await assert.rejects(pull(db, 'a', 'user', null, 10), { code: '42P01' });
});

test('fetch: alleen eigen rijen, ook met veel sleutels', async () => {
  const db = setup();
  const rows = Array.from({ length: 250 }, (_, i) => entry(`r${i}`, 1));
  await push(db, 'a', 'diary', rows.slice(0, 200));
  await push(db, 'a', 'diary', rows.slice(200));
  await push(db, 'b', 'diary', [entry('r1', 1)]);
  const got = await fetchRows(db, 'a', 'diary', rows.map((r) => r.id));
  assert.equal(got.length, 250);
  assert.ok(got.every((r) => r.user_id === 'a'));
});
