# Onwaarschijnlijke metingen

Geschreven door `tool/build_foods.py` (zie `outlier_pass` en `tryptophan_check`). Per 100 g. Referentie: "groep" = 99e percentiel van de voedingsgroep; "soort: x" = mediaan van andere producten van dezelfde soort (zelfde labelgroep en hoofdwoord, of hetzelfde Latijnse geslacht), omgerekend naar dit product; bij tryptofaan het aandeel van het eiwit. Alle = 99,9e percentiel van alle producten. Weggelaten waarden worden daarna geschat zoals elke ontbrekende waarde. Behouden staat met de reden in `tool/outlier_keep.json` (en is nooit donor bij het aanvullen), of wordt gesteund door een andere databank. Fouten die deze toetsen net missen (harder `ciqual:26091` met 168 µg selenium, 4× de andere harders; rode paprika `frida:38` met 70 µg molybdeen), staan met de reden in `tool/food_fixes.json`.

| product | naam | groep | stof | waarde | referentie | alle | wat |
|---|---|---|---|---|---|---|---|
| bls:E811032 | Fresh pasta egg-free, boiled | pasta | tryptophan | 0.1 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| bls:F306100 | Loganberry raw | fruit | manganese | 600.0 | 2.87 (groep) | 28.0 | weggelaten |
| bls:F407100 | Small cranberry raw | fruit | manganese | 2.3 | 0.02757 (soort: cranberry) | 28.0 | weggelaten |
| bls:F504100 | Date raw | fruit | tryptophan | 0.042 | 2.8 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in frida:533 |
| bls:F532100 | Musk melon/cantaloup, raw | fruit | b9 | 132.0 | 18.02 (soort: cantaloupe) | 2104.0 | weggelaten |
| bls:G210600 | Spinach juice | vegetable | tryptophan | 0.035 | 2.5 % van het eiwit | max 2.5 % | behouden: ook 2.8 % in usda_sr:169287 |
| bls:G995000 | Sushi nori (toasted) | vegetable | b6 | 0.95 | 0.04277 (soort: nori) | 2.58 | weggelaten |
| bls:G995000 | Sushi nori (toasted) | vegetable | magnesium | 337.5 | 30.12 (soort: nori) | 694.0 | weggelaten |
| bls:H250100 | Pistachio nut | nut/seed | chromium | 41.74 | 2.335 (soort: pistachio) | 173.0 | weggelaten |
| bls:K713902 | Chanterelle canned, drained | mushroom | tryptophan | 0.059 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718100 | Porcini mushroom raw | mushroom | tryptophan | 0.21 | 3.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718152 | Porcini mushroom stewed | mushroom | tryptophan | 0.296 | 3.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718162 | Porcini mushroom baked | mushroom | tryptophan | 0.292 | 3.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718182 | Porcini mushroom fried without fat (pan) | mushroom | tryptophan | 0.344 | 3.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718400 | Porcini mushroom dried | mushroom | tryptophan | 1.649 | 5.2 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718432 | Porcini mushroom dried, boiled | mushroom | tryptophan | 0.848 | 5.2 % van het eiwit | max 2.5 % | weggelaten |
| bls:K718902 | Porcini mushroom canned, drained | mushroom | tryptophan | 0.25 | 3.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:M248000 | Yogurt min. 3.5 % fat, with coffee preparation, sweetened | dairy | tryptophan | 0.1 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| bls:N420900 | Coffee instant powder | beverage | tryptophan | 0.6 | 3.1 % van het eiwit | max 2.5 % | weggelaten |
| bls:N440900 | Coffee instant powder decaffeinated | beverage | tryptophan | 0.6 | 3.1 % van het eiwit | max 2.5 % | weggelaten |
| bls:R113100 | Iodised salt with fluoride and folic acid | other | b9 | 17000.0 | 4000.0 (groep) | 2104.0 | weggelaten |
| bls:R411000 | Cutter additives phosphate-based (E 450) | other | phosphorus | 24870.0 | 9918.0 (groep) | 1349.0 | weggelaten |
| bls:R421300 | Potash (99 % potassium carbonate, E 501) | other | potassium | 44420.0 | 21000.0 (groep) | 4350.0 | weggelaten |
| bls:R553000 | Ascorbic acid (E 300) | other | vit_c | 100000.0 | 57.2 (groep) | 266.0 | weggelaten |
| bls:S220400 | Ice cream mixed (chocolate, coffee, vanilla) | dessert | tryptophan | 0.1 | 2.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:S220900 | Ice cream mixed (coffee, vanilla) | dessert | tryptophan | 0.1 | 2.9 % van het eiwit | max 2.5 % | weggelaten |
| bls:S243300 | Ice cream mixed (chocolate, vanilla, coffee, caramel) | dessert | tryptophan | 0.1 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| bls:T800200 | Stockfish (cod unsalted, dried) | fish | molybdenum | 100.0 | 0.0 (soort: cod) | 282.7 | weggelaten |
| bls:X448343 | Porcini mushroom soup | soup | tryptophan | 0.086 | 3.5 % van het eiwit | max 2.5 % | weggelaten |
| bls:X513063 | Porcini mushrooms stewed | mushroom | tryptophan | 0.247 | 3.8 % van het eiwit | max 2.5 % | weggelaten |
| bls:X513163 | Porcini mushrooms stewed, in white basic sauce with cream | mushroom | tryptophan | 0.211 | 3.7 % van het eiwit | max 2.5 % | weggelaten |
| bls:X513263 | Porcini mushrooms fried with tomatoes | mushroom | tryptophan | 0.192 | 3.7 % van het eiwit | max 2.5 % | weggelaten |
| bls:Y073012 | Beef and pork offals with cream sauce | dish | retinol | 5726.0 | 320.0 (groep) | 20000.0 | weggelaten |
| ciqual:10026 | Mediterranean mussel, raw | shellfish | copper | 1.1 | 0.1121 (soort: mussel) | 9.2 | weggelaten |
| ciqual:11009 | Yeast, flakes | supplement | b1 | 11.6 | 11.6 (groep) | 3.187 | weggelaten |
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | beta_carotene | 155000.0 | 592.0 (groep) | 14130.0 | behouden: spirulina is een van de rijkste bronnen van bètacaroteen (in de literatuur 80-200 mg per 100 g droog) |
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | vit_a | 25830.0 | 98.67 (groep) | 20120.0 | behouden: volgt uit het bètacaroteen van spirulina |
| ciqual:15045 | Sunflower seed, grilled, salted | nut/seed | b5 | 7.04 | 0.7565 (soort: sunflower) | 12.6 | weggelaten |
| ciqual:15045 | Sunflower seed, grilled, salted | nut/seed | zinc | 36.0 | 5.261 (soort: sunflower) | 23.0 | weggelaten |
| ciqual:18354 | Energy drink, with sugar(s) and with sweetener(s) | beverage | b5 | 135.0 | 4.167 (groep) | 12.6 | weggelaten |
| ciqual:20984 | Wakame (Undaria pinnatifida), dried or dehydrated | vegetable | beta_carotene | 104000.0 | 10630.0 (groep) | 14130.0 | weggelaten |
| ciqual:20985 | Sea lettuce (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2660.0 | 195.0 (groep) | 694.0 | behouden: zeesla (Ulva) gedroogd: 2-3 g magnesium per 100 g is gewoon voor dit zeewier |
| ciqual:20993 | Gracilaria seaweeds (Gracilaria sp.), dried or dehydrated | vegetable | iodine | 356000.0 | 19100.0 (groep) | 9900.0 | behouden: gedroogd zeewier: jodium varieert sterk per soort en oogst; zeer hoog is hier geen eenheidsfout |
| ciqual:20994 | Toothed wrack or bladder wrack (Fucus serratus et vesiculosus), dried or dehydrated | vegetable | iodine | 42000.0 | 19100.0 (groep) | 9900.0 | weggelaten |
| ciqual:20995 | Gut weed (Ulva sp.), dried or dehydrated | vegetable | iron | 205.0 | 10.4 (groep) | 64.1 | weggelaten |
| ciqual:20995 | Gut weed (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2260.0 | 195.0 (groep) | 694.0 | behouden: darmwier (Ulva) gedroogd: zelfde soort als zeesla, hoog magnesium |
| ciqual:20996 | Carragheen mosses (Chondrus crispus), dried or dehydrated | vegetable | iodine | 31300.0 | 19100.0 (groep) | 9900.0 | weggelaten |
| ciqual:20998 | North Atlantic rockweed (Ascophyllum nodosum), dried or dehydrated | vegetable | iodine | 68500.0 | 19100.0 (groep) | 9900.0 | weggelaten |
| ciqual:26113 | Horse mackerel, raw | fish | copper | 0.99 | 0.06949 (soort: mackerel) | 9.2 | weggelaten |
| ciqual:26128 | Roundnose grenadier, raw | fish | selenium | 356.0 | 36.72 (soort: grenadier) | 208.0 | weggelaten |
| ciqual:26208 | Anglerfish (Lophius budegassa), raw | fish | selenium | 414.0 | 37.54 (soort: monkfish) | 208.0 | weggelaten |
| cofid:11-725 | Noodles, rice, fine, dried, boiled in unsalted water | pasta | tryptophan | 0.048 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| cofid:12-551 | Cheese, spreadable, full fat, soft, white | dairy | tryptophan | 0.162 | 3.1 % van het eiwit | max 2.5 % | weggelaten |
| cofid:13-341 | Seaweed, wakame, dried, raw | vegetable | b12 | 2.5 | 0.1104 (soort: wakame) | 78.9 | behouden: zeewier (wakame) bevat B12 en B12-analogen; gemeten waarden lopen sterk uiteen (0,3 tot enkele µg per 100 g droog) |
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
| cofid:16-270 | Winkles, boiled | shellfish | b2 | 0.38 | 0.04694 (soort: winkle) | 4.2 | behouden: alikruiken: 0,2-0,4 mg B2 is gewoon voor weekdieren; de enige andere meting (CIQUAL) is laag |
| cofid:17-514 | Beef extract | sauce/condiment | b1 | 9.7 | 1.38 (groep) | 3.187 | weggelaten |
| cofid:17-721 | Soy sauce, light and dark varieties | sauce/condiment | tryptophan | 0.084 | 2.8 % van het eiwit | max 2.5 % | weggelaten |
| cofid:17-798 | Halva, carrot, homemade | dessert | beta_carotene | 13430.0 | 639.0 (groep) | 14130.0 | weggelaten |
| cofid:17-808 | Soup, lentil, homemade | soup | manganese | 29.0 | 0.76 (groep) | 28.0 | weggelaten |
| cofid:17-825 | Instant drinks powder, malted, unfortified | beverage | tryptophan | 0.156 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | copper | 10.84 | 0.472 (groep) | 9.2 | behouden: gerecht met lever: lever is de rijkste bron van koper |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | retinol | 15750.0 | 320.0 (groep) | 20000.0 | behouden: gerecht met lever: het vitamine A van lever is bijna allemaal retinol |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | vit_a | 15760.0 | 803.4 (groep) | 20120.0 | behouden: gerecht met lever: lever is de rijkste bron van vitamine A |
| frida:1075 | Coffee bean, roasted, ground | beverage | tryptophan | 6.6 | 48.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:1089 | Black salsify, raw | vegetable | tryptophan | 1.08 | 32.7 % van het eiwit | max 2.5 % | weggelaten |
| frida:1193 | Pecans, oil roasted | nut/seed | tryptophan | 0.243 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:1194 | Pecans, dry roasted | nut/seed | tryptophan | 0.2509 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:1454 | Saithe (UK), pollock (US), liver oil | oil/fat | vit_d | 500.0 | 250.0 (groep) | 39.1 | behouden: visleverolie: 100-500 µg vitamine D per 100 g is normaal |
| frida:1573 | Butter cookie, wheat, Danish, industrially produced | bakery | tryptophan | 0.129 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| frida:1829 | Pomegranate seeds, frozen | fruit | tryptophan | 0.0369 | 3.6 % van het eiwit | max 2.5 % | weggelaten |
| frida:372 | Seaweed, agar, dried | vegetable | iodine | 36000.0 | 19100.0 (groep) | 9900.0 | weggelaten |
| frida:515 | Pecans, dried | nut/seed | tryptophan | 0.2422 | 2.6 % van het eiwit | max 2.5 % | behouden: ook 2.7 % in cofid:14-837 |
| frida:533 | Date, dried | fruit | chromium | 80.0 | 2.114 (soort: date) | 173.0 | weggelaten |
| frida:533 | Date, dried | fruit | tryptophan | 0.0544 | 2.7 % van het eiwit | max 2.5 % | behouden: ook 3.8 % in cofid:14-394 |
| frida:537 | Tea, leaves | beverage | tryptophan | 0.8154 | 4.2 % van het eiwit | max 2.5 % | weggelaten |
| frida:566 | Heart, veal, raw | offal | tryptophan | 1.645 | 11.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:641 | Heart, beef, raw | offal | tryptophan | 1.956 | 11.0 % van het eiwit | max 2.5 % | weggelaten |
| frida:698 | Liver, calf, raw | offal | b5 | 54.65 | 8.9 (groep) | 12.6 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | magnesium | 197.0 | 31.58 (soort: goose) | 694.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | phosphorus | 2563.0 | 302.8 (soort: goose) | 1349.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | potassium | 3653.0 | 510.6 (soort: goose) | 4350.0 | weggelaten |
| mvt:03.245 | Goose, without skin, roasted | poultry | zinc | 22.6 | 2.649 (soort: goose) | 23.0 | weggelaten |
| mvt:06.850 | Kale, steamed | vegetable | copper | 1.49 | 0.045 (soort: kale) | 9.2 | weggelaten |
| mvt:12.023 | Salt, mineral | other | potassium | 21000.0 | 21000.0 (groep) | 4350.0 | behouden: mineraalzout met kaliumchloride: ongeveer een vijfde kalium |
| slv:1381 | Lumpfish roe salted | fish | b2 | 4.23 | 0.261 (soort: lumpfish) | 4.2 | weggelaten |
| slv:4124 | Lamb liver fried w/ salt | offal | b9 | 2080.0 | 323.4 (soort: lamb) | 2104.0 | weggelaten |
| slv:4131 | Palmoil | oil/fat | beta_carotene | 15430.0 | 903.0 (groep) | 14130.0 | behouden: (rode) palmolie bevat 30-70 mg bètacaroteen per 100 g |
| usda_fnd:2262075 | Flaxseed, ground | nut/seed | selenium | 135.9 | 14.57 (soort: flaxseed) | 208.0 | weggelaten |
| usda_fnd:2346386 | Cream, heavy | dairy | tryptophan | 0.066 | 3.3 % van het eiwit | max 2.5 % | weggelaten |
| usda_fnd:2710819 | Chia seeds, dry, raw | nut/seed | tryptophan | 0.436 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_fndds:2707589 | Mixed seeds | nut/seed | selenium | 61.8 | 9.114 (soort: seeds) | 208.0 | weggelaten |
| usda_fndds:2710635 | Jagerbomb | alcohol | b6 | 1.626 | 0.09 (groep) | 2.58 | weggelaten |
| usda_fndds:2710668 | Vodka and energy drink | alcohol | b6 | 1.63 | 0.09 (groep) | 2.58 | weggelaten |
| usda_sr:167634 | Mutton, cooked, roasted (Navajo) | meat | selenium | 38.0 | 4.47 (soort: mutton) | 208.0 | behouden: schapenvlees heeft elders 20-30 µg selenium (USDA lam); de Noorse en Zweedse metingen zijn laag door seleenarme grond |
| usda_sr:167760 | Sapote, mamey, raw | fruit | tryptophan | 0.049 | 3.4 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:167971 | Candies, TOOTSIE ROLL, chocolate-flavor roll | sugar/sweets | tryptophan | 0.19 | 11.9 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168063 | Restaurant, Latino, arroz con leche (rice pudding) | dessert | tryptophan | 0.084 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168152 | Jujube, Chinese, fresh, dried | fruit | manganese | 31.07 | 0.3242 (soort: jujube) | 28.0 | weggelaten |
| usda_sr:168457 | Seaweed, kelp, raw | vegetable | tryptophan | 0.048 | 2.9 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:168993 | Agave, dried (Southwest) | vegetable | zinc | 12.1 | 0.6843 (soort: agave) | 23.0 | weggelaten |
| usda_sr:169001 | Sea lion, Steller, kidney (Alaska Native) | offal | tryptophan | 1.2 | 6.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:169287 | Spinach, frozen, chopped or leaf, unprepared (Includes foods for USDA's Food Distribution Program) | vegetable | tryptophan | 0.1 | 2.8 % van het eiwit | max 2.5 % | behouden: ook 2.5 % in bls:G210600 |
| usda_sr:169288 | Spinach, frozen, chopped or leaf, cooked, boiled, drained, without salt | vegetable | tryptophan | 0.101 | 2.5 % van het eiwit | max 2.5 % | behouden: ook 2.5 % in bls:G210600 |
| usda_sr:169373 | Peppers, sweet, red, freeze-dried | vegetable | beta_carotene | 42890.0 | 10630.0 (groep) | 14130.0 | weggelaten |
| usda_sr:169373 | Peppers, sweet, red, freeze-dried | vegetable | vit_c | 1900.0 | 170.0 (groep) | 266.0 | behouden: gevriesdroogde rode paprika: het vitamine C van verse paprika, zonder water (~10× geconcentreerd) |
| usda_sr:169824 | Sea lion, Steller, meat with fat (Alaska Native) | meat | tryptophan | 1.6 | 7.2 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170124 | Spinach, frozen, chopped or leaf, cooked, boiled, drained, with salt | vegetable | tryptophan | 0.101 | 2.5 % van het eiwit | max 2.5 % | behouden: ook 2.5 % in bls:G210600 |
| usda_sr:170143 | Mushrooms, portabella, exposed to ultraviolet light, raw | mushroom | tryptophan | 0.056 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170552 | Seeds, breadnut tree seeds, raw | nut/seed | tryptophan | 0.162 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170553 | Seeds, breadnut tree seeds, dried | nut/seed | tryptophan | 0.234 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170554 | Seeds, chia seeds, dried | nut/seed | tryptophan | 0.436 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:170569 | Nuts, brazilnuts, dried, unblanched | nut/seed | selenium | 1917.0 | 254.0 (groep) | 208.0 | behouden: paranoten zijn de rijkste bron van selenium; de USDA-waarde is een bekend gemiddelde |
| usda_sr:171263 | Cream substitute, powdered | other | tryptophan | 0.066 | 2.7 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:171620 | Bratwurst, pork, cooked | processed meat | tryptophan | 0.347 | 2.5 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:173040 | Grapes, muscadine, raw | fruit | b2 | 1.5 | 0.00903 (soort: grape) | 4.2 | weggelaten |
| usda_sr:173237 | Beverages, Orange-flavor drink, breakfast type, low calorie, powder | beverage | b6 | 8.0 | 1.414 (groep) | 2.58 | weggelaten |
| usda_sr:173237 | Beverages, Orange-flavor drink, breakfast type, low calorie, powder | beverage | retinol | 6006.0 | 280.0 (groep) | 20000.0 | weggelaten |
| usda_sr:173237 | Beverages, Orange-flavor drink, breakfast type, low calorie, powder | beverage | vit_c | 2400.0 | 155.6 (groep) | 266.0 | behouden: verrijkt poeder voor een sinaasappeldrank: per 100 g poeder, aangelengd een gewone hoeveelheid |
| usda_sr:174181 | Beverages, nutritional shake mix, high protein, powder | supplement | manganese | 125.0 | 28.0 (groep) | 28.0 | weggelaten |
| usda_sr:174283 | Winged beans, mature seeds, raw | legume | tryptophan | 0.762 | 2.6 % van het eiwit | max 2.5 % | weggelaten |
| usda_sr:174783 | Snacks, sweet potato chips, unsalted | snack | tryptophan | 0.098 | 3.3 % van het eiwit | max 2.5 % | weggelaten |
