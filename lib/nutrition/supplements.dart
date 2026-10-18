/// Supplementen: een ingebouwde lijst met veelgebruikte producten (hoeveelheden per dosis, zoals ze in Europa
/// gangbaar zijn) en je eigen dagelijkse supplementen.
///
/// Een ingenomen supplement is een gewone dagboekregel met vaste id `supp:<id>:<dag>` en verwijzing `supp:<id>`.
/// De waarden staan "per 100 g" met 100 g als hoeveelheid, zodat één regel precies één dosis is.
library;

import '../i18n.dart';
import 'nutrients.dart';

class Supplement {
  const Supplement({required this.id, required this.name, required this.dose, required this.nutrients, this.auto = false, this.since});

  final String id;
  final String name;

  /// Dosis zoals op het etiket, bv. "1 capsule" of "1 tablet".
  final String dose;

  /// Hoeveelheden per dosis, in de eenheid van de voedingsstof.
  final Map<String, double> nutrients;

  /// Elke dag vanzelf aangevinkt (je vinkt af als je het eens niet nam).
  final bool auto;

  /// Dag waarop je het toevoegde: automatisch aanvinken gebeurt niet voor dagen daarvoor.
  final String? since;

  String get ref => 'supp:$id';
  String entryId(String day) => 'supp:$id:$day';

  /// Korte samenvatting, bv. "Vitamine D 25 µg · Vitamine K1 75 µg".
  String get summary => [
    for (final e in nutrients.entries)
      if (e.key != 'energy' && nutrientByKey[e.key] != null) '${_short(nutrientByKey[e.key]!.name)} ${_fmt(e.value)} ${nutrientByKey[e.key]!.unit}',
  ].join(' · ');

  static String _short(String name) => name.replaceAll(RegExp(r'\s*\(.*\)'), '');
  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toString().dec;

  Supplement copyWith({bool? auto, String? since}) =>
      Supplement(id: id, name: name, dose: dose, nutrients: nutrients, auto: auto ?? this.auto, since: since ?? this.since);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'dose': dose, 'nutrients': nutrients, 'auto': auto, 'since': since};

  factory Supplement.fromJson(Map<String, Object?> j) => Supplement(
    id: j['id'] as String,
    name: j['name'] as String,
    dose: (j['dose'] as String?) ?? '1 dosis',
    nutrients: {for (final e in (j['nutrients'] as Map).entries) e.key as String: (e.value as num).toDouble()},
    auto: j['auto'] == true,
    since: j['since'] as String?,
  );
}

