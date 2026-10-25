# foods.db: wijzigingen 2026-10-25 (ronde 11: NF-1, NF-2, NF-6, NF-16, NF-17, SP-1, NW-15, en de controle erna)

Gebouwd met `python3 tool/build_foods.py <bronnen> assets/db/foods.db`. Versie `485eba568e4d` → `db1143d85e05`
(20 576 producten, ongewijzigd aantal). De app werkt dagboekregels van ingebouwde producten bij zodra de versie verandert.

## Omrekeningen

| Regel | Factor | Bron | Producten |
|---|---|---|---|
| CoFID-koolhydraten naar gewicht | zetmeel ÷ 1,10; sacharose, maltose, lactose ÷ 1,05; monosachariden ÷ 1; oligosachariden ongewijzigd | McCance and Widdowson (monosacharide-equivalenten) | 1962 met lagere koolhydraten (1536 zetmeel, 1693 suikers) |
| CoFID-vezels | geen factor: AOAC-vezels; Englyst-NSP alleen als AOAC ontbreekt, ongewijzigd (NSP ligt lager, geen betrouwbare vaste factor) | CoFID 2021 | 1092 met NSP (zoals voorheen) |
| Vitamine A in RE | RE = retinol + bètacaroteen / 6 (+ andere carotenoïden / 12); RAE → RE: + bètacaroteen / 12 + (alfacaroteen + bètacryptoxanthine) / 24 | EFSA DRV 2015 (PRI in RE) | 3740 omgerekend uit RAE (USDA, Matvaretabellen), 4739 zelf berekend met / 6 |
| B3 in niacine-equivalenten | NE = niacine + tryptofaan (mg) / 60; NE van de bron zelf als die bestaat (CoFID, Frida, Livsmedelsverket) | EFSA DRV 2014 (1,6 mg NE/MJ) | 6537 NE van de bron, 13 618 berekend (2722 daarvan als geschat gemarkeerd: geschatte tryptofaan > helft), 278 zonder tryptofaan (blijft voorgevormd) |
| CoFID tryptofaan | tryptofaan (g) = tryptofaan/60 (mg) × 60 / 1000 | CoFID 2021 | 2642 nu gemeten |
| Onwaarschijnlijke metingen | > 15× het 99e percentiel van de voedingsgroep (én > ¼ van het 99,9e percentiel van alles), of > 3× het 99,9e percentiel van alles, zonder steun van hetzelfde voedingsmiddel elders | `outlier_pass` | 6 weggelaten, 15 nagekeken en behouden (`tool/outlier_report.md`, `tool/outlier_keep.json`) |

Over alle producten veranderden (meer dan 0,5 %): B3 18 812, vitamine A 9912, tryptofaan 7788 (ook doorgegeven
schattingen), koolhydraten 1885 (alleen CoFID), zetmeel 1835, suikers 1647, mangaan 31, B5 15. De energie verandert
nergens: CoFID rekende met 3,75 kcal per g monosacharide-equivalent.

Weggelaten (en daarna geschat zoals elke ontbrekende waarde): mangaan in de eiwitshake `usda_sr:174181` (125 mg),
linzensoep `cofid:17-808` (29 mg) en gedroogde jujube `usda_sr:168152` (31 mg); B5 in energiedrank `ciqual:18354`
(135 mg) en rauwe kalfslever `frida:698` (55 mg); bètacaroteen in gedroogde wakame `ciqual:20984` (104 mg).

## Voor en na

| Product | Voor | Na |
|---|---|---|
| Havermout, eerste resultaat 'oats' | CoFID porridge oats: 70,7 g koolhydraten, 7,8 g vezel | Matvaretabellen rolled oats: 57,3 g |
| Havermout, eerste resultaat 'havermout' | CoFID porridge oats: 70,7 g | Frida havervlokken: 58,9 g, 9,9 g vezel |
| CoFID porridge oats zelf | 70,7 g koolh., 70,4 g zetmeel | 64,3 g, 64,0 g zetmeel (nu bij "Andere bronnen") |
| CoFID rijst lange korrel, gekookt | 31,1 g | 28,3 g (USDA 28,2) |
| CoFID pasta wit, gekookt | 37,2 g | 33,9 g |
| Halfvolle melk, eerste resultaat | CoFID: B12 0,9 µg/100 g | Matvaretabellen: B12 0,6 µg/100 g (CoFID bij "Andere bronnen") |
| Halfvolle melk CoFID, B3 | 0,1 mg | 0,7 mg NE |
| Kipfilet gebraden (USDA), B3 | 13,7 mg | 19,75 mg NE |
| Wortel rauw (CIQUAL), vitamine A | 1100 µg RAE | 2200 µg RE |
| Eiwitshake (USDA), mangaan | 125 mg (30 g = >999 %) | ≈ 0,18 mg (geschat, niet bij de rijkste bronnen) |

