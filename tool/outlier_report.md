# Onwaarschijnlijke metingen

Geschreven door `tool/build_foods.py` (zie `outlier_pass`). Per 100 g; groepsref. = 99e percentiel van de voedingsgroep, alle = 99,9e percentiel van alle producten. Weggelaten waarden worden daarna geschat zoals elke ontbrekende waarde. Behouden staat met de reden in `tool/outlier_keep.json`.

| product | naam | groep | stof | waarde | groepsref. | alle | wat |
|---|---|---|---|---|---|---|---|
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | beta_carotene | 155000.0 | 592.0 | 15430.0 | behouden: spirulina is een van de rijkste bronnen van bètacaroteen (in de literatuur 80-200 mg per 100 g droog) |
| ciqual:11086 | Spirulina (spirulina sp.), dried or dehydrated | other | vit_a | 25830.0 | 98.67 | 20080.0 | behouden: volgt uit het bètacaroteen van spirulina |
| ciqual:18354 | Energy drink, with sugar(s) and with sweetener(s) | beverage | b5 | 135.0 | 4.53 | 15.38 | weggelaten |
| ciqual:20984 | Wakame (Undaria pinnatifida), dried or dehydrated | vegetable | beta_carotene | 104000.0 | 11320.0 | 15430.0 | weggelaten |
| ciqual:20985 | Sea lettuce (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2660.0 | 480.0 | 721.0 | behouden: zeesla (Ulva) gedroogd: 2-3 g magnesium per 100 g is gewoon voor dit zeewier |
| ciqual:20993 | Gracilaria seaweeds (Gracilaria sp.), dried or dehydrated | vegetable | iodine | 356000.0 | 42000.0 | 36000.0 | behouden: gedroogd zeewier: jodium varieert sterk per soort en oogst; zeer hoog is hier geen eenheidsfout |
| ciqual:20995 | Gut weed (Ulva sp.), dried or dehydrated | vegetable | magnesium | 2260.0 | 480.0 | 721.0 | behouden: darmwier (Ulva) gedroogd: zelfde soort als zeesla, hoog magnesium |
| cofid:13-340 | Seaweed, nori, dried, raw | vegetable | b12 | 27.5 | 0.3 | 84.6 | behouden: nori bevat B12 (in de literatuur 30-70 µg per 100 g gedroogd) |
| cofid:17-808 | Soup, lentil, homemade | soup | manganese | 29.0 | 0.8 | 30.37 | weggelaten |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | copper | 10.84 | 0.5 | 9.83 | behouden: gerecht met lever: lever is de rijkste bron van koper |
| cofid:19-603 | Liver and bacon, fried, homemade | dish | vit_a | 15760.0 | 780.2 | 20080.0 | behouden: gerecht met lever: lever is de rijkste bron van vitamine A |
| cofid:19-604 | Liver and onions, stewed, homemade | dish | vit_a | 11970.0 | 780.2 | 20080.0 | behouden: gerecht met lever: lever is de rijkste bron van vitamine A |
| frida:1454 | Saithe (UK), pollock (US), liver oil | oil/fat | vit_d | 500.0 | 250.0 | 41.2 | behouden: visleverolie: 100-500 µg vitamine D per 100 g is normaal |
| frida:698 | Liver, calf, raw | offal | b5 | 54.65 | 10.3 | 15.38 | weggelaten |
| mvt:12.023 | Salt, mineral | other | potassium | 21000.0 | 20780.0 | 4740.0 | behouden: mineraalzout met kaliumchloride: ongeveer een vijfde kalium |
| slv:4131 | Palmoil | oil/fat | beta_carotene | 15430.0 | 925.0 | 15430.0 | behouden: (rode) palmolie bevat 30-70 mg bètacaroteen per 100 g |
| usda_sr:168152 | Jujube, Chinese, fresh, dried | fruit | manganese | 31.07 | 2.0 | 30.37 | weggelaten |
| usda_sr:169373 | Peppers, sweet, red, freeze-dried | vegetable | vit_c | 1900.0 | 165.0 | 295.0 | behouden: gevriesdroogde rode paprika: het vitamine C van verse paprika, zonder water (~10× geconcentreerd) |
| usda_sr:170569 | Nuts, brazilnuts, dried, unblanched | nut/seed | selenium | 1917.0 | 280.4 | 210.0 | behouden: paranoten zijn de rijkste bron van selenium; de USDA-waarde is een bekend gemiddelde |
| usda_sr:173237 | Beverages, Orange-flavor drink, breakfast type, low calorie, powder | beverage | vit_c | 2400.0 | 189.7 | 295.0 | behouden: verrijkt poeder voor een sinaasappeldrank: per 100 g poeder, aangelengd een gewone hoeveelheid |
| usda_sr:174181 | Beverages, nutritional shake mix, high protein, powder | supplement | manganese | 125.0 | 30.37 | 30.37 | weggelaten |
