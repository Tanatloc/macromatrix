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

## Website en webversie (https://app.divinenet.online)

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
- `tool/audit_foods.py`: controleert de database op waarden die niet kunnen kloppen
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

Wat het bouwscript doet met ontbrekende of foute waarden:

1. Correcties uit `tool/food_fixes.json` (eenheidsfouten, tikfouten, een misleidende naam), vóór alles.
2. Vaste regels: aminozuren die niet bij het eiwit passen vallen weg; een zuiver plantaardig product krijgt
   B12, cholesterol, vitamine D (behalve paddenstoelen) en EPA/DHA = 0; vitamine A wordt pas uit retinol +
   bètacaroteen berekend als retinol bekend is.
3. Aanvullen, in drie rondes, telkens alleen met gemeten waarden (nooit een schatting van een schatting):
   - hetzelfde voedingsmiddel in een andere bron (zelfde bereiding, naam = verfijning);
   - een vergelijkbaar product (zelfde hoofdproduct, andere bereiding), geschaald met de vetvrije droge stof,
     het vet of het eiwit; `~bron:id` in de kolom `estimated`;
   - het gemiddelde van vergelijkbare producten (zelfde hoofdwoord, anders de categorie), nooit hoger dan het
     hoogste gemeten product van die groep; `~~head:…` of `~~cat:…`.
4. Onder de meetgrens (CIQUAL "< x") en nergens anders gevonden: 0.
5. Geschatte deelwaarden worden ingekort tot ze niet boven het totaal uitkomen.

De app toont elke geschatte waarde met ≈ en de herkomst. Verandert de database, dan werkt de app bij de start
de dagboekregels van ingebouwde producten bij (tabel `meta`, sleutel `version`).

Nog niet toegevoegd: Fineli (Finland, CC BY 4.0; download zit achter een botcontrole, dus met de hand
downloaden) en NEVO (Nederland; aan te vragen bij het RIVM, gegevens mogen niet gewijzigd worden en je mag
gebruikers er niet voor laten betalen).

## Bronnen en licenties

- ANSES-CIQUAL 2020: Licence Ouverte (Etalab)
- Livsmedelsverket, Livsmedelsdatabasen: CC BY 4.0
- Matvaretabellen (Mattilsynet): Norwegian Licence for Open Government Data (NLOD)
- USDA FoodData Central: publiek domein (CC0)
- Open Food Facts: Open Database License (ODbL). Naamsvermelding staat in de app (Profiel → Bronnen).
- Richtwaarden: EFSA Dietary Reference Values; essentiële aminozuren: WHO/FAO/UNU 2007. Geen medisch advies.
