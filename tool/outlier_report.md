# Onwaarschijnlijke metingen

Geschreven door `tool/build_foods.py` (zie `outlier_pass` en `tryptophan_check`). Per 100 g. Referentie: "groep" = 99e percentiel van de voedingsgroep; "soort: x" = mediaan van andere producten van dezelfde soort (zelfde labelgroep en hoofdwoord, of hetzelfde Latijnse geslacht), omgerekend naar dit product; bij tryptofaan het aandeel van het eiwit. Alle = 99,9e percentiel van alle producten. Weggelaten waarden worden daarna geschat zoals elke ontbrekende waarde. Behouden staat met de reden in `tool/outlier_keep.json` (en is nooit donor bij het aanvullen), of wordt gesteund door een andere databank.

| product | naam | groep | stof | waarde | referentie | alle | wat |
|---|---|---|---|---|---|---|---|
| ciqual:10026 | Mediterranean mussel, raw | shellfish | copper | 1.1 | 0.1414 (soort: mussel) | 9.83 | weggelaten |
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | beta_carotene | 155000.0 | 592.0 (groep) | 15430.0 | behouden: spirulina is een van de rijkste bronnen van bètacaroteen (in de literatuur 80-200 mg per 100 g droog) |
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | vit_a | 25830.0 | 98.67 (groep) | 20080.0 | behouden: volgt uit het bètacaroteen van spirulina |
| ciqual:15045 | Sunflower seed, grilled, salted | nut/seed | b5 | 7.04 | 0.7565 (soort: sunflower) | 15.38 | weggelaten |
| ciqual:15045 | Sunflower seed, grilled, salted | nut/seed | zinc | 36.0 | 5.261 (soort: sunflower) | 22.5 | weggelaten |
| ciqual:18354 | Energy drink, with sugar(s) and with sweetener(s) | beverage | b5 | 135.0 | 4.53 (groep) | 15.38 | weggelaten |
| ciqual:20984 | Wakame (Undaria pinnatifida), dried or dehydrated | vegetable | beta_carotene | 104000.0 | 11320.0 (groep) | 15430.0 | weggelaten |
| ciqual:20985 | Sea lettuce (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2660.0 | 480.0 (groep) | 721.0 | behouden: zeesla (Ulva) gedroogd: 2-3 g magnesium per 100 g is gewoon voor dit zeewier |
| ciqual:20993 | Gracilaria seaweeds (Gracilaria sp.), dried or dehydrated | vegetable | iodine | 356000.0 | 42000.0 (groep) | 36000.0 | behouden: gedroogd zeewier: jodium varieert sterk per soort en oogst; zeer hoog is hier geen eenheidsfout |
| ciqual:20995 | Gut weed (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2260.0 | 480.0 (groep) | 721.0 | behouden: darmwier (Ulva) gedroogd: zelfde soort als zeesla, hoog magnesium |
| ciqual:26113 | Horse mackerel, raw | fish | copper | 0.99 | 0.07356 (soort: mackerel) | 9.83 | weggelaten |
| ciqual:26128 | Roundnose grenadier, raw | fish | selenium | 356.0 | 36.72 (soort: grenadier) | 210.0 | weggelaten |
| ciqual:26208 | Anglerfish (Lophius budegassa), raw | fish | selenium | 414.0 | 37.54 (soort: monkfish) | 210.0 | weggelaten |
| cofid:11-725 | Noodles, rice, fine, dried, boiled in unsalted water | pasta | tryptophan | 0.048 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| cofid:12-551 | Cheese, spreadable, full fat, soft, white | dairy | tryptophan | 0.162 | 3.1 % van het eiwit | max 2.5 % | weggelaten |
| cofid:13-340 | Seaweed, nori, dried, raw | vegetable | b12 | 27.5 | 0.3 (groep) | 84.6 | behouden: nori bevat B12 (in de literatuur 30-70 µg per 100 g gedroogd) |
| cofid:13-341 | Seaweed, wakame, dried, raw | vegetable | b12 | 2.5 | 0.1104 (soort: wakame) | 84.6 | behouden: zeewier (wakame) bevat B12 en B12-analogen; gemeten waarden lopen sterk uiteen (0,3 tot enkele µg per 100 g droog) |
| cofid:13-505 | Mushrooms, white, raw | mushroom | tryptophan | 0.03 | 3.0 % van het eiwit | max 2.5 % | weggelaten |
| cofid:13-506 | Mushrooms, white, stewed in unsalted water | mushroom | tryptophan | 0.048 | 3.4 % van het eiwit | max 2.5 % | weggelaten |
| cofid:13-507 | Mushrooms, white, fried in rapeseed oil | mushroom | tryptophan | 0.042 | 3.0 % van het eiwit | max 2.5 % | weggelaten |
| cofid:13-546 | Mushrooms, white, fried in corn oil | mushroom | tryptophan | 0.042 | 3.0 % van het eiwit | max 2.5 % | weggelaten |
| cofid:14-083 | Dates, raw, flesh and skin | fruit | tryptophan | 0.042 | 2.8 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in frida:533 |
| cofid:14-084 | Dates, raw, flesh and skin, weighed with stones | fruit | tryptophan | 0.036 | 2.8 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in frida:533 |
| cofid:14-394 | Dates, dried, flesh and skin | fruit | tryptophan | 0.09 | 3.8 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in frida:533 |
| cofid:14-399 | Dates, dried, flesh and skin, weighed with stones | fruit | tryptophan | 0.078 | 3.9 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in frida:533 |
| cofid:14-837 | Pecan nuts, kernel only | nut/seed | tryptophan | 0.246 | 2.7 % van het eiwit | max 2.5 % | behouden: ook 2.6 % in frida:515 |
| cofid:14-838 | Pecan nuts, kernel only, weighed with shells | nut/seed | tryptophan | 0.12 | 2.7 % van het eiwit | max 2.5 % | behouden: ook 2.6 % in frida:515 |
| cofid:15-642 | Garlic mushrooms, not coated, homemade | dish | tryptophan | 0.036 | 3.0 % van het eiwit | max 2.5 % | weggelaten |
| cofid:16-270 | Winkles, boiled | shellfish | b2 | 0.38 | 0.04694 (soort: winkle) | 4.55 | behouden: alikruiken: 0,2-0,4 mg B2 is gewoon voor weekdieren; de enige andere meting (CIQUAL) is laag |
| cofid:17-721 | Soy sauce, light and dark varieties | sauce/condiment | tryptophan | 0.084 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| cofid:17-808 | Soup, lentil, homemade | soup | manganese | 29.0 | 0.8 (groep) | 30.37 | weggelaten |
| cofid:17-825 | Instant drinks powder, malted, unfortified | beverage | tryptophan | 0.156 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | copper | 10.84 | 0.5 (groep) | 9.83 | behouden: gerecht met lever: lever is de rijkste bron van koper |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | retinol | 15750.0 | 390.0 (groep) | 20000.0 | behouden: gerecht met lever: het vitamine A van lever is bijna allemaal retinol |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | vit_a | 15760.0 | 780.2 (groep) | 20080.0 | behouden: gerecht met lever: lever is de rijkste bron van vitamine A |
| cofid:19-604 | Liver and onions, stewed, homemade | dish | retinol | 11960.0 | 390.0 (groep) | 20000.0 | behouden: gerecht met lever: het vitamine A van lever is bijna allemaal retinol |
| cofid:19-604 | Liver and onions, stewed, homemade | dish | vit_a | 11970.0 | 780.2 (groep) | 20080.0 | behouden: gerecht met lever: lever is de rijkste bron van vitamine A |
| frida:1075 | Coffee bean, roasted, ground | beverage | tryptophan | 6.6 | 48.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:1089 | Black salsify, raw | vegetable | tryptophan | 1.08 | 32.7 % van het eiwit | max 2.5 % | weggelaten |
| frida:1193 | Pecans, oil roasted | nut/seed | tryptophan | 0.243 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:1194 | Pecans, dry roasted | nut/seed | tryptophan | 0.2509 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:1454 | Saithe (UK), pollock (US), liver oil | oil/fat | vit_d | 500.0 | 250.0 (groep) | 41.2 | behouden: visleverolie: 100-500 µg vitamine D per 100 g is normaal |
| frida:1573 | Butter cookie, wheat, Danish, industrially produced | bakery | tryptophan | 0.129 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| frida:1829 | Pomegranate seeds, frozen | fruit | tryptophan | 0.0369 | 3.6 % van het eiwit | max 2.5 % | weggelaten |
| frida:515 | Pecans, dried | nut/seed | tryptophan | 0.2422 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:533 | Date, dried | fruit | tryptophan | 0.0544 | 2.7 % van het eiwit | max 2.5 % | behouden: ook 3.8 % in cofid:14-394 |
| frida:537 | Tea, leaves | beverage | tryptophan | 0.8154 | 4.2 % van het eiwit | max 2.5 % | weggelaten |
| frida:566 | Heart, veal, raw | offal | tryptophan | 1.645 | 11.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:641 | Heart, beef, raw | offal | tryptophan | 1.956 | 11.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:698 | Liver, calf, raw | offal | b5 | 54.65 | 10.3 (groep) | 15.38 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | magnesium | 197.0 | 29.18 (soort: goose) | 721.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | phosphorus | 2563.0 | 372.1 (soort: goose) | 1650.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | potassium | 3653.0 | 500.9 (soort: goose) | 4740.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | zinc | 22.6 | 2.93 (soort: goose) | 22.5 | weggelaten |
| mvt:06.261 | Purslane, raw | vegetable | b9 | 131.0 | 5.723 (soort: purslane) | 2340.0 | weggelaten |
| mvt:06.850 | Kale, steamed | vegetable | copper | 1.49 | 0.05354 (soort: kale) | 9.83 | weggelaten |
| mvt:12.023 | Salt, mineral | other | potassium | 21000.0 | 20780.0 (groep) | 4740.0 | behouden: mineraalzout met kaliumchloride: ongeveer een vijfde kalium |
| slv:4124 | Lamb liver fried w/ salt | offal | b9 | 2080.0 | 323.4 (soort: lamb) | 2340.0 | weggelaten |
| slv:4131 | Palmoil | oil/fat | beta_carotene | 15430.0 | 925.0 (groep) | 15430.0 | behouden: (rode) palmolie bevat 30-70 mg bètacaroteen per 100 g |
| usda_fnd:2262075 | Flaxseed, ground | nut/seed | selenium | 135.9 | 14.57 (soort: flaxseed) | 210.0 | weggelaten |
| usda_fnd:2346386 | Cream, heavy | dairy | tryptophan | 0.066 | 3.3 % van het eiwit | max 2.5 % | weggelaten |
| usda_fnd:2710819 | Chia seeds, dry, raw | nut/seed | tryptophan | 0.436 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:167634 | Mutton, cooked, roasted (Navajo) | meat | selenium | 38.0 | 4.47 (soort: mutton) | 210.0 | behouden: schapenvlees heeft elders 20-30 µg selenium (USDA lam); de Noorse en Zweedse metingen zijn laag door seleenarme grond |
| usda_sr:167714 | Hearts of palm, raw | vegetable | b6 | 0.81 | 0.07238 (soort: hearts) | 2.74 | behouden: rauwe palmharten tegenover palmharten uit blik: B6 lost op in het kookvocht |
| usda_sr:167760 | Sapote, mamey, raw | fruit | tryptophan | 0.049 | 3.4 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:167971 | Candies, TOOTSIE ROLL, chocolate-flavor roll | sugar/sweets | tryptophan | 0.19 | 11.9 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168063 | Restaurant, Latino, arroz con leche (rice pudding) | dessert | tryptophan | 0.084 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168152 | Jujube, Chinese, fresh, dried | fruit | manganese | 31.07 | 2.0 (groep) | 30.37 | weggelaten |
| usda_sr:168457 | Seaweed, kelp, raw | vegetable | tryptophan | 0.048 | 2.9 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168982 | Blackberries, wild, raw (Alaska Native) | fruit | b5 | 1.258 | 0.1502 (soort: blackberry) | 15.38 | weggelaten |
| usda_sr:168993 | Agave, dried (Southwest) | vegetable | zinc | 12.1 | 0.6843 (soort: agave) | 22.5 | weggelaten |
| usda_sr:169001 | Sea lion, Steller, kidney (Alaska Native) | offal | tryptophan | 1.2 | 6.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:169287 | Spinach, frozen, chopped or leaf, unprepared (Includes foods for USDA's Food Distribution Program) | vegetable | tryptophan | 0.1 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:169288 | Spinach, frozen, chopped or leaf, cooked, boiled, drained, without salt | vegetable | tryptophan | 0.101 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:169373 | Peppers, sweet, red, freeze-dried | vegetable | vit_c | 1900.0 | 165.0 (groep) | 295.0 | behouden: gevriesdroogde rode paprika: het vitamine C van verse paprika, zonder water (~10× geconcentreerd) |
| usda_sr:169824 | Sea lion, Steller, meat with fat (Alaska Native) | meat | tryptophan | 1.6 | 7.2 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170124 | Spinach, frozen, chopped or leaf, cooked, boiled, drained, with salt | vegetable | tryptophan | 0.101 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170143 | Mushrooms, portabella, exposed to ultraviolet light, raw | mushroom | tryptophan | 0.056 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170552 | Seeds, breadnut tree seeds, raw | nut/seed | tryptophan | 0.162 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170553 | Seeds, breadnut tree seeds, dried | nut/seed | tryptophan | 0.234 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170554 | Seeds, chia seeds, dried | nut/seed | tryptophan | 0.436 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170569 | Nuts, brazilnuts, dried, unblanched | nut/seed | selenium | 1917.0 | 280.4 (groep) | 210.0 | behouden: paranoten zijn de rijkste bron van selenium; de USDA-waarde is een bekend gemiddelde |
| usda_sr:171263 | Cream substitute, powdered | other | tryptophan | 0.066 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:171620 | Bratwurst, pork, cooked | processed meat | tryptophan | 0.347 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:173040 | Grapes, muscadine, raw | fruit | b2 | 1.5 | 0.008912 (soort: grape) | 4.55 | weggelaten |
| usda_sr:173237 | Beverages, Orange-flavor drink, breakfast type, low calorie, powder | beverage | vit_c | 2400.0 | 189.7 (groep) | 295.0 | behouden: verrijkt poeder voor een sinaasappeldrank: per 100 g poeder, aangelengd een gewone hoeveelheid |
| usda_sr:174181 | Beverages, nutritional shake mix, high protein, powder | supplement | manganese | 125.0 | 30.37 (groep) | 30.37 | weggelaten |
| usda_sr:174283 | Winged beans, mature seeds, raw | legume | tryptophan | 0.762 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:174783 | Snacks, sweet potato chips, unsalted | snack | tryptophan | 0.098 | 3.3 % van het eiwit | max 2.5 % | weggelaten |
