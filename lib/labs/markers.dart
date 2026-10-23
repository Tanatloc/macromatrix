/// Bloedwaarden die met voeding te maken hebben: namen zoals labo's ze schrijven (Nederlands, Frans, Engels),
/// de eenheid waarin de app ze bewaart, omrekeningen, en wat een te lage of te hoge waarde betekent voor je eten.
///
/// Dit is uitleg, geen diagnose: de teksten verwijzen bij afwijkingen altijd naar je arts.
library;

import '../i18n.dart';

enum LabGroup {
  vitamins('Vitamins and iron', 'Vitaminen en ijzer'),
  fats('Fats', 'Vetten'),
  sugar('Blood sugar', 'Bloedsuiker'),
  organs('Liver and kidneys', 'Lever en nieren'),
  minerals('Minerals', 'Mineralen'),
  blood('Blood', 'Bloed'),
  other('Other', 'Overige');

  const LabGroup(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

class LabMarker {
  const LabMarker(
    this.key,
    this.en,
    this.nl,
    this.unit,
    this.group, {
    required this.aliases,
    this.convert = const {},
    this.low,
    this.high,
    this.lowText,
    this.highText,
    this.decimals = 1,
  });

  final String key, en, nl;
  String get name => tr(en, nl);

  /// Eenheid waarin de app de waarde bewaart.
  final String unit;
  final LabGroup group;

  /// Namen zoals ze op een verslag staan, genormaliseerd met [normalizeLabName].
  final List<String> aliases;

  /// Andere eenheid (genormaliseerd met [normalizeUnit]) -> factor naar [unit].
  final Map<String, double> convert;

  /// Grenzen als het labo er geen geeft (in [unit]).
  final double? low, high;

  /// (Engels, Nederlands): wat het betekent en wat je eten kan doen.
  final (String, String)? lowText, highText;
  final int decimals;
}

/// Kleine letters, zonder accenten en leestekens: "Vitamine D 25(OH)" -> "vitamine d 25 oh".
String normalizeLabName(String s) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ü': 'u',
    'û': 'u',
    'ç': 'c',
    'γ': 'g',
  };
  final lower = s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
  return lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// "µg/L", "ug/l", "mcg/L" -> "ug/l".
String normalizeUnit(String s) =>
    s.toLowerCase().replaceAll('µ', 'u').replaceAll('μ', 'u').replaceAll('mcg', 'ug').replaceAll(' ', '').replaceAll('mmol/mol', 'mmol/mol');

const labMarkers = <LabMarker>[
  // ── Vitaminen en ijzer ──
  LabMarker(
    'vit_d',
    'Vitamin D (25-OH)',
    'Vitamine D (25-OH)',
    'ng/mL',
    LabGroup.vitamins,
    aliases: [
      'vit d 25 oh',
      'vitamine d 25 oh',
      'vitamine d',
      'vitamin d',
      '25 oh vitamine d',
      '25 oh vitamin d',
      '25 hydroxyvitamine d',
      '25 hydroxy vitamine d',
      '25 hydroxyvitamin d',
      'vitamine d3',
      'vitamine d 25 hydroxy',
      '25 oh d',
      '25 oh d3',
      'vit d',
    ],
    convert: {'nmol/l': 0.4},
    low: 30,
    high: 100,
    lowText: (
      'Low vitamin D (aim for 30–100 ng/mL, which is 75–250 nmol/L). Food alone rarely fixes this: oily fish helps, but usually a supplement of 10–25 µg (400–1000 IU) a day is needed, especially from October to March. Discuss the dose with your doctor.',
      'Weinig vitamine D (streefwaarde 30–100 ng/mL, dat is 75–250 nmol/L). Met eten alleen lukt dat zelden: vette vis helpt, maar meestal is een supplement van 10–25 µg (400–1000 IE) per dag nodig, zeker van oktober tot maart. Bespreek de dosis met je arts.',
    ),
    highText: (
      'Very high vitamin D, usually from too many supplements. Check what you take and talk to your doctor.',
      'Zeer veel vitamine D, meestal door te veel supplementen. Kijk na wat je neemt en spreek met je arts.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'ferritin',
    'Ferritin',
    'Ferritine',
    'µg/L',
    LabGroup.vitamins,
    aliases: ['ferritine', 'ferritin', 'serum ferritine'],
    convert: {'ng/ml': 1},
    low: 30,
    lowText: (
      'Your iron stores are low. Eat iron-rich foods (red meat, legumes, wholegrains, dark green vegetables) together with vitamin C (fruit, peppers), and drink tea or coffee between meals rather than with them.',
      'Je ijzervoorraad is laag. Eet ijzerrijk (rood vlees, peulvruchten, volkoren, donkergroene groenten) samen met vitamine C (fruit, paprika), en drink thee of koffie tussen de maaltijden in plaats van erbij.',
    ),
    highText: (
      'High ferritin can come from inflammation, alcohol, a fatty liver or too much iron. Avoid iron supplements and talk to your doctor.',
      'Hoge ferritine kan komen door een ontsteking, alcohol, een vette lever of te veel ijzer. Neem geen ijzersupplementen en spreek met je arts.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'iron',
    'Iron',
    'IJzer',
    'µg/dL',
    LabGroup.vitamins,
    aliases: ['ijzer', 'iron', 'fer', 'fer serique', 'serum ijzer', 'ijzer serum', 'sideremie'],
    convert: {'umol/l': 5.585},
    decimals: 0,
  ),
  LabMarker(
    'transferrin_sat',
    'Transferrin saturation',
    'Transferrineverzadiging',
    '%',
    LabGroup.vitamins,
    aliases: [
      'transferrine saturatie',
      'transferrineverzadiging',
      'saturatie transferrine',
      'transferrin saturation',
      'saturation de la transferrine',
      'coefficient de saturation',
    ],
    low: 20,
    lowText: (
      'Little iron available in your blood. See the advice for ferritin.',
      'Weinig ijzer beschikbaar in je bloed. Zie het advies bij ferritine.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'b12',
    'Vitamin B12',
    'Vitamine B12',
    'ng/L',
    LabGroup.vitamins,
    aliases: ['vitamine b12', 'vitamin b12', 'b12', 'cobalamine', 'cobalamin', 'vit b12'],
    convert: {'pg/ml': 1, 'pmol/l': 1.355},
    low: 200,
    lowText: (
      'Low vitamin B12. It is only in animal foods (fish, meat, eggs, dairy) and fortified products. Eating plant-based or over 50? Then a supplement is often needed.',
      'Weinig vitamine B12. Die zit alleen in dierlijke producten (vis, vlees, eieren, zuivel) en verrijkte producten. Eet je plantaardig of ben je ouder dan 50? Dan is een supplement vaak nodig.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'folate',
    'Folate',
    'Foliumzuur',
    'µg/L',
    LabGroup.vitamins,
    aliases: ['foliumzuur', 'foliumzuur serum', 'folaat', 'folate', 'folic acid', 'acide folique', 'folates', 'folaten'],
    convert: {'ng/ml': 1, 'nmol/l': 0.441},
    low: 3.9,
    lowText: (
      'Low folate. Eat more green leafy vegetables, legumes, oranges and wholegrains. Trying for a baby? Then 400 µg folic acid a day is advised.',
      'Weinig foliumzuur. Eet meer groene bladgroenten, peulvruchten, sinaasappels en volkoren. Wil je zwanger worden? Dan is 400 µg foliumzuur per dag aangeraden.',
    ),
  ),
  // ── Vetten ──
  LabMarker(
    'ldl',
    'LDL cholesterol',
    'LDL-cholesterol',
    'mg/dL',
    LabGroup.fats,
    aliases: ['ldl cholesterol', 'ldl', 'ldl c', 'cholesterol ldl', 'ldl cholesterol berekend', 'ldl berekend', 'cholesterol ldl calcule'],
    convert: {'mmol/l': 38.67},
    high: 115,
    highText: (
      'High LDL cholesterol raises the risk of heart and vascular disease. Food helps most by: less saturated fat (butter, fatty meat, cheese, pastries), more fibre (oats, legumes) and more unsaturated fats (olive oil, nuts, fish).',
      'Hoge LDL-cholesterol verhoogt je kans op hart- en vaatziekten. Eten helpt het meest met: minder verzadigd vet (boter, vet vlees, kaas, koeken), meer vezels (havermout, peulvruchten) en meer onverzadigd vet (olijfolie, noten, vis).',
    ),
    decimals: 0,
  ),
  LabMarker(
    'hdl',
    'HDL cholesterol',
    'HDL-cholesterol',
    'mg/dL',
    LabGroup.fats,
    aliases: ['hdl cholesterol', 'hdl', 'hdl c', 'cholesterol hdl'],
    convert: {'mmol/l': 38.67},
    low: 40,
    lowText: (
      'Low HDL ("good") cholesterol. What raises it most: exercise, losing excess weight, not smoking, fewer sugars and refined starches, and unsaturated fats (olive oil, nuts, oily fish) instead of saturated fat.',
      'Lage HDL-cholesterol (de "goede"). Wat het meest helpt: bewegen, overgewicht verliezen, niet roken, minder suiker en witte bloem, en onverzadigd vet (olijfolie, noten, vette vis) in plaats van verzadigd vet.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'cholesterol',
    'Total cholesterol',
    'Totale cholesterol',
    'mg/dL',
    LabGroup.fats,
    aliases: [
      'cholesterol totaal',
      'totaal cholesterol',
      'totale cholesterol',
      'cholesterol',
      'total cholesterol',
      'cholesterol total',
      'cholesterol totale',
    ],
    convert: {'mmol/l': 38.67},
    high: 190,
    decimals: 0,
  ),
  LabMarker(
    'non_hdl',
    'Non-HDL cholesterol',
    'Non-HDL-cholesterol',
    'mg/dL',
    LabGroup.fats,
    aliases: ['non hdl cholesterol', 'non hdl', 'niet hdl cholesterol', 'cholesterol non hdl'],
    convert: {'mmol/l': 38.67},
    high: 130,
    highText: (
      'High non-HDL cholesterol. The same food advice as for LDL helps: less saturated fat, more fibre and unsaturated fats.',
      'Hoge non-HDL-cholesterol. Hetzelfde voedingsadvies als bij LDL helpt: minder verzadigd vet, meer vezels en onverzadigd vet.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'triglycerides',
    'Triglycerides',
    'Triglyceriden',
    'mg/dL',
    LabGroup.fats,
    aliases: ['triglyceriden', 'triglyceriden nuchter', 'triglycerides', 'triglycerides a jeun', 'tg'],
    convert: {'mmol/l': 88.57},
    high: 150,
    highText: (
      'High triglycerides. They drop fastest with less sugar, soft drinks, juice, white bread and alcohol, more exercise and oily fish.',
      'Hoge triglyceriden. Die dalen het snelst met minder suiker, frisdrank, sap, wit brood en alcohol, meer bewegen en vette vis.',
    ),
    decimals: 0,
  ),
  // ── Bloedsuiker ──
  LabMarker(
    'glucose',
    'Fasting glucose',
    'Nuchtere glucose',
    'mg/dL',
    LabGroup.sugar,
    aliases: [
      'glucose nuchter',
      'nuchtere glucose',
      'glucose',
      'glycemie',
      'glycemie a jeun',
      'glucose a jeun',
      'fasting glucose',
      'nuchter glucose',
    ],
    convert: {'mmol/l': 18.016},
    high: 100,
    highText: (
      'Raised fasting blood sugar. Fewer sugars and refined starches, more fibre and wholegrains, exercise and losing excess weight help. Talk to your doctor about follow-up.',
      'Verhoogde nuchtere bloedsuiker. Minder suiker en witte bloem, meer vezels en volkoren, bewegen en overgewicht verliezen helpen. Spreek met je arts over opvolging.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'hba1c',
    'HbA1c',
    'HbA1c',
    '%',
    LabGroup.sugar,
    aliases: ['hb a1c', 'hba1c', 'hemoglobine a1c', 'geglyceerd hemoglobine', 'hemoglobine glyquee', 'hba1c ngsp', 'hb a1c ngsp'],
    high: 5.7,
    highText: (
      'Your average blood sugar of the past months is raised. Fewer sugars and refined starches, more fibre, exercise and losing excess weight bring it down. Talk to your doctor.',
      'Je gemiddelde bloedsuiker van de voorbije maanden is verhoogd. Minder suiker en witte bloem, meer vezels, bewegen en overgewicht verliezen brengen dat omlaag. Spreek met je arts.',
    ),
  ),
  LabMarker(
    'hba1c_ifcc',
    'HbA1c (IFCC)',
    'HbA1c (IFCC)',
    'mmol/mol',
    LabGroup.sugar,
    aliases: ['hb a1c ifcc', 'hba1c ifcc', 'hemoglobine a1c ifcc'],
    high: 39,
    decimals: 0,
  ),
  // ── Lever en nieren ──
  LabMarker(
    'alt',
    'ALT (liver)',
    'ALT (lever)',
    'U/L',
    LabGroup.organs,
    aliases: ['sgpt', 'alt', 'alat', 'gpt', 'alt sgpt', 'sgpt alt', 'alanine aminotransferase', 'alanine aminotransferase alt', 'transaminase alt'],
    high: 41,
    highText: (
      'A raised liver value. Often from a fatty liver (excess weight, sugar, alcohol) or hard training the days before. Less alcohol and sugar and losing excess weight help; ask your doctor whether to retest.',
      'Een verhoogde leverwaarde. Vaak door een vette lever (overgewicht, suiker, alcohol) of zwaar sporten de dagen ervoor. Minder alcohol en suiker en overgewicht verliezen helpen; vraag je arts of je opnieuw moet laten meten.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'ggt',
    'Gamma-GT (liver)',
    'Gamma-GT (lever)',
    'U/L',
    LabGroup.organs,
    aliases: ['y gt', 'gamma gt', 'ggt', 'g gt', 'gamma glutamyltransferase', 'gamma glutamyl transferase', 'gammagt', 'ygt'],
    high: 60,
    highText: (
      'Raised gamma-GT, often from alcohol. Drinking less is the first step; talk to your doctor.',
      'Verhoogde gamma-GT, vaak door alcohol. Minder drinken is de eerste stap; spreek met je arts.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'uric_acid',
    'Uric acid',
    'Urinezuur',
    'mg/dL',
    LabGroup.organs,
    aliases: ['urinezuur', 'uric acid', 'acide urique', 'urate'],
    convert: {'umol/l': 0.0168, 'mmol/l': 16.8},
    high: 7.2,
    highText: (
      'High uric acid can cause gout. Less alcohol (beer especially), sugary drinks, organ meat and shellfish help; drink plenty of water.',
      'Hoog urinezuur kan jicht geven. Minder alcohol (vooral bier), suikerhoudende dranken, orgaanvlees en schaaldieren helpen; drink voldoende water.',
    ),
  ),
  LabMarker(
    'egfr',
    'Kidney function (eGFR)',
    'Nierfunctie (eGFR)',
    'mL/min/1,73 m²',
    LabGroup.organs,
    aliases: ['egfr ckd epi', 'egfr', 'gfr', 'egfr ckd epi 2021', 'dfg', 'egfr mdrd', 'geschatte gfr'],
    low: 60,
    lowText: (
      'Your kidney function is reduced. Do not eat extra protein or take protein shakes without talking to your doctor, and keep salt low.',
      'Je nierfunctie is verminderd. Eet geen extra eiwit en neem geen eiwitshakes zonder overleg met je arts, en houd zout laag.',
    ),
    decimals: 0,
  ),
  LabMarker(
    'creatinine',
    'Creatinine',
    'Creatinine',
    'mg/dL',
    LabGroup.organs,
    aliases: ['creatinine', 'creatinine serum', 'kreatinine'],
    convert: {'umol/l': 0.0113},
    decimals: 2,
  ),
  // ── Mineralen ──
  LabMarker('sodium', 'Sodium', 'Natrium', 'mmol/L', LabGroup.minerals, aliases: ['natrium', 'sodium', 'na'], decimals: 0),
  LabMarker('potassium', 'Potassium', 'Kalium', 'mmol/L', LabGroup.minerals, aliases: ['kalium', 'potassium', 'k']),
  LabMarker(
    'calcium',
    'Calcium',
    'Calcium',
    'mmol/L',
    LabGroup.minerals,
    aliases: ['calcium', 'calcium totaal', 'ca'],
    convert: {'mg/dl': 0.2495},
    decimals: 2,
  ),
  LabMarker(
    'magnesium',
    'Magnesium',
    'Magnesium',
    'mmol/L',
    LabGroup.minerals,
    aliases: ['magnesium', 'mg', 'magnesium serum'],
    convert: {'mg/dl': 0.4114},
    low: 0.7,
    lowText: (
      'Low magnesium. Eat more nuts, seeds, wholegrains, legumes and green vegetables.',
      'Weinig magnesium. Eet meer noten, zaden, volkoren, peulvruchten en groene groenten.',
    ),
    decimals: 2,
  ),
  LabMarker(
    'phosphorus',
    'Phosphate',
    'Fosfor',
    'mmol/L',
    LabGroup.minerals,
    aliases: ['fosfor', 'fosfaat', 'phosphore', 'phosphate', 'phosphorus', 'anorganisch fosfaat'],
    convert: {'mg/dl': 0.3229},
    decimals: 2,
  ),
  LabMarker('zinc', 'Zinc', 'Zink', 'µg/dL', LabGroup.minerals, aliases: ['zink', 'zinc'], convert: {'umol/l': 6.54}, decimals: 0),
  LabMarker('selenium', 'Selenium', 'Seleen', 'µg/L', LabGroup.minerals, aliases: ['seleen', 'selenium'], decimals: 0),
  // ── Bloed ──
  LabMarker(
    'hemoglobin',
    'Haemoglobin',
    'Hemoglobine',
    'g/dL',
    LabGroup.blood,
    aliases: ['hemoglobine', 'haemoglobine', 'hemoglobin', 'haemoglobin', 'hb'],
    convert: {'g/l': 0.1, 'mmol/l': 1.611},
    lowText: (
      'Low haemoglobin (anaemia). Often from too little iron, B12 or folate: look at those values and talk to your doctor.',
      'Lage hemoglobine (bloedarmoede). Vaak door te weinig ijzer, B12 of foliumzuur: kijk naar die waarden en spreek met je arts.',
    ),
  ),
  LabMarker('mcv', 'MCV (red cell size)', 'MCV (grootte rode bloedcellen)', 'fL', LabGroup.blood, aliases: ['mcv', 'vgm'], decimals: 0),
  // ── Overige ──
  LabMarker(
    'tsh',
    'TSH (thyroid)',
    'TSH (schildklier)',
    'mU/L',
    LabGroup.other,
    aliases: ['tsh', 'thyreotropine', 'tsh ultrasensitief'],
    convert: {'uiu/ml': 1, 'miu/l': 1},
    decimals: 2,
  ),
  LabMarker(
    'crp',
    'CRP (inflammation)',
    'CRP (ontsteking)',
    'mg/L',
    LabGroup.other,
    aliases: ['crp', 'c reactief proteine', 'c reactive protein', 'proteine c reactive'],
    decimals: 1,
  ),
  LabMarker('albumin', 'Albumin', 'Albumine', 'g/L', LabGroup.other, aliases: ['albumine', 'albumin'], decimals: 0),
  LabMarker(
    'total_protein',
    'Total protein',
    'Totaal eiwit',
    'g/L',
    LabGroup.other,
    aliases: ['eiwit totaal', 'totaal eiwit', 'proteines totales', 'total protein'],
    decimals: 0,
  ),
  LabMarker(
    'homocysteine',
    'Homocysteine',
    'Homocysteïne',
    'µmol/L',
    LabGroup.other,
    aliases: ['homocysteine', 'homocysteine plasma'],
    high: 15,
    decimals: 1,
  ),
];

final labMarkerByKey = {for (final m in labMarkers) m.key: m};
final _byAlias = {
  for (final m in labMarkers)
    for (final a in m.aliases) a: m,
};

/// De stof bij een naam op een verslag, of null als de app ze niet kent.
LabMarker? labMarkerFor(String name) => _byAlias[normalizeLabName(name)];

/// Waarde omrekenen naar de eenheid van de app, of null als de eenheid onbekend is.
/// Zonder eenheid (of dezelfde) blijft de waarde zoals ze is.
double? toMarkerUnit(LabMarker m, double value, String? unit) {
  if (unit == null || unit.trim().isEmpty) return value;
  final u = normalizeUnit(unit), own = normalizeUnit(m.unit);
  // Eenheden die hetzelfde zijn: "U/L" = "IU/L" = "UI/L", en eGFR in mL/min (met of zonder "/1,73 m²")
  const sameAsU = {'u/l', 'iu/l', 'ui/l'};
  if (u == own || (sameAsU.contains(u) && sameAsU.contains(own)) || (own.startsWith('ml/min') && u.startsWith('ml/min'))) return value;
  final f = m.convert[u];
  return f == null ? null : value * f;
}
