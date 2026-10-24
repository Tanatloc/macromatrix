// Cloudflare Pages Function: zoeken in merkproducten van Open Food Facts.
// Hun zoekdienst staat geen verzoeken uit de browser toe (geen CORS); daarom vraagt de webversie het via
// /api/off/search op het eigen domein, en stuurt deze functie het door met een User-Agent die de app noemt
// (zoals Open Food Facts vraagt). Zelfde zoekterm binnen een uur: antwoord uit de cache van Cloudflare.
const allowed = new Set(['q', 'page_size', 'page', 'fields', 'langs', 'sort_by']);

export async function onRequestGet({ request }) {
  const url = new URL(request.url);
  const target = new URL('https://search.openfoodfacts.org/search');
  for (const [k, v] of url.searchParams) if (allowed.has(k)) target.searchParams.set(k, v);
  if (!target.searchParams.get('q')) return new Response('{"error":"q ontbreekt"}', { status: 400, headers: { 'Content-Type': 'application/json' } });

  const res = await fetch(target, {
    headers: { 'User-Agent': 'MacroMatrix/0.1 (https://macromatrix.eu)', Accept: 'application/json' },
    cf: { cacheTtl: 3600, cacheEverything: true },
  });
  return new Response(res.body, {
    status: res.status,
    headers: {
      'Content-Type': res.headers.get('Content-Type') ?? 'application/json',
      'Cache-Control': res.ok ? 'public, max-age=3600' : 'no-store',
    },
  });
}
