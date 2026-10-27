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

## Restpunten na de controle (harder, nullen, NE bij merkproducten, molybdeen, retinol uit supplementen, spirulina)

Versie `f859b4474021` → `37c9dfe721a2` (20 576 producten). Drie keer gebouwd (ook met een andere `PYTHONHASHSEED`):
dezelfde versie, dezelfde inhoud. Nauwkeurigheidstest (`HOLDOUT=3000`): 24 % / 50 % / 78 % (was 24 / 51 / 78).
Over alle producten: 961 waarden veranderd (622 producten), 14 bijgekomen, 5 weggevallen (zetmeel en alcohol bij
rijst die ze van voorgekookte rijst leende).

| Punt | Regel | Waarden |
|---|---|---|
| 1. Harder | `food_fixes.json`: selenium van CIQUAL "Mullet, raw" (`ciqual:26091`) weg, daarna geschat. Zelfde CIQUAL-bron (source_code 257) als de zeeduivel en de grenadier; de andere harders meten 36-51 µg. De drempel verlagen werkt niet zuiver: per gram droge stof is het 4,1× de mediaan (grens 6×) en gegrilde harder ligt boven een kwart, dus ook de steun-regel moet om (4× en een derde). Dat vangt dan ook schar (CoFID 70 µg, maar Zweedse schol meet 62-107 µg), witte kool (20 µg) en gedroogde kervel: geen duidelijke fouten | 2 (rauw en gebakken) |
| 2. Nullen die niet gemeten zijn | `zeros_not_measured`: calcium, ijzer, magnesium, kalium, fosfor en zink zitten in elke cel. Een 0 in een enkelvoudig voedingsmiddel (granen, rijst, pasta, brood, ontbijtgranen, peulvruchten, groenten, aardappelen, noten; vlees, gevogelte, orgaanvlees, vis, schaaldieren) valt weg en wordt geschat (en als geschat getoond). Bij vlees en vis ook selenium. Niet bij zetmeel, lutefisk, zeewierkaviaar, fruit, eiwit van ei en paddenstoelen (daar is 0 een eerlijke afronding), en een correctie in `food_fixes.json` gaat voor | 68 nullen |
| 2. Onder de meetgrens (Matvaretabellen) | Bron 60a ("below the limit of quantification") is geen 0 maar "<": bij een enkelvoudig product (geen gerecht, mengsel, snoep of ontbijtgraan) eerst aanvullen uit hetzelfde voedingsmiddel elders, anders 0, zoals CIQUAL "<" (`mvt_below_loq`) | 165 vitaminen en mineralen, 90 daarvan aangevuld |
| 2. Onder een bekende meetgrens | CIQUAL "<" bij de mineralen en voedingsmiddelen hierboven: zonder ander gegeven de helft van de grens in plaats van 0 (alikruik gekookt, selenium < 20 → 10 µg) | 3 |
| 2. Selenium 0 in planten | Blijft staan (seleenarme grond, vooral Scandinavië), maar is geen donor meer: Amerikaanse gekookte rijst leende 0 µg van de Noorse | 254 producten (meestal 0 → 0,1-2 µg) |
| 2. Voorgekookte rijst | Eigen labelvlag `parboiled` (ook "pre-boiled", "easy cook"): parboiled rijst neemt calcium op uit het weekwater (71 mg tegenover 9-28 mg, USDA en CIQUAL). Gewone rijst wordt niet meer aangevuld uit voorgekookte en omgekeerd; in de app een eigen groep | 342 waarden bij rijst (alle regels samen) |
| 4. Paprika, molybdeen | `food_fixes.json`: molybdeen van Frida rode paprika (`frida:38`) weg. 70 µg is het gemiddelde van 2 bepalingen van 10 en ~130 µg, het hoogste van alle groenten in Frida (mediaan 2 µg); gele paprika 0,7 µg, groene 0; geen andere databank heeft molybdeen voor paprika. Het werd naar alle andere rode paprika's doorgegeven | 31 paprikaproducten |
| 6. Verse spirulina | Een geschatte waarde die per gram basis (vetvrije droge stof) binnen het bereik van de metingen van hetzelfde voedingsmiddel valt, is geen uitschieter, bij een enkelvoudig plantaardig product, alg of paddenstoel (alleen water verschilt). Verse spirulina houdt zo het jodium van gedroogde spirulina, omgerekend | 14 |

