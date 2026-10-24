/// Catalogus van alle voedingsstoffen die de app bijhoudt.
///
/// De sleutels komen overeen met tool/build_foods.py (USDA) en lib/data/off_client.dart
/// (Open Food Facts). Alle waarden in de app zijn per 100 g en in de eenheid hieronder.
library;

import '../i18n.dart';

enum NutrientGroup {
  general('General', 'Algemeen'),
  carbs('Carbohydrates', 'Koolhydraten'),
  fats('Fats', 'Vetten'),
  protein('Protein and amino acids', 'Eiwitten en aminozuren'),
  vitamins('Vitamins', 'Vitaminen'),
  minerals('Minerals', 'Mineralen'),
  other('Other compounds', 'Overige stoffen');

  const NutrientGroup(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

class Nutrient {
  const Nutrient(this.key, this.nameNl, this.unit, this.group, {this.indent = 0, this.decimals, this.derived = false});

  final String key;

  /// Nederlandse naam; de Engelse staat in [_englishNames].
  final String nameNl;
  String get name => isNl ? nameNl : (_englishNames[key] ?? nameNl);
  final String unit;
  final NutrientGroup group;

  /// Inspringing in lijsten: 1 = deel van de regel erboven (bv. vezels onder koolhydraten).
  final int indent;

  /// Aantal decimalen bij het tonen; standaard afhankelijk van de eenheid.
  final int? decimals;

  /// Berekend uit andere voedingsstoffen (bv. omega-3 = ALA + EPA + DPA + DHA).
  final bool derived;

  int get displayDecimals =>
      decimals ??
      switch (unit) {
        'kcal' => 0,
        'g' => 1,
        'mg' => 1,
        _ => 0,
      };
}

const nutrients = <Nutrient>[
  // Algemeen
  Nutrient('energy', 'Energie', 'kcal', NutrientGroup.general),
  Nutrient('water', 'Water', 'ml', NutrientGroup.general, decimals: 0),
  Nutrient('alcohol', 'Alcohol', 'g', NutrientGroup.general),
  Nutrient('caffeine', 'Cafeïne', 'mg', NutrientGroup.general, decimals: 0),

  // Koolhydraten
  Nutrient('carbs', 'Koolhydraten', 'g', NutrientGroup.carbs),
  Nutrient('fiber', 'Vezels', 'g', NutrientGroup.carbs, indent: 1),
  Nutrient('sugars', 'Suikers', 'g', NutrientGroup.carbs, indent: 1),
  // Geschat uit het label of de naam (zie free_sugars.dart): suikers buiten heel fruit, groenten en gewone melk
  Nutrient('free_sugars', 'Vrije suikers', 'g', NutrientGroup.carbs, indent: 2, derived: true),
  Nutrient('starch', 'Zetmeel', 'g', NutrientGroup.carbs, indent: 1),

  // Vetten
  Nutrient('fat', 'Vet', 'g', NutrientGroup.fats),
  Nutrient('sfa', 'Verzadigd vet', 'g', NutrientGroup.fats, indent: 1),
  Nutrient('mufa', 'Enkelvoudig onverzadigd', 'g', NutrientGroup.fats, indent: 1),
  Nutrient('pufa', 'Meervoudig onverzadigd', 'g', NutrientGroup.fats, indent: 1),
  Nutrient('omega3', 'Omega-3', 'g', NutrientGroup.fats, indent: 2, decimals: 2, derived: true),
  Nutrient('ala', 'ALA', 'g', NutrientGroup.fats, indent: 3, decimals: 2),
  Nutrient('epa_dha', 'EPA + DHA', 'mg', NutrientGroup.fats, indent: 3, decimals: 0, derived: true),
  Nutrient('epa', 'EPA', 'g', NutrientGroup.fats, indent: 4, decimals: 3),
  Nutrient('dpa', 'DPA', 'g', NutrientGroup.fats, indent: 4, decimals: 3),
  Nutrient('dha', 'DHA', 'g', NutrientGroup.fats, indent: 4, decimals: 3),
  Nutrient('omega6', 'Omega-6', 'g', NutrientGroup.fats, indent: 2, decimals: 2, derived: true),
  Nutrient('la', 'Linolzuur (LA)', 'g', NutrientGroup.fats, indent: 3, decimals: 2),
  Nutrient('aa', 'Arachidonzuur (AA)', 'g', NutrientGroup.fats, indent: 3, decimals: 3),
  Nutrient('trans', 'Transvet', 'g', NutrientGroup.fats, indent: 1, decimals: 2),
  Nutrient('cholesterol', 'Cholesterol', 'mg', NutrientGroup.fats, decimals: 0),

  // Eiwitten en essentiële aminozuren
  Nutrient('protein', 'Eiwit', 'g', NutrientGroup.protein),
  Nutrient('histidine', 'Histidine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('isoleucine', 'Isoleucine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('leucine', 'Leucine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('lysine', 'Lysine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('met_cys', 'Methionine + cysteïne', 'g', NutrientGroup.protein, indent: 1, decimals: 2, derived: true),
  Nutrient('methionine', 'Methionine', 'g', NutrientGroup.protein, indent: 2, decimals: 2),
  Nutrient('cystine', 'Cysteïne', 'g', NutrientGroup.protein, indent: 2, decimals: 2),
  Nutrient('phe_tyr', 'Fenylalanine + tyrosine', 'g', NutrientGroup.protein, indent: 1, decimals: 2, derived: true),
  Nutrient('phenylalanine', 'Fenylalanine', 'g', NutrientGroup.protein, indent: 2, decimals: 2),
  Nutrient('tyrosine', 'Tyrosine', 'g', NutrientGroup.protein, indent: 2, decimals: 2),
  Nutrient('threonine', 'Threonine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('tryptophan', 'Tryptofaan', 'g', NutrientGroup.protein, indent: 1, decimals: 2),
  Nutrient('valine', 'Valine', 'g', NutrientGroup.protein, indent: 1, decimals: 2),

  // Vitaminen
  // Vitamine A in RE (retinol + bètacaroteen / 6), zoals de EFSA-doelen; B3 in niacine-equivalenten (niacine +
  // tryptofaan / 60), zoals het EFSA-doel van 1,6 mg NE/MJ. Zie VIT_A_BC en niacin_ne in tool/build_foods.py.
  Nutrient('vit_a', 'Vitamine A (RE)', 'µg', NutrientGroup.vitamins),
  Nutrient('vit_c', 'Vitamine C', 'mg', NutrientGroup.vitamins),
  Nutrient('vit_d', 'Vitamine D', 'µg', NutrientGroup.vitamins, decimals: 1),
  Nutrient('vit_e', 'Vitamine E', 'mg', NutrientGroup.vitamins),
  Nutrient('vit_k', 'Vitamine K1', 'µg', NutrientGroup.vitamins),
  Nutrient('vit_k2', 'Vitamine K2 (MK-4)', 'µg', NutrientGroup.vitamins, decimals: 1),
  Nutrient('b1', 'B1 (thiamine)', 'mg', NutrientGroup.vitamins, decimals: 2),
  Nutrient('b2', 'B2 (riboflavine)', 'mg', NutrientGroup.vitamins, decimals: 2),
  Nutrient('b3', 'B3 (niacine-equivalenten)', 'mg', NutrientGroup.vitamins),
  Nutrient('b5', 'B5 (pantotheenzuur)', 'mg', NutrientGroup.vitamins, decimals: 2),
  Nutrient('b6', 'B6 (pyridoxine)', 'mg', NutrientGroup.vitamins, decimals: 2),
  Nutrient('b7', 'B7 (biotine)', 'µg', NutrientGroup.vitamins, decimals: 1),
  Nutrient('b9', 'B9 (folaat)', 'µg', NutrientGroup.vitamins),
  Nutrient('b12', 'B12 (cobalamine)', 'µg', NutrientGroup.vitamins, decimals: 2),
  Nutrient('choline', 'Choline', 'mg', NutrientGroup.vitamins, decimals: 0),

  // Mineralen
  Nutrient('calcium', 'Calcium', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('chloride', 'Chloride', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('chromium', 'Chroom', 'µg', NutrientGroup.minerals, decimals: 1),
  Nutrient('copper', 'Koper', 'mg', NutrientGroup.minerals, decimals: 2),
  Nutrient('fluoride', 'Fluoride', 'mg', NutrientGroup.minerals, decimals: 2),
  Nutrient('iodine', 'Jodium', 'µg', NutrientGroup.minerals),
  Nutrient('iron', 'IJzer', 'mg', NutrientGroup.minerals),
  Nutrient('magnesium', 'Magnesium', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('manganese', 'Mangaan', 'mg', NutrientGroup.minerals, decimals: 2),
  Nutrient('molybdenum', 'Molybdeen', 'µg', NutrientGroup.minerals),
  Nutrient('phosphorus', 'Fosfor', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('potassium', 'Kalium', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('selenium', 'Seleen', 'µg', NutrientGroup.minerals),
  Nutrient('sodium', 'Natrium', 'mg', NutrientGroup.minerals, decimals: 0),
  Nutrient('salt', 'Zout', 'g', NutrientGroup.minerals, decimals: 1, derived: true),
  Nutrient('zinc', 'Zink', 'mg', NutrientGroup.minerals),

  // Overige
  Nutrient('beta_carotene', 'Bètacaroteen', 'µg', NutrientGroup.other, decimals: 0),
  Nutrient('lycopene', 'Lycopeen', 'µg', NutrientGroup.other, decimals: 0),
  Nutrient('lutein_zeaxanthin', 'Luteïne + zeaxanthine', 'µg', NutrientGroup.other, decimals: 0),
];

final nutrientByKey = {for (final n in nutrients) n.key: n};

/// De vier hoofdgetallen bovenaan het dagboek.
const macroKeys = ['energy', 'protein', 'carbs', 'fat'];

const _englishNames = {
  'energy': 'Energy',
  'water': 'Water',
  'alcohol': 'Alcohol',
  'caffeine': 'Caffeine',
  'carbs': 'Carbohydrates',
  'fiber': 'Fiber',
  'sugars': 'Sugars',
  'free_sugars': 'Free sugars',
  'starch': 'Starch',
  'fat': 'Fat',
  'sfa': 'Saturated fat',
  'mufa': 'Monounsaturated',
  'pufa': 'Polyunsaturated',
  'omega3': 'Omega-3',
  'ala': 'ALA',
  'epa_dha': 'EPA + DHA',
  'epa': 'EPA',
  'dpa': 'DPA',
  'dha': 'DHA',
  'omega6': 'Omega-6',
  'la': 'Linoleic acid (LA)',
  'aa': 'Arachidonic acid (AA)',
  'trans': 'Trans fat',
  'cholesterol': 'Cholesterol',
  'protein': 'Protein',
  'histidine': 'Histidine',
  'isoleucine': 'Isoleucine',
  'leucine': 'Leucine',
  'lysine': 'Lysine',
  'met_cys': 'Methionine + cysteine',
  'methionine': 'Methionine',
  'cystine': 'Cysteine',
  'phe_tyr': 'Phenylalanine + tyrosine',
  'phenylalanine': 'Phenylalanine',
  'tyrosine': 'Tyrosine',
  'threonine': 'Threonine',
  'tryptophan': 'Tryptophan',
  'valine': 'Valine',
  'vit_a': 'Vitamin A (RE)',
  'vit_c': 'Vitamin C',
  'vit_d': 'Vitamin D',
  'vit_e': 'Vitamin E',
  'vit_k': 'Vitamin K1',
  'vit_k2': 'Vitamin K2 (MK-4)',
  'b1': 'B1 (thiamine)',
  'b2': 'B2 (riboflavin)',
  'b3': 'B3 (niacin equivalents)',
  'b5': 'B5 (pantothenic acid)',
  'b6': 'B6 (pyridoxine)',
  'b7': 'B7 (biotin)',
  'b9': 'B9 (folate)',
  'b12': 'B12 (cobalamin)',
  'choline': 'Choline',
  'calcium': 'Calcium',
  'chloride': 'Chloride',
  'chromium': 'Chromium',
  'copper': 'Copper',
  'fluoride': 'Fluoride',
  'iodine': 'Iodine',
  'iron': 'Iron',
  'magnesium': 'Magnesium',
  'manganese': 'Manganese',
  'molybdenum': 'Molybdenum',
  'phosphorus': 'Phosphorus',
  'potassium': 'Potassium',
  'selenium': 'Selenium',
  'sodium': 'Sodium',
  'salt': 'Salt',
  'zinc': 'Zinc',
  'beta_carotene': 'Beta-carotene',
  'lycopene': 'Lycopene',
  'lutein_zeaxanthin': 'Lutein + zeaxanthin',
};

/// Korte uitleg bij een voedingsstof die niet vanzelf spreekt, of null.
String? nutrientNote(String key) => switch (key) {
  'free_sugars' => tr(
    'Added sugar plus the sugar in honey, syrups and fruit juice. Sugar in whole fruit, vegetables, legumes and plain milk or yoghurt does not count. Estimated from the kind of product. The WHO advises less than 10% of your energy.',
    'Toegevoegde suiker plus de suiker in honing, siropen en vruchtensap. Suiker in heel fruit, groenten, peulvruchten en gewone melk of yoghurt telt niet mee. Geschat uit het soort product. De WHO raadt minder dan 10% van je energie aan.',
  ),
  'sugars' => tr(
    'All sugars together, also those in fruit and milk. For your maximum, look at free sugars.',
    'Alle suikers samen, ook die in fruit en melk. Kijk voor je maximum naar de vrije suikers.',
  ),
  _ => null,
};
