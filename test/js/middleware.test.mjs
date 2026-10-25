// functions/_middleware.js: het oude adres app.divinenet.online stuurt door naar macromatrix.eu.
// Draaien met: node --test test/js/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { onRequest } from '../../functions/_middleware.js';

const next = async () => new Response('verder');

test('app.divinenet.online → macromatrix.eu met hetzelfde pad en dezelfde zoekvraag (301)', async () => {
  const r = await onRequest({ request: new Request('https://app.divinenet.online/app/?start=login'), next });
  assert.equal(r.status, 301);
  assert.equal(r.headers.get('location'), 'https://macromatrix.eu/app/?start=login');
});

test('macromatrix.eu en andere adressen gaan gewoon verder', async () => {
  for (const u of ['https://macromatrix.eu/privacy/', 'https://www.macromatrix.eu/', 'https://voedingsapp.pages.dev/api/off/search?q=x']) {
    assert.equal(await (await onRequest({ request: new Request(u), next })).text(), 'verder', u);
  }
});