| Product | Voor | Na |
|---|---|---|
| Harder rauw / gebakken (CIQUAL), selenium | 168 / 198 µg | 39,7 / 46,8 µg (geschat uit USDA gestreepte harder) |
| Witte langkorrelrijst gekookt (MVT), calcium / ijzer | 0 / 0 | 1,8 mg / 0,18 mg (geschat) |
| Witte langkorrelrijst ongekookt (MVT), calcium / ijzer / selenium | 0 / 0 / 0 | 15,4 mg / 0,25 mg / 12,5 µg (geschat) |
| Langkorrelrijst ongekookt (SLV), calcium / ijzer | 0 / 0 | 15,7 mg / 0,26 mg (geschat; met de parboiled-donor was het 175 mg) |
| Zeeduivel rauw (MVT), ijzer | 0 | 0,29 mg |
| Bleekselder rauw (USDA Foundation), ijzer | 0 | 0,21 mg |
| Gerookte kalkoenham (MVT), selenium | 0 (60a) | 34 µg |
| Rode paprika rauw (Frida) / gevriesdroogd (USDA), molybdeen | 70 / 741 µg | 0,37 / 3,9 µg |
| Verse spirulina (CIQUAL), jodium | onbekend | 2,3 µg (geschat uit gedroogde spirulina, per droge stof) |

### In de app

- **3. B3 bij merkproducten** (`lib/nutrition/niacin.dart`): een etiket (Open Food Facts `off:`, USDA-barcode `fdc:`)
  en een eigen product (`custom:`) geven alleen voorgevormde niacine. Bij het tellen komt er tryptofaan / 60 bij: de
  tryptofaan van het product als die er is, anders 1,2 % van het eiwit (12 mg per g eiwit, de mediaan in de databank is
  1,17 %), dus + 0,2 mg NE per g eiwit. Alleen als niacine en eiwit bekend zijn, en als geschat gemarkeerd (≈, met uitleg
  bij de waarde). Niet als B3 uit het basisproduct van de databank komt (dat is al NE), niet bij supplementen. Een recept
  telt het per ingrediënt. Het gebeurt bij het tellen (`AppState._counted`, ook voor oudere dagboekregels); de bewaarde
  waarden blijven die van het etiket, dus nooit dubbel. Een eiwitreep met 30 g eiwit en 8 mg niacine telt 14 mg NE.
- **5. Retinol uit supplementen** (`supplementRetinol` in `lib/nutrition/supplements.dart`): de vitamine A van een
  supplement telt als retinol (retinylacetaat of -palmitaat, "vitamine A (retinol)", een multivitamine), behalve
  bètacaroteen (in de naam, of apart ingevuld: vitamine A − bètacaroteen / 6). Ook bij het tellen, dus ook voor
  supplementen die al in het dagboek staan. Eén dag 100 g runderlever per week (4948 µg) blijft onder de grens; met
  2400 µg retinol per dag erbij gemiddeld ~3100 µg: waarschuwing. Met 2400 µg vitamine A uit bètacaroteen: geen.

Niet veranderd: het selenium van planten met een 0 (seleenarme grond is echt), witte rijst van Matvaretabellen houdt
selenium 0 (receptberekening uit ongekookte rijst onder de meetgrens). Overige CIQUAL "<"-waarden blijven 0 als er
geen ander gegeven is.

## Namen (25-10)

Versie blijft `37c9dfe721a2` (alleen namen en zoektekst, geen waarden). CoFID "Potato chips, …" heet nu "French fries, …"
(Britse chips zijn frieten) en Matvaretabellen "Oatmeal" met lokale naam "Havremel" heet "Oat flour". De oude naam blijft
in de zoektekst. Eerder gebeurde dit alleen bij het tonen (`tidyFoodName`), waardoor de nieuwe naam niet vindbaar was.

## 26-10-2026: BLS 4.0 en FNDDS erbij

- **BLS 4.0** (Max Rubner-Institut, Duitsland, CC BY 4.0): 7.140 voedingsmiddelen, Engelse naam met de Duitse als
  lokale naam (doorzoekbaar). Waarden zoals BLS ze geeft, ook de eigen berekeningen van BLS (zoals bij CIQUAL en
  Livsmedelsverket). Vitamine A staat al als RE; B6, koper, mangaan en fluoride van µg naar mg.
- **USDA FNDDS 2021–2023** (publiek domein): 3.731 samengestelde gerechten. Producten met één ingrediënt (kopieën van
  SR Legacy), babyvoeding, zuigelingenvoeding en moedermelk niet. "NFS" en "NS as to …" weg uit de getoonde naam.
- Labels voor beide (pakketten 059–070, voedingsapp-data/labels), met een gelijktrekronde voor varianten van dezelfde
  naam (harmonize_new.py).
- **Gewogen met afval** (dop, schil, pit, graat): schatten schaalt nu op de energie in plaats van de vetvrije droge stof,
  die de dop meetelde (walnoten met dop kregen 400 µg chroom tegenover 145 in de pit; nu 59).
- **Gejodeerd** telt als eigen product bij het aanvullen op naam: gewoon pekelzout nam de jodium van gejodeerd pekelzout
  over (1.987 µg); nu onbekend.
- Nauwkeurigheid (HOLDOUT=3000, dezelfde verborgen waarden van de oude bronnen, met en zonder de nieuwe):
  typische afwijking 27 % → 26 %, binnen 2× 78 % → 78 %.

