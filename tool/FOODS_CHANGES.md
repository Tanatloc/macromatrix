# foods.db: wijzigingen 2026-10-25 (ronde 11: NF-1, NF-2, NF-6, NF-16, NF-17, SP-1, NW-15)

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
