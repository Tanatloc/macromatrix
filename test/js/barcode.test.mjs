// /api/fdc/barcode (functions/api/fdc/barcode.js): een kapot antwoord van FoodData Central wordt een nette 502.
// Draaien met: node --test test/js/
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { onRequestGet } from '../../functions/api/fdc/barcode.js';

const get = (code) => onRequestGet({ request: new Request(`https://app.test/api/fdc/barcode?code=${code}`), env: { FDC_API_KEY: 'k' } });

test('FDC antwoordt met kapotte JSON (of HTML): 502 met JSON, geen uitzondering', async () => {
  globalThis.fetch = async () => new Response('<html>upstream error</html>', { status: 200, headers: { 'Content-Type': 'text/html' } });
  const res = await get('5449000000996');
  assert.equal(res.status, 502);
  assert.equal(res.headers.get('Content-Type'), 'application/json');
  assert.ok((await res.json()).error);
});

test('een gewoon antwoord: het product, en een onbekende barcode: found false', async () => {
  globalThis.fetch = async () =>
    Response.json({ foods: [{ gtinUpc: '05449000000996', fdcId: 1, description: 'COLA', brandName: 'ACME', foodNutrients: [{ nutrientId: 1008, unitName: 'KCAL', value: 42 }] }] });
  const j = await (await get('5449000000996')).json();
  assert.equal(j.found, true);
  assert.equal(j.name, 'COLA');
  assert.deepEqual(j.nutrients, [[1008, 'KCAL', 42]]);
  globalThis.fetch = async () => Response.json({ foods: [] });
  assert.deepEqual(await (await get('5449000000996')).json(), { found: false });
});