/// Veelgebruikte supplementen. Hoeveelheden zijn typische Europese doseringen; kies "Eigen supplement" als je
/// etiket anders is.
const supplementCatalog = [
  Supplement(id: 'vitd10', name: 'Vitamine D3 10 µg (400 IE)', dose: '1 tablet', nutrients: {'energy': 0, 'vit_d': 10}),
  Supplement(id: 'vitd25', name: 'Vitamine D3 25 µg (1000 IE)', dose: '1 tablet', nutrients: {'energy': 0, 'vit_d': 25}),
  Supplement(id: 'vitd75', name: 'Vitamine D3 75 µg (3000 IE)', dose: '1 tablet', nutrients: {'energy': 0, 'vit_d': 75}),
  Supplement(id: 'vitdk2', name: 'Vitamine D3 + K2', dose: '1 tablet', nutrients: {'energy': 0, 'vit_d': 25, 'vit_k2': 75}),
  Supplement(id: 'b12_100', name: 'Vitamine B12 100 µg', dose: '1 tablet', nutrients: {'energy': 0, 'b12': 100}),
  Supplement(id: 'b12_1000', name: 'Vitamine B12 1000 µg', dose: '1 tablet', nutrients: {'energy': 0, 'b12': 1000}),
  Supplement(
    id: 'bcomplex',
    name: 'Vitamine B-complex',
    dose: '1 tablet',
    nutrients: {'energy': 0, 'b1': 1.1, 'b2': 1.4, 'b3': 16, 'b5': 6, 'b6': 1.4, 'b7': 50, 'b9': 200, 'b12': 2.5},
  ),
  Supplement(id: 'vitc500', name: 'Vitamine C 500 mg', dose: '1 tablet', nutrients: {'energy': 0, 'vit_c': 500}),
  Supplement(id: 'vitc1000', name: 'Vitamine C 1000 mg', dose: '1 tablet', nutrients: {'energy': 0, 'vit_c': 1000}),
  Supplement(id: 'folic', name: 'Foliumzuur 400 µg', dose: '1 tablet', nutrients: {'energy': 0, 'b9': 400}),
  Supplement(id: 'mg200', name: 'Magnesium 200 mg (citraat of bisglycinaat)', dose: '1 tablet', nutrients: {'energy': 0, 'magnesium': 200}),
  Supplement(id: 'mg300', name: 'Magnesium 300 mg', dose: '1 tablet', nutrients: {'energy': 0, 'magnesium': 300}),
  Supplement(id: 'zn15', name: 'Zink 15 mg', dose: '1 tablet', nutrients: {'energy': 0, 'zinc': 15}),
  Supplement(id: 'zn25', name: 'Zink 25 mg', dose: '1 tablet', nutrients: {'energy': 0, 'zinc': 25}),
  Supplement(id: 'fe14', name: 'IJzer 14 mg', dose: '1 tablet', nutrients: {'energy': 0, 'iron': 14}),
  Supplement(id: 'fe28', name: 'IJzer 28 mg', dose: '1 tablet', nutrients: {'energy': 0, 'iron': 28}),
  Supplement(id: 'ca500', name: 'Calcium 500 mg', dose: '1 tablet', nutrients: {'energy': 0, 'calcium': 500}),
  Supplement(id: 'cad', name: 'Calcium 500 mg + vitamine D 10 µg', dose: '1 tablet', nutrients: {'energy': 0, 'calcium': 500, 'vit_d': 10}),
  Supplement(id: 'iodine', name: 'Jodium 150 µg', dose: '1 tablet', nutrients: {'energy': 0, 'iodine': 150}),
  Supplement(id: 'se55', name: 'Seleen 55 µg', dose: '1 tablet', nutrients: {'energy': 0, 'selenium': 55}),
  Supplement(id: 'k2', name: 'Vitamine K2 (MK-7) 75 µg', dose: '1 capsule', nutrients: {'energy': 0, 'vit_k2': 75}),
  Supplement(
    id: 'fishoil',
    name: 'Visolie omega-3',
    dose: '1 capsule (1000 mg)',
    nutrients: {'energy': 9, 'fat': 1, 'epa': 0.18, 'dha': 0.12, 'omega3': 0.3},
  ),
  Supplement(
    id: 'fishoil_hi',
    name: 'Visolie omega-3 extra sterk',
    dose: '1 capsule',
    nutrients: {'energy': 9, 'fat': 1, 'epa': 0.4, 'dha': 0.2, 'omega3': 0.6},
  ),
  Supplement(
    id: 'algae',
    name: 'Algenolie omega-3 (vegan)',
    dose: '1 capsule',
    nutrients: {'energy': 5, 'fat': 0.5, 'epa': 0.1, 'dha': 0.2, 'omega3': 0.3},
  ),
  Supplement(
    id: 'multi',
    name: 'Multivitamine (100% van de referentie-inname)',
    dose: '1 tablet',
    nutrients: {
      'energy': 0,
      'vit_a': 800,
      'vit_c': 80,
      'vit_d': 5,
      'vit_e': 12,
      'vit_k': 75,
      'b1': 1.1,
      'b2': 1.4,
      'b3': 16,
      'b5': 6,
      'b6': 1.4,
      'b7': 50,
      'b9': 200,
      'b12': 2.5,
      'iron': 14,
      'zinc': 10,
      'iodine': 150,
      'selenium': 55,
      'copper': 1,
      'manganese': 2,
      'chromium': 40,
      'molybdenum': 50,
    },
  ),
  Supplement(id: 'potassium', name: 'Kalium 99 mg', dose: '1 capsule', nutrients: {'energy': 0, 'potassium': 99}),
  Supplement(id: 'choline', name: 'Choline 250 mg', dose: '1 capsule', nutrients: {'energy': 0, 'choline': 250}),
  Supplement(
    id: 'whey',
    name: 'Wei-eiwit (whey) 30 g',
    dose: '1 schep (30 g)',
    nutrients: {'energy': 120, 'protein': 24, 'carbs': 2, 'fat': 1.5, 'calcium': 120},
  ),
  Supplement(id: 'creatine', name: 'Creatine 5 g', dose: '1 schep (5 g)', nutrients: {'energy': 0}),
];

/// De ingebouwde lijst in de taal van de app.
List<Supplement> get localizedCatalog => isNl
    ? supplementCatalog
    : [
        for (final s in supplementCatalog)
          Supplement(id: s.id, name: _catalogEnglish[s.id] ?? s.name, dose: s.dose.replaceAll('schep', 'scoop'), nutrients: s.nutrients),
      ];

const _catalogEnglish = {
  'vitd10': 'Vitamin D3 10 µg (400 IU)',
  'vitd25': 'Vitamin D3 25 µg (1000 IU)',
  'vitd75': 'Vitamin D3 75 µg (3000 IU)',
  'vitdk2': 'Vitamin D3 + K2',
  'b12_100': 'Vitamin B12 100 µg',
  'b12_1000': 'Vitamin B12 1000 µg',
  'bcomplex': 'Vitamin B complex',
  'vitc500': 'Vitamin C 500 mg',
  'vitc1000': 'Vitamin C 1000 mg',
  'folic': 'Folic acid 400 µg',
  'mg200': 'Magnesium 200 mg (citrate or bisglycinate)',
  'mg300': 'Magnesium 300 mg',
  'zn15': 'Zinc 15 mg',
  'zn25': 'Zinc 25 mg',
  'fe14': 'Iron 14 mg',
  'fe28': 'Iron 28 mg',
  'ca500': 'Calcium 500 mg',
  'cad': 'Calcium 500 mg + vitamin D 10 µg',
  'iodine': 'Iodine 150 µg',
  'se55': 'Selenium 55 µg',
  'k2': 'Vitamin K2 (MK-7) 75 µg',
  'fishoil': 'Fish oil omega-3',
  'fishoil_hi': 'Fish oil omega-3 extra strong',
  'algae': 'Algae oil omega-3 (vegan)',
  'multi': 'Multivitamin (100% of reference intake)',
  'potassium': 'Potassium 99 mg',
  'choline': 'Choline 250 mg',
  'whey': 'Whey protein 30 g',
  'creatine': 'Creatine 5 g',
};