## In de app

- Bronvoorkeur (`FoodSource.priority`): CIQUAL, Frida, Matvaretabellen, Livsmedelsverket, dan CoFID, dan USDA, voor
  de hoofdbron van een groep in het zoekvak, Snel loggen en de suggesties.
- Eén regel voor "te veel" (`isTooMuch`): rood alleen boven een bovengrens of limiet; zonder maximum (EPA+DHA,
  aminozuren, mangaan) nooit rood, ook niet boven 300 %. De score telt met dezelfde regel en zegt nu dat ze over de
  vitaminen en mineralen gaat.
- Een bron die per 100 g meer dan 10× de bovengrens geeft (of zonder bovengrens 10× het doel, buiten gewone
  basisvoeding) wordt niet als bron aangeraden (`absurdShare`).
- Labels: "Vitamin A (RE)", "B3 (niacin equivalents)".

## Na de onafhankelijke controle (r11/data-verificatie.md, punten 1-11)

Versie `db1143d85e05` → `f859b4474021` (20 576 producten). Twee keer gebouwd: dezelfde versie, dezelfde inhoud.
Nauwkeurigheidstest (`HOLDOUT=3000`): typische afwijking 26 % → 24 %, binnen ±25 % 49 % → 51 %, binnen 2× 78 % → 78 %.

| Punt | Regel | Producten |
|---|---|---|
| 1. Tryptofaan | Gemeten tryptofaan boven 2,5 % van het eiwit (bij ≥ 1 g eiwit) valt weg en wordt opnieuw geschat; de NE van de bron, die op dezelfde tryptofaan steunt, ook. Behalve als een andere databank voor hetzelfde voedingsmiddel ook > 2 % meet (dadels, pecannoten) of na controle (`outlier_keep.json`). Tryptofaan, chroom, molybdeen en retinol zitten nu in de uitschieterscontrole | 35 weggelaten, 10 gesteund door een tweede databank |
| 2. NE van de bron | B3 = max(NE van de bron, niacine + tryptofaan / 60), met 10 % speling voor de NE van de bron. Frida laat bij granen de niacine weg (§7.2), CoFID heeft rekenfouten | 1214 met de som in plaats van de bron-NE |
| 3. Matvaretabellen | `NIAEQ` als NE van de bron, zoals CoFID, Frida en Livsmedelsverket | 2118 |
| 4. Halfvolle melk | Melk met een EU-benaming waarvan het vetgehalte niet past (magere ≤ 0,5 %, halfvolle 1,5-1,8 %, volle ≥ 3,5 %, Verordening (EU) 1308/2013) komt niet vooraan in een groep (`offStandardMilk`) | app |
| 5. Kipfilet | Met vel (labeldeel `muscle+skin`, "meat and skin") −10 in het zoeken, tenzij je "skin" of "vel" typt; "met vel gegrild, alleen het vlees" telt als zonder vel | app |
| 6. Donors | Een nagekeken uitschieter is nooit donor. Een drank of aftreksel (vetvrije droge stof < 3 g) leent niets van een droog product (> 10 g), en aminozuren niet van een product met < 1 g eiwit. Planten, algen en paddenstoelen: jodium mag van rauw naar gedroogd (alleen water verschilt). Geen groepsschatting voor cafeïne bij koffie, thee, cacao en cola, en geen leverproducten in een groepsgemiddelde voor vitamine A of retinol van een product zonder lever | – |
| 7. Pieken binnen een soort | Tweede toets in `outlier_pass`: per gram basis meer dan 6× de mediaan van minstens 2 andere producten van dezelfde soort (labelgroep + deel + hoofdwoord van het voedingsmiddel of de naam, of het Latijnse geslacht), alleen mineralen en B-vitaminen van enkelvoudige voedingsmiddelen | 17 weggelaten, 4 nagekeken en behouden |
| 8. Retinol | Voorgevormd retinol als eigen sleutel `retinol` (µg): uit de bron, of RAE − bètacaroteen / 12 − andere carotenoïden / 24 (USDA, Matvaretabellen) als het niet apart staat; planten 0; anders geschat zoals elke waarde. In de app: "waarvan retinol" onder vitamine A, bovengrens 3000 µg (EFSA/SCF, lager onder 18 jaar), rood boven de grens, in "wat aandacht vraagt" en in de gezondheidscheck. Geen bovengrens op het totaal (RE) | 18 642 gemeten (168 afgeleid uit RAE), 1805 geschat |
| 9. CoFID zonder opsplitsing | Geen zetmeel en geen suikers: koolhydraten ÷ 1,10 bij zetmeelrijke producten (labelgroep granen, brood, pasta, rijst, peulvruchten, aardappelen), anders ÷ 1,05. Zetmeel gemeten maar suikers niet: de rest ÷ 1,05. Niet als geschat gemarkeerd: het is een omrekening van een gemeten waarde, met hooguit 5 % onzekerheid | 57 (7 zetmeelrijk) + 14 |
| 10. Tryptofaanschatting | Groepsschattingen van aminozuren begrensd als verhouding tot het eiwit, niet als absolute waarde; ook de oudste aanvulronde (op naam) schaalt met het eiwit. Mediaan geschat 1,17 % van het eiwit, p99 1,94 % | – |
| 11. Rijst | "Parboiled" en "pre-boiled" tellen als bijzondere vorm (`_variant`): niet de hoofdbron van "rijst" | app |

