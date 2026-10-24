# Ontwikkelen (Nederlands)

## Ontwikkelen

Nodig: Flutter (stable), Java 21 en de Android-SDK (zie `flutter doctor`).

```bash
flutter run -d linux          # op de pc
flutter run                   # op een aangesloten Android-gsm (USB-foutopsporing aan)
flutter test                  # tests
flutter build apk --release   # Android-installatiebestand
flutter build linux --release
```

Een Windows-versie kan alleen op Windows gebouwd worden (later via GitHub Actions).

## Website en webversie (https://macromatrix.eu)

Gehost op **Cloudflare Pages** (project `voedingsapp`, ook https://voedingsapp.pages.dev). Elke push naar `master`
wordt door GitHub Actions getest, gebouwd (`tool/build_site.sh`) en uitgerold. DNS: CNAME `app` → `voedingsapp.pages.dev`
bij Namecheap. 

- `/`: homepage, met `/privacy/` en `/voorwaarden/` (statische pagina's in `site/`, zelfde ontwerp als de app).
- `/app/`: de app zelf (Flutter-web). Zonder account kom je niet verder dan het welkomscherm;
  `/app/?start=register` en `/app/?start=login` openen meteen het juiste scherm (knoppen op de homepage).

In de browser draait SQLite als WebAssembly (`web/sqlite3.wasm`, van de releases van sqlite3.dart, versie gelijk
aan het pakket): de voedingsdatabase in het geheugen, je eigen gegevens in IndexedDB. Zoeken in Open Food Facts gaat
via de eigen server (`/api/off/search`), omdat hun zoekdienst geen verzoeken uit de browser toelaat. Lettertypes
(Geist) en CanvasKit worden meegeleverd, er wordt niets van Google geladen.

Pc en Android altijd met het account bouwen:

```bash
flutter build linux --release --dart-define-from-file=supabase.json
flutter build apk --release --dart-define-from-file=supabase.json
```

## Importeren uit Cronometer en MyFitnessPal

`lib/import/`: herkent exportbestanden aan hun kolommen (niet aan hun naam), zet eenheden om (IE vitamine D naar µg,
pond naar kilo, mg/dL glucose naar mmol/L) en geeft elke regel een vaste id, zodat twee keer importeren geen dubbels
geeft. Cronometer: elk product met al zijn voedingsstoffen, plus metingen, beweging en notities. MyFitnessPal: het
dagboek per product als de export dat heeft, anders de totalen per maaltijd; % van de Amerikaanse dagwaarde wordt niet
overgenomen. In de app: Profiel → Overige instellingen → Gegevens, of "Overstappen?" op een lege dag.

## Accounts en synchronisatie (Supabase)

Lokaal eerst: de app werkt altijd met de lokale database; met een account gaan wijzigingen via Supabase naar je
andere toestellen. Instellen en bouwen: zie [supabase/README.md](supabase/README.md). Zonder `supabase.json` werkt
de app zonder account.

## Pro en de fototeller

Bijna alles is gratis. Loggen met een foto: 3 per dag gratis, onbeperkt met Pro (rem: 50 per dag, UTC). Pro geeft
ook extra kleuren, een Supporter-badge bij vrienden en een uitgebreid jaaroverzicht.

- Migratie `supabase/migrations/20261026000000_pro.sql` (met de hand in de SQL-editor): `pro_status`, `photo_usage`,
  `photo_quota_use()`, `photo_quota()`, `my_pro()`, `pro_show_badge()` en `friend_list_v2()` (met kolom `supporter`).
  Zonder die migratie werkt alles zoals vroeger.
- `functions/api/photo.js` verhoogt de teller met het token van de gebruiker voor het beeldmodel draait (429
  `{error:'quota', used, limit, pro}`); ontbreekt de functie, dan alleen de rem per uur. Test: `node --test test/js/`.
- App: `lib/sync/pro.dart` (status en teller), `lib/sync/purchase.dart` (`PurchaseProvider`: voorlopig
  `NoPurchaseProvider`, later Google Play Billing in de Play-build en een betaalpagina op het web; geen
  in_app_purchase in de F-Droid-build), `lib/ui/screens/pro_screen.dart`. In een debug-build staat onderaan het
  Pro-scherm een schakelaar om Pro na te bootsen.
- Pro met de hand toekennen (een jaar):

```sql
insert into public.pro_status (user_id, until, source)
select id, now() + interval '1 year', 'manual' from auth.users where email = 'iemand@example.com'
on conflict (user_id) do update set until = excluded.until, source = excluded.source, updated_at = now();
```

## Cloudflare Pages (webversie in de cloud)

- `site/_headers`: beveiligings- en cacheheaders (op de eigen server doet nginx dit).
- `functions/api/off/search.js`: het zoeken in merkproducten op hetzelfde adres als nu (`/api/off/search`), met een
  uur cache bij Cloudflare.
- `.github/workflows/web.yml`: bij elke push naar main testen, bouwen en uitrollen. Nodig als secrets in GitHub:
  `CLOUDFLARE_API_TOKEN` (rechten: *Cloudflare Pages: Edit*) en `CLOUDFLARE_ACCOUNT_ID`.
- Met de hand vanaf deze pc (Node.js nodig): `tool/build_site.sh && npx wrangler pages deploy build/site --project-name=voedingsapp`.
- Eigen domein: in Cloudflare → *Workers & Pages* → voedingsapp → *Custom domains*.
- Tip: een gratis *Rate limiting rule* op `/api/*` (bv. 20 per minuut per IP).

## Structuur

- `lib/nutrition/`: catalogus van voedingsstoffen, richtwaarden (EFSA/WHO), rekenen met waarden
- `lib/data/`: ingebouwde USDA-database, Open Food Facts, lokale gebruikersdatabase
- `lib/state/app_state.dart`: centrale toestand (dag, dagboek, profiel, doelen)
- `lib/ui/`: schermen en widgets
- `tool/build_foods.py`: bouwt `assets/db/foods.db` uit alle bronnen
- `tool/food_fixes.json`: correcties op fouten in de bronnen zelf, met uitleg per waarde
- `tool/audit_foods.py`, `tool/consensus.py`: controleren de database op waarden die niet kunnen kloppen
- `tool/food_labels.jsonl`, `tool/label_fixes.json`: labels per product (zie hieronder)
- `tool/retention.py`, `tool/xlsx_read.py`: kookverliezen en een kleine Excel-lezer
- `tool/fetch_slv.py`: haalt de Zweedse database op via hun API
- `tool/search_probe_test.dart`: toont zoekresultaten voor een paar woorden (`flutter test tool/search_probe_test.dart`)
- `tool/seed_demo.py`: vult een voorbeelddag in, voor screenshots

## Database met basisvoedingsmiddelen opnieuw bouwen

Zet de bronnen in één map (zie de uitleg bovenaan `tool/build_foods.py` voor de submappen en downloadlinks):

- `ciqual/`: XML-zip van https://ciqual.anses.fr, uitgepakt
- `slv/`: `python3 tool/fetch_slv.py <map>/slv`
- `mvt/`: `foods_en.json`, `foods_nb.json`, `food_groups_en.json` van https://www.matvaretabellen.no/api/
- USDA: "SR Legacy" en "Foundation Foods" (CSV) van https://fdc.nal.usda.gov/download-datasets, uitgepakt

```bash
python3 tool/build_foods.py <map> assets/db/foods.db
python3 tool/audit_foods.py assets/db/foods.db /tmp/audit   # bevindingen.csv + samenvatting.md
```

Bronnen: CIQUAL 2025 (en 2020 voor verdwenen producten), Livsmedelsverket, Matvaretabellen, Frida (Denemarken),
CoFID (VK), USDA SR Legacy en Foundation. Daarnaast `usda_retention/retn06.txt` (USDA-kookverliezen) en
`langual/LanguaL2017.XML` (alleen voor de hints bij het labelen).

Wat het bouwscript doet met ontbrekende of foute waarden:

1. Correcties uit `tool/food_fixes.json` (eenheidsfouten, tikfouten, een misleidende naam), vóór alles. Elke
   correctie heeft een reden; een deel komt uit de controle met andere databanken (zie hieronder).
2. Elk product heeft een label in `tool/food_labels.jsonl` (voedingsmiddel, deel, plant/dier, groep, bereiding,
   kenmerken, gerecht). Verbeteringen staan in `tool/label_fixes.json`.
3. Vaste regels: aminozuren die niet bij het eiwit passen vallen weg; zuiver plantaardig (niet verrijkt) krijgt
   B12, cholesterol, vitamine D en EPA/DHA = 0; vitamine A pas uit retinol + bètacaroteen als retinol bekend is.
4. Aanvullen, telkens alleen uit gemeten waarden (nooit een schatting van een schatting), omgerekend met vet,
   eiwit of vetvrije droge stof:
   - hetzelfde voedingsmiddel (zelfde label, ook bereiding): mediaan van alle databanken;
   - hetzelfde voedingsmiddel, andere bereiding: plus de kookverliezen (`tool/retention.py`); `~bron:id`;
   - de groep (bv. "fish, fillet"), anders de ruimere groep, nooit hoger dan het hoogste gemeten product;
     `~~group:…`. Verrijkt en niet-verrijkt worden voor vitamines en mineralen nooit gemengd.
5. Onder de meetgrens (CIQUAL "< x") en nergens anders gevonden: 0.
6. Geschatte deelwaarden worden ingekort tot ze niet boven het totaal uitkomen.

Labels maken (eenmalig, of voor nieuwe producten): `tool/export_for_labels.py` maakt de invoer, het labelen gebeurt
volgens een vaste opdracht (voedingsmiddel, deel, …), `tool/check_labels.py` controleert op verschoven regels en
`tool/merge_labels.py` maakt er `tool/food_labels.jsonl` van.

Controle: `tool/audit_foods.py` (regels: energie, sommen, grenzen, plant/dier, uitschieters) en
`tool/consensus.py` (dezelfde voeding in verschillende databanken). Verdachte waarden worden één voor één
beoordeeld; `tool/apply_review.py` neemt de uitkomst over in de correctiebestanden.


Nauwkeurigheid meten: `HOLDOUT=3000 python3 tool/build_foods.py <map> /tmp/x.db` verbergt 3000 gemeten waarden,
schat ze opnieuw en vergelijkt. Uitslag op 2026-10-20 (afwijking = |schatting/meting|):

| | aantal | typische afwijking (mediaan) | binnen ±25% | binnen 2× |
|---|---|---|---|---|
| ALLES | 2996 | 25% | 50% | 78% |
| zelfde voeding | 2144 | 21% | 54% | 81% |
| andere bereiding | 690 | 40% | 43% | 72% |
| groep | 162 | 68% | 28% | 61% |
| phosphorus | 185 | 18% | 58% | 85% |
| calcium | 170 | 28% | 47% | 78% |
| potassium | 164 | 17% | 59% | 90% |
| b2 | 158 | 32% | 46% | 80% |
| b1 | 156 | 30% | 46% | 76% |

De app toont elke geschatte waarde met ≈ en de herkomst. Verandert de database, dan werkt de app bij de start
de dagboekregels van ingebouwde producten bij (tabel `meta`, sleutel `version`).

Nog niet toegevoegd: Fineli (Finland, CC BY 4.0; download zit achter een botcontrole, dus met de hand
downloaden) en NEVO (Nederland; aan te vragen bij het RIVM, gegevens mogen niet gewijzigd worden en je mag
gebruikers er niet voor laten betalen).

## Bronnen en licenties

- ANSES-CIQUAL 2025 (en 2020 voor producten die verdwenen): Licence Ouverte 2.0 (Etalab)
- Frida 6.1, DTU Fødevareinstituttet: vrij te gebruiken met bronvermelding
- McCance and Widdowson's CoFID 2021 (Public Health England): Open Government Licence v3.0
- Livsmedelsverket, Livsmedelsdatabasen: CC BY 4.0
- Matvaretabellen (Mattilsynet): Norwegian Licence for Open Government Data (NLOD)
- USDA FoodData Central: publiek domein (CC0)
- Open Food Facts: Open Database License (ODbL). Naamsvermelding staat in de app (Profiel → Bronnen).
- Richtwaarden: EFSA Dietary Reference Values; essentiële aminozuren: WHO/FAO/UNU 2007. Geen medisch advies.
