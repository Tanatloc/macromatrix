/// Bloedwaarden die met voeding te maken hebben: namen zoals labo's ze schrijven (Nederlands, Frans, Engels),
/// de eenheid waarin de app ze bewaart, omrekeningen, en korte algemene uitleg bij een waarde buiten de normaal.
///
/// Dit is uitleg, geen diagnose: geen dosissen en geen mogelijke ziektes of oorzaken (Google Play, gezondheidsapps).
/// Bij een afwijking verwijzen de teksten altijd naar je arts.
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

  /// (Engels, Nederlands): algemene uitleg en waar de stof in eten zit, met een verwijzing naar je arts.
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
      'Your vitamin D is below the reference range. Vitamin D comes mostly from sunlight; in food it is in oily fish, eggs and fortified products. A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
      'Je vitamine D ligt onder de normaalwaarden. Vitamine D komt vooral van zonlicht; in eten zit het in vette vis, eieren en verrijkte producten. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
    ),
    highText: (
      'Your vitamin D is above the reference range. Talk to your doctor about what it means for you, and mention the supplements you take.',
      'Je vitamine D ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent, en vertel welke supplementen je neemt.',
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
      'Ferritin shows how much iron your body has stored, and yours is below the reference range. Iron is in foods such as meat, legumes, wholegrains and dark green vegetables; vitamin C in the same meal helps your body take it up. A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
      'Ferritine toont hoeveel ijzer je lichaam heeft opgeslagen, en de jouwe ligt onder de normaalwaarden. IJzer zit in onder meer vlees, peulvruchten, volkoren en donkergroene groenten; vitamine C in dezelfde maaltijd helpt je lichaam het op te nemen. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
    ),
    highText: (
      'Your ferritin is above the reference range. A high value can have several causes. Talk to your doctor about what it means for you. Mention any supplements with iron that you take.',
      'Je ferritine ligt boven de normaalwaarden. Een hoge waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent. Vertel of je supplementen met ijzer neemt.',
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
      'Your transferrin saturation is below the reference range; see also your ferritin. A low value can have several causes. Talk to your doctor about what it means for you.',
      'Je transferrineverzadiging ligt onder de normaalwaarden; kijk ook naar je ferritine. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent.',
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
      'Your vitamin B12 is below the reference range. B12 is found in animal foods (fish, meat, eggs, dairy) and in fortified products. A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
      'Je vitamine B12 ligt onder de normaalwaarden. B12 zit in dierlijke producten (vis, vlees, eieren, zuivel) en in verrijkte producten. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
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
      'Your folate is below the reference range. Folate is in green leafy vegetables, legumes, oranges and wholegrains. A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
      'Je foliumzuur ligt onder de normaalwaarden. Foliumzuur zit in groene bladgroenten, peulvruchten, sinaasappels en volkoren. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
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
      'Your LDL cholesterol is above the reference range. Talk to your doctor about what it means for you. In general, healthy eating guidelines advise less saturated fat (butter, fatty meat, cheese, pastries), more fibre (oats, legumes) and more unsaturated fats (olive oil, nuts, fish).',
      'Je LDL-cholesterol ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent. Algemene richtlijnen voor gezond eten raden minder verzadigd vet aan (boter, vet vlees, kaas, koeken), meer vezels (havermout, peulvruchten) en meer onverzadigd vet (olijfolie, noten, vis).',
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
      'Your HDL cholesterol is below the reference range. Talk to your doctor about what it means for you. In general, healthy living guidelines advise moving regularly, not smoking and choosing unsaturated fats (olive oil, nuts, oily fish) over saturated fat.',
      'Je HDL-cholesterol ligt onder de normaalwaarden. Bespreek met je arts wat ze voor jou betekent. Algemene richtlijnen voor gezond leven raden aan om regelmatig te bewegen, niet te roken en onverzadigd vet (olijfolie, noten, vette vis) te kiezen boven verzadigd vet.',
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
      'Your non-HDL cholesterol is above the reference range. Talk to your doctor about what it means for you. The general eating guidelines are the same as for LDL: less saturated fat, more fibre and unsaturated fats.',
      'Je non-HDL-cholesterol ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent. De algemene richtlijnen voor eten zijn dezelfde als bij LDL: minder verzadigd vet, meer vezels en onverzadigd vet.',
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
      'Your triglycerides are above the reference range. Talk to your doctor about what it means for you. In general, healthy eating guidelines advise limiting sugar, soft drinks, juice and alcohol, and moving more.',
      'Je triglyceriden liggen boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent. Algemene richtlijnen voor gezond eten raden aan om suiker, frisdrank, sap en alcohol te beperken en meer te bewegen.',
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
      'Your fasting glucose is above the reference range. Talk to your doctor about what it means for you and about follow-up. In general, healthy eating guidelines advise fewer sugars and refined starches and more fibre and wholegrains.',
      'Je nuchtere glucose ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent en of opvolging nodig is. Algemene richtlijnen voor gezond eten raden minder suiker en witte bloem aan, en meer vezels en volkoren.',
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
      'Your HbA1c is above the reference range. Talk to your doctor about what it means for you and about follow-up. In general, healthy eating guidelines advise fewer sugars and refined starches and more fibre.',
      'Je HbA1c ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent en of opvolging nodig is. Algemene richtlijnen voor gezond eten raden minder suiker en witte bloem aan, en meer vezels.',
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
      'This liver value is above the reference range. A high value can have several causes. Talk to your doctor about what it means for you. Ask whether to retest.',
      'Deze leverwaarde ligt boven de normaalwaarden. Een hoge waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent. Vraag of je opnieuw moet laten meten.',
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
      'Your gamma-GT is above the reference range. A high value can have several causes. Talk to your doctor about what it means for you.',
      'Je gamma-GT ligt boven de normaalwaarden. Een hoge waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent.',
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
      'Your uric acid is above the reference range. Talk to your doctor about what it means for you. Uric acid comes partly from purines in food, for example in organ meat, shellfish and beer.',
      'Je urinezuur ligt boven de normaalwaarden. Bespreek met je arts wat ze voor jou betekent. Urinezuur komt deels van purines in eten, bijvoorbeeld in orgaanvlees, schaaldieren en bier.',
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
      'Your kidney function value (eGFR) is below the reference range. Talk to your doctor about what it means for you, also before you eat extra protein or take protein shakes.',
      'Je nierfunctiewaarde (eGFR) ligt onder de normaalwaarden. Bespreek met je arts wat ze voor jou betekent, ook voor je extra eiwit eet of eiwitshakes neemt.',
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
      'Your magnesium is below the reference range. Magnesium is in nuts, seeds, wholegrains, legumes and green vegetables. A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
      'Je magnesium ligt onder de normaalwaarden. Magnesium zit in noten, zaden, volkoren, peulvruchten en groene groenten. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
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
      'Your haemoglobin is below the reference range. A low value can have several causes. Talk to your doctor about what it means for you.',
      'Je hemoglobine ligt onder de normaalwaarden. Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent.',
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
