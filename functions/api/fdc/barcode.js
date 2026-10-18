// Cloudflare Pages Function: merkproduct opzoeken in USDA FoodData Central (Branded Foods), op barcode.
// Alleen gebruikt als Open Food Facts een product niet kent. De API-sleutel (gratis, api.data.gov) staat als
// omgevingsvariabele FDC_API_KEY in Cloudflare, nooit in de app of in git. Zonder sleutel: DEMO_KEY (heel lage limiet).
// Antwoord: een compacte versie (naam, merk, ingrediënten, portie en voedingswaarden per 100 g als [id, eenheid, waarde]).

const json = (body, status = 200, cache = 'no-store') =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': cache } });

export async function onRequestGet({ request, env }) {
  const code = new URL(request.url).searchParams.get('code') ?? '';
  if (!/^\d{8,14}$/.test(code)) return json({ error: 'code ontbreekt of is geen barcode' }, 400);

  // FDC bewaart GTIN's met wisselend aantal voorloopnullen (12, 13 of 14 cijfers)
  const bare = code.replace(/^0+/, '');
  const variants = new Set([code]);
  for (const len of [12, 13, 14]) if (bare.length <= len) variants.add(bare.padStart(len, '0'));
  const target = new URL('https://api.nal.usda.gov/fdc/v1/foods/search');
  target.searchParams.set('api_key', env.FDC_API_KEY || 'DEMO_KEY');
  target.searchParams.set('query', [...variants].map((v) => `gtinUpc:${v}`).join(' OR '));
  target.searchParams.set('dataType', 'Branded');
  target.searchParams.set('pageSize', '5');

  const res = await fetch(target, { cf: { cacheTtl: 86400, cacheEverything: true } });
  if (res.status === 429) return json({ error: 'limiet' }, 429);
  if (!res.ok) return json({ error: `FDC ${res.status}` }, 502);
  const data = await res.json();
  // Nieuwste versie van het product eerst
  const foods = (data.foods ?? [])
    .filter((f) => (f.gtinUpc ?? '').replace(/^0+/, '') === bare)
    .sort((a, b) => String(b.publishedDate ?? '').localeCompare(String(a.publishedDate ?? '')));
  const f = foods[0];
  if (!f) return json({ found: false }, 200, 'public, max-age=86400');
  return json(
    {
      found: true,
      code,
      fdcId: f.fdcId,
      name: f.description,
      brand: f.brandName || f.brandOwner || null,
      ingredients: f.ingredients || null,
      serving: f.servingSize ?? null,
      servingUnit: f.servingSizeUnit ?? null,
      household: f.householdServingFullText || null,
      country: f.marketCountry || null,
      category: f.brandedFoodCategory || null,
      nutrients: (f.foodNutrients ?? []).filter((n) => typeof n.value === 'number').map((n) => [n.nutrientId, n.unitName, n.value]),
    },
    200,
    'public, max-age=86400',
  );
}