## 28-10-2026: Fineli erbij

- **Fineli release 20** (THL, Finland, CC BY 4.0), het pakket met 74 voedingsstoffen: 4.232 voedingsmiddelen, Engelse
  naam met de Finse als lokale naam. Zeer volledig (jodium 96 %, seleen 99 %, vitamine D 100 %, vitamine K 98 %).
  Waarden zoals Fineli ze geeft, ook wat Fineli zelf uit verwante producten aanvult. Omrekeningen: energie kJ → kcal
  (÷ 4,184), vetzuren en tryptofaan mg → g, molybdeen mg → µg, vitamine A van RAE naar RE (andere carotenoïden uit
  RAE − retinol − bètacaroteen / 12). Porties uit `foodaddunit.csv` (klein/middel/groot, stuk, dl, eetlepel, theelepel).
- Labels: pakketten 074–079 (voedingsapp-data/labels). Pakket 075 werd half opnieuw gelabeld: twee hulpen schreven in
  dezelfde map, waardoor regels 181–706 bij de verkeerde producten stonden (opgemerkt met een woordovereenkomst per
  50 regels; nu nagekeken over alle zes pakketten).
- **Tryptofaan**: Fineli neemt waarden over uit andere tabellen (ACQTYPE F) en rekent recepten uit (METHTYPE R, K, I,
  IG, O, U). Zo'n waarde bevestigt geen hoge meting in een andere databank meer (`copied`, `tryptophan_check`), en een
  bevestiging die zelf boven 2,5 % ligt, telt alleen als die zelf door een eigen meting bevestigd is. Eekhoorntjesbrood
  (BLS en Fineli allebei 0,21 g, 3,9–6,7 % van het eiwit) blijft daardoor weggelaten: gedroogd B3 53 → 33 mg NE.
- Frida `754` "Chicken, breast, boiled, sliced" (1120 mg natrium) is beleg: label nu bewerkt vlees, zoals de
  USDA-varianten (`label_fixes.json`).
- Zoeken: Fineli komt bij gelijke stand na de andere Europese tabellen (vertaalde Engelse namen), en `FoodDb.search`
  rangschikt nu alle treffers voor het een plafond toepast (vroeger 600 rijen in bestandsvolgorde: bij "chicken",
  "beef" of "cheese" vielen de laatste bronnen zonder reden weg).
- Nauwkeurigheid (HOLDOUT=3000, HOLDOUT_OLD=1, dezelfde verborgen waarden): over alles gelijk, 26 % typische afwijking,
  78 % binnen 2×. Jodium 65 → 52 %, B3 33 → 27 %, B6 32 → 27 %; vitamine C 48 → 59 %, EPA 65 → 74 % (kleine aantallen).
  Fineli helpt vooral door zijn eigen, bijna volledig gemeten producten, niet door het schatten voor andere.
- Databank `f8ed384cef93`, 35.679 producten, 81,0 MB.

## 28-10-2026: NEVO erbij

- **NEVO-online 2025/9.0** (RIVM, Nederland): 2.328 voedingsmiddelen, Engelse naam met de Nederlandse als lokale naam,
  synoniemen doorzoekbaar. Gebruik met toestemming van het RIVM (antwoord 27-10-2026, voedingsapp-data/nevo/
  antwoord-rivm.txt): gratis voor iedereen in de app, ook in de openbare repo, en ontbrekende waarden mogen geschat
  worden uit hetzelfde voedingsmiddel in een andere tabel, gemarkeerd met ≈.
- NEVO-waarden blijven onveranderd: geen correcties, geen uitschieterscontrole, geen nullen of plantenregels. De rijen
  komen pas na alle verwerking erbij. Gecontroleerd: 103.137 NEVO-waarden, 0 veranderd, 0 als schatting gemarkeerd.
- `nevo_fill`: wat NEVO niet heeft, alleen uit hetzelfde voedingsmiddel (zelfde label: product, deel, gerecht,
  bereiding, kenmerken), alleen uit gemeten waarden, omgerekend naar dit product zoals label_fill ronde 1. Nooit uit een
  verwant product of de groep. 31.110 waarden; daarna jodium 92 %, seleen 95 %, vitamine D 99 %, vitamine K 86 % van de
  NEVO-producten.
- NEVO is geen donor voor andere producten en telt niet mee in de nauwkeurigheidstest.
- Zoeken: NEVO zoals Fineli na de andere Europese tabellen (vertaalde Engelse namen); de app blijft Engelstalig eerst.
- Bronvermelding zoals met het RIVM afgesproken: "Based on data from NEVO online version 2025/9.0, RIVM, Bilthoven and
  other data sources" (productscherm, Instellingen → Bronnen, README, site).
- Databank 38.007 producten, 85,0 MB.