Verder, gevonden bij het nakijken: een vitamine A die we uit gemeten retinol en geschat bètacaroteen berekenden, telt
alleen als geschat als het caroteendeel de doorslag geeft (lever verloor anders zijn vitamine A in de controle op
geschatte uitschieters); die controle laat een schatting staan die binnen het bereik van de metingen van hetzelfde
voedingsmiddel valt (244 waarden, vooral lever); een verbeterde vitamine A of retinol in `food_fixes.json` wordt niet
meer overschreven; vijf vitamine A-correcties kregen ook hun retinol (lamslever 435 µg, paneer en Port Salut 0 µg,
melkpoeder 1182 µg, verrijkte margarine 0 µg). Gans zonder vel, gebraden (Matvaretabellen): niacine 33,2 mg en NE 82
weggelaten.

| Product | Voor | Na |
|---|---|---|
| Rundshart rauw, B3 (Frida / CIQUAL / Matvaretabellen) | 40,1 / 40,8 / 40,6 mg NE | 11,0 / 10,4 / 10,8 (NIAEQ van Matvaretabellen) |
| Gemalen koffie, B3 (Frida / CIQUAL) | 125 / 126 mg NE | 16,6 / 17,7 |
| Theebladeren, B3 (Frida) | 21,1 | 10,0 |
| Schorseneer rauw, B3 (Frida) | 18,3 | 0,85 (geschat) |
| Tarwezemelen / rijstzemelen, B3 (Frida) | 3,4 / 3,1 | 33,0 / 37,1 |
| Gedroogde basilicum / lamscurry, B3 (CoFID) | 1,6 / 0,6 | 10,6 / 5,9 |
| Havervlokken, B3 (Frida) | 2,98 | 3,78 |
| Verse spirulina, jodium (CIQUAL / USDA) | 35 940 / 3485 µg (geschat) | onbekend / 2,3 µg |
| Groene thee en thee met melk, chroom | 335 µg per 100 ml (geschat) | onbekend |
| Zeeduivel (*Lophius budegassa*) / grenadier, selenium | 414 / 356 µg | 37,5 / 30,1 (geschat) |
| Gans zonder vel gebraden (MVT), B3 / zink / fosfor | 39,9 / 22,6 / 2563 | 10,7 / 3,1 / 301 (geschat) |
| Kalfslever rauw (CIQUAL), retinol | – | 13 800 µg |
| Kalfslever gekookt (CIQUAL), vitamine A | weggevallen | 10 530 µg RE |
| Wortel rauw (CIQUAL), retinol / vitamine A | – / 2200 | 0 / 2200 |
| Pintobonen gekookt / tamarinde (CoFID), koolhydraten | 23,9 / 56,5 g | 21,7 / 53,8 g |
| Eerste resultaat "semi-skimmed milk", "halfvolle melk", "milk" | Matvaretabellen 0,8 % vet, 39 kcal | CIQUAL halfvolle melk (gemiddelde) 1,55 % vet, 47,5 kcal |
| Eerste resultaat "chicken breast", "kipfilet" | CoFID gegrild met vel, 173 kcal, 6,4 g vet | CIQUAL zonder vel gegrild, 141 kcal, 30,1 g eiwit |
| Eerste resultaat "rice", "rijst" | Matvaretabellen parboiled, 112 kcal, 61 mg calcium | Matvaretabellen basmati gekookt, 115 kcal, 6 mg calcium |
| Eerste resultaat "egg" (bijwerking: meer gemeten waarden) | CIQUAL hardgekookt ei, 134 kcal | Matvaretabellen gekookt ei, 148 kcal (USDA 155) |

Niet veranderd: USDA cheddar (173414) heeft een gemeten tryptofaan van 0,547 g (2,4 % van het eiwit, onder de grens).
De "0,156 g" uit de controle was USDA hüttenkäse (167703, 12,4 g eiwit, 1,25 %): de schatting klopt.
