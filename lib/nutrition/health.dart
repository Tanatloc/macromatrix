/// Gezondheidscheck voor een week: hoe je eetpatroon je gezondheid op termijn beïnvloedt, per factor
/// (vezels, verzadigd vet, zout, ...) met een oordeel goed, oké of slecht, en een eindoordeel.
/// Grenzen volgen EFSA, de WHO en de Hoge Gezondheidsraad. Zonder Flutter, zodat het testbaar is.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../labs/lab_report.dart';
import 'insights.dart';
import 'nutrients.dart';
import 'targets.dart';
import 'values.dart';

enum HealthRating {
  good,
  ok,
  poor,

  /// Te weinig gegevens over deze stof om iets te zeggen.
  unknown;

  String get label => switch (this) {
    good => tr('Good', 'Goed'),
    ok => tr('Okay', 'Oké'),
    poor => tr('Poor', 'Slecht'),
    unknown => tr('Unknown', 'Onbekend'),
  };

  /// Punten voor het eindoordeel.
  double get points => switch (this) {
    good => 2,
    ok => 1,
    _ => 0,
  };
}

class HealthFactor {
  const HealthFactor({
    required this.key,
    required this.title,
    required this.value,
    required this.rating,
    required this.effect,
    this.advice,
    this.note,
    this.tips = const [],
    this.weight = 1,
  });

  final String key, title;

  /// Bv. "23 g per dag".
  final String value;
  final HealthRating rating;

  /// Wat dit doet met je gezondheid.
  final String effect;

  /// Wat je kunt doen, alleen als het beter kan.
  final String? advice;

  /// Kanttekening bij de gegevens.
  final String? note;

  /// Persoonlijk advies (leeftijd, gewicht, training), ook als het oordeel goed is.
  /// Het oordeel zelf volgt altijd de algemene richtlijn.
  final List<String> tips;

  /// Gewicht in het eindoordeel: de grote risicofactoren tellen dubbel.
  final double weight;
}

class HealthCheck {
  const HealthCheck({required this.days, required this.factors, required this.score, required this.rating});

  /// Volledig gelogde dagen waarop het oordeel steunt.
  final int days;
  final List<HealthFactor> factors;

  /// 0–100.
  final int score;
  final HealthRating rating;

  /// Ook beweging beoordeeld (stappen of activiteiten).
  bool get hasActivity => factors.any((f) => activityFactors.contains(f.key));

  String get summary => switch (rating) {
    HealthRating.good => tr(
      'A healthy week. Keep it up: this protects your heart, blood vessels and gut in the long run.',
      'Een gezonde week. Ga zo door: dit beschermt op termijn je hart, je bloedvaten en je darmen.',
    ),
    HealthRating.ok => tr(
      'Okay, but there is room for improvement. Below you can see what is going well and what would make the biggest difference.',
      'Oké, maar het kan beter. Hieronder zie je wat goed gaat en wat het meeste verschil zou maken.',
    ),
    HealthRating.poor => tr(
      'Not a good week. If you carry on like this, it raises your risk of heart and vascular disease and diabetes. Start with the first point below.',
      'Geen goede week. Als je zo verdergaat, verhoogt dat je kans op hart- en vaatziekten en diabetes. Begin met het eerste punt hieronder.',
    ),
    HealthRating.unknown => '',
  };
}

/// Lost op in water: een overschot plas je uit, dus het vult geen andere dag aan. Foliumzuur (B9) en B12 slaat de
/// lever wel op.
const washesOut = {'vit_c', 'b1', 'b2', 'b3', 'b5', 'b6', 'b7', 'choline', 'potassium'};

const activityFactors = {'exercise', 'steps', 'strength'};

/// Beweging in een week, voor wie stappen of activiteiten bijhoudt.
class ActivityWeek {
  const ActivityWeek({this.steps = const [], this.exercises = const [], this.days = 7, this.tracksExercise = false});

  /// Stappen per dag, alleen dagen met gegevens.
  final List<double> steps;
  final List<({String day, double? minutes, double kcal, bool strength})> exercises;

  /// Dagen van de week die al bezig of voorbij zijn (1–7): een lopende week wordt naar 7 dagen omgerekend.
  final int days;

  /// Je houdt activiteiten bij (deze of de vorige weken, of via Health Connect), dus 0 minuten is echt niet bewogen.
  final bool tracksExercise;
}

/// Minstens zoveel volledig gelogde dagen voor een oordeel.
const healthMinDays = 3;

/// Een dag telt als volledig gelogd vanaf de helft van je energiedoel (en minstens 800 kcal).
bool isFullDay(NutrientTotals t, Map<String, Target> targets) => t['energy'] >= math.max(800, (targets['energy']?.goal ?? 0) * 0.5);

/// Gezondheidscheck over [days] (totalen en doelen per dag). [weightKg] voor eiwit per kilo; [age], [heightCm] en
/// [trains] (krachttraining of veel sport) geven persoonlijk advies, net als [labs]: je laatste bloedwaarden per stof
/// (zie lib/labs/markers.dart). Null als er te weinig volledig gelogde dagen zijn.
HealthCheck? healthCheck(
  List<(NutrientTotals, Map<String, Target>)> days, {
  required double weightKg,
  int? age,
  double? heightCm,
  bool trains = false,
  Map<String, LabResult> labs = const {},
  ActivityWeek activity = const ActivityWeek(),
}) {
  final full = [
    for (final d in days)
      if (isFullDay(d.$1, d.$2)) d,
  ];
  if (full.length < healthMinDays) return null;
  final n = full.length;
  final energy = full.fold(0.0, (s, d) => s + d.$1['energy']);
  double avg(String k) => full.fold(0.0, (s, d) => s + d.$1[k]) / n;

  /// Deel van de energie in procent.
  double pctEnergy(String k, double kcalPerGram) => energy <= 0 ? 0 : full.fold(0.0, (s, d) => s + d.$1[k]) * kcalPerGram / energy * 100;

  /// Bekend als hooguit 30% van de energie uit producten zonder gegevens voor deze stof komt.
  bool known(String k) => energy > 0 && full.fold(0.0, (s, d) => s + (d.$1.missingEnergy[k] ?? 0)) / energy <= 0.3;

  HealthRating rateUp(double v, double good, double ok) => v >= good ? HealthRating.good : (v >= ok ? HealthRating.ok : HealthRating.poor);
  HealthRating rateDown(double v, double good, double ok) => v <= good ? HealthRating.good : (v <= ok ? HealthRating.ok : HealthRating.poor);

  HealthFactor factor(
    String key,
    String title,
    String value,
    HealthRating rating, {
    required String good,
    required String ok,
    required String poor,
    required String advice,
    String? note,
    List<String> tips = const [],
    double weight = 1,
    bool isKnown = true,
  }) {
    final r = isKnown ? rating : HealthRating.unknown;
    return HealthFactor(
      key: key,
      title: title,
      value: value,
      rating: r,
      effect: switch (r) {
        HealthRating.good => good,
        HealthRating.ok => ok,
        HealthRating.poor => poor,
        HealthRating.unknown => tr(
          'Too many of the foods you logged have no data for this, so the app cannot judge it.',
          'Van te veel producten die je logde ontbreken gegevens hierover, dus de app kan dit niet beoordelen.',
        ),
      },
      advice: r == HealthRating.ok || r == HealthRating.poor ? advice : null,
      note: note,
      tips: r == HealthRating.unknown ? const [] : tips,
      weight: weight,
    );
  }

  final perDay = tr('per day', 'per dag');
  final ofEnergy = tr('of your energy', 'van je energie');

  final fiber = avg('fiber');
  final sfa = pctEnergy('sfa', 9);
  final sodium = avg('sodium');
  final potassium = avg('potassium');
  final sugars = pctEnergy('sugars', 4);
  final epaDha = avg('epa_dha');
  final protein = weightKg > 0 ? avg('protein') / weightKg : 0.0;
  // Alcohol in standaardglazen van 10 g per week
  final glasses = avg('alcohol') * 7 / 10;
  // Over de hele week: een dag met veel vult een dag met weinig aan, want je lichaam heeft voorraden. Behalve bij
  // wat oplost in water: het overschot plas je uit, dus dat telt per dag maar tot twee keer je doel mee.
  double counted(String k, (NutrientTotals, Map<String, Target>) d) {
    final v = d.$1[k];
    final goal = d.$2[k]?.goal;
    return washesOut.contains(k) && goal != null ? math.min(v, goal * 2) : v;
  }

  final weekValues = {for (final k in stripKeys) k: full.fold(0.0, (s, d) => s + counted(k, d)) / n};
  double? mean(Iterable<double?> xs) {
    final v = xs.whereType<double>();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final weekTargets = {
    for (final k in stripKeys) k: Target(goal: mean(full.map((d) => d.$2[k]?.goal)), upper: mean(full.map((d) => d.$2[k]?.upper))),
  };
  final micro = completenessScore(weekValues, weekTargets).toDouble();
  // Boven een bovengrens (gemiddeld over de week, want die grenzen gelden voor langdurig gebruik)
  final tooMuch = [
    for (final k in stripKeys)
      if (weekTargets[k]!.upper case final u? when weekTargets[k]!.goal != null && avg(k) > u) nutrientByKey[k]!.name,
  ];
  final microTips = [
    if (tooMuch.isNotEmpty)
      tr(
        'On average you get more than the safe upper limit of ${tooMuch.join(', ')}. Too much of this for a long time can harm you: check your supplements.',
        'Je krijgt gemiddeld meer dan de veilige bovengrens van ${tooMuch.join(', ')}. Daar langdurig te veel van kan schaden: kijk je supplementen na.',
      ),
  ];

  // Vezels: 14 g per 1000 kcal (wie veel eet, heeft meer nodig), met de EFSA-waarde als minimum
  final kcalPerDay = energy / n;
  final fiberGoal = math.max(25.0, kcalPerDay * 14 / 1000);
  final fiberTips = [
    if (fiberGoal > 25 && fiber < fiberGoal)
      tr(
        'Because you eat ${fmtNum(kcalPerDay, 0)} kcal a day on average, 14 g per 1000 kcal = ${fmtNum(fiberGoal, 0)} g is a better goal for you.',
        'Omdat je gemiddeld ${fmtNum(kcalPerDay, 0)} kcal per dag eet, is 14 g per 1000 kcal = ${fmtNum(fiberGoal, 0)} g een beter doel voor jou.',
      ),
  ];

  // Eiwit: hogere behoefte vanaf 65 en bij training; bij een BMI boven 30 rekenen met een aangepast gewicht
  final proteinTips = <String>[];
  if (weightKg > 0) {
    final now = fmtNum(protein);
    if (age != null && age >= 65 && protein < 1.0) {
      proteinTips.add(
        tr(
          'From 65, at least 1.0 g per kg is recommended to keep your muscle mass. You are at $now g.',
          'Vanaf 65 jaar raadt men minstens 1,0 g per kg aan om je spiermassa te behouden. Jij zit op $now g.',
        ),
      );
    }
    if (trains && protein < 1.2) {
      proteinTips.add(
        tr(
          'Because you train, 1.2 to 1.6 g per kg helps your muscles recover and grow. You are at $now g.',
          'Omdat je traint, helpt 1,2 à 1,6 g per kg je spieren herstellen en groeien. Jij zit op $now g.',
        ),
      );
    }
    if (heightCm != null && heightCm > 0) {
      final h = heightCm / 100;
      if (weightKg / (h * h) >= 30) {
        // Aangepast gewicht: gewicht bij BMI 25 plus 40% van wat erboven zit
        final reference = 25 * h * h;
        final adjusted = reference + 0.4 * (weightKg - reference);
        proteinTips.add(
          tr(
            'With a BMI above 30, protein is better calculated on an adjusted weight (${fmtNum(adjusted, 0)} kg), as fat tissue needs little protein. Then you are at ${fmtNum(avg('protein') / adjusted)} g per kg.',
            'Bij een BMI boven 30 reken je eiwit beter op een aangepast gewicht (${fmtNum(adjusted, 0)} kg), want vetweefsel heeft weinig eiwit nodig. Dan zit je op ${fmtNum(avg('protein') / adjusted)} g per kg.',
          ),
        );
      }
    }
  }

  // Bloedwaarden: wat afwijkt, met de uitleg bij die stof (alleen als advies; het oordeel blijft de richtlijn)
  String? lab(String key) {
    final r = labs[key];
    if (r == null || r.value.status == 0) return null;
    final v = r.value, m = v.marker!;
    final text = v.status < 0 ? m.lowText : m.highText;
    if (text == null) return null;
    final d = r.day.split('-').reversed.join('/');
    final shown = '${v.comparator ?? ''}${fmtNum(v.value, m.decimals)} ${v.unit ?? m.unit}';
    final word = v.status < 0 ? tr('low', 'laag') : tr('high', 'hoog');
    return '${tr('Blood test', 'Bloedafname')} $d: ${m.name} $shown ($word). ${tr(text.$1, text.$2)}';
  }

  List<String> labTips(List<String> keys) => [for (final k in keys) ?lab(k)];
  // Verminderde nierfunctie: dan geen advies om meer eiwit te eten
  final kidneys = labs['egfr']?.value.status == -1;

  final factors = [
    factor(
      'sodium',
      tr('Salt', 'Zout'),
      '${fmtNum(sodium * 2.5 / 1000)} g $perDay',
      rateDown(sodium, 2000, 2400),
      weight: 2,
      isKnown: known('sodium'),
      good: tr('Little salt: good for your blood pressure.', 'Weinig zout: goed voor je bloeddruk.'),
      ok: tr('A bit too much salt. That can raise your blood pressure slightly.', 'Iets te veel zout. Dat kan je bloeddruk wat doen stijgen.'),
      poor: tr(
        'Too much salt. That raises your blood pressure, and high blood pressure is the main cause of strokes and heart attacks.',
        'Te veel zout. Dat verhoogt je bloeddruk, en hoge bloeddruk is de grootste oorzaak van beroertes en hartaanvallen.',
      ),
      advice: tr(
        'Less ready meals, cold cuts, cheese, crisps and sauces; season with herbs instead of salt. Aim for at most 5 g a day.',
        'Minder kant-en-klaar, vleeswaren, kaas, chips en sauzen; kruid met kruiden in plaats van zout. Mik op hooguit 5 g per dag.',
      ),
      note: tr('Salt you add yourself while cooking is not included.', 'Zout dat je zelf toevoegt bij het koken, telt niet mee.'),
    ),
    factor(
      'sfa',
      tr('Saturated fat', 'Verzadigd vet'),
      '${fmtNum(sfa, 0)}% $ofEnergy',
      rateDown(sfa, 10, 12),
      weight: 2,
      isKnown: known('sfa'),
      tips: labTips(['ldl', 'non_hdl', 'hdl']),
      good: tr(
        'Little saturated fat: that keeps your LDL cholesterol low and protects your heart and blood vessels.',
        'Weinig verzadigd vet: dat houdt je LDL-cholesterol laag en beschermt je hart en bloedvaten.',
      ),
      ok: tr(
        'Slightly too much saturated fat. That raises your LDL cholesterol a little.',
        'Net iets te veel verzadigd vet. Dat verhoogt je LDL-cholesterol een beetje.',
      ),
      poor: tr(
        'Too much saturated fat. That raises your LDL cholesterol, and with it your risk of heart and vascular disease.',
        'Te veel verzadigd vet. Dat verhoogt je LDL-cholesterol, en daarmee je kans op hart- en vaatziekten.',
      ),
      advice: tr(
        'Swap butter, fatty cheese and processed meat for olive oil, nuts, fish and legumes. Keep it under 10% of your energy.',
        'Vervang boter, vette kaas en vleeswaren door olijfolie, noten, vis en peulvruchten. Blijf onder 10% van je energie.',
      ),
    ),
    factor(
      'fiber',
      tr('Fibre', 'Vezels'),
      '${fmtNum(fiber, 0)} g $perDay',
      rateUp(fiber, 25, 18),
      weight: 2,
      isKnown: known('fiber'),
      tips: [
        ...fiberTips,
        if (labs['ldl']?.value.status == 1 || labs['non_hdl']?.value.status == 1)
          tr(
            'Your cholesterol was high: soluble fibre (oats, barley, legumes, apples) lowers LDL by itself.',
            'Je cholesterol was hoog: oplosbare vezels (havermout, gerst, peulvruchten, appels) verlagen je LDL op zich al.',
          ),
      ],
      good: tr(
        'Enough fibre: good for your gut and blood sugar, and it lowers your risk of heart disease, type 2 diabetes and bowel cancer.',
        'Genoeg vezels: goed voor je darmen en je bloedsuiker, en het verlaagt je kans op hart- en vaatziekten, diabetes type 2 en darmkanker.',
      ),
      ok: tr(
        'A bit too little fibre. Every 5 g more a day goes with a lower risk of heart disease and bowel cancer.',
        'Iets te weinig vezels. Elke 5 g meer per dag hangt samen met minder kans op hart- en vaatziekten en darmkanker.',
      ),
      poor: tr(
        'Too little fibre. In the long run that raises your risk of heart disease, type 2 diabetes and bowel cancer, and it causes constipation sooner.',
        'Te weinig vezels. Op termijn verhoogt dat je kans op hart- en vaatziekten, diabetes type 2 en darmkanker, en je raakt sneller verstopt.',
      ),
      advice: tr(
        'Choose wholegrain bread and pasta, legumes, vegetables, fruit and nuts. Aim for at least 25 g a day.',
        'Kies volkoren brood en pasta, peulvruchten, groenten, fruit en noten. Mik op minstens 25 g per dag.',
      ),
    ),
    factor(
      'micro',
      tr('Vitamins and minerals', 'Vitaminen en mineralen'),
      'Nutrient Score ${micro.round()}',
      rateUp(micro, 85, 70),
      weight: 2,
      tips: [
        ...microTips,
        ...labTips(['vit_d', 'ferritin', 'transferrin_sat', 'b12', 'folate', 'hemoglobin', 'magnesium']),
      ],
      note: tr(
        'Counted over the week: your body stores most vitamins and minerals. Extra vitamin C, B vitamins or potassium is harmless, but you pass it out, so it counts for at most twice your goal per day.',
        'Over de week geteld: je lichaam bewaart de meeste vitaminen en mineralen. Extra vitamine C, B-vitaminen of kalium is onschadelijk, maar je plast het uit, dus het telt per dag hooguit voor twee keer je doel.',
      ),
      good: tr('You get almost all your vitamins and minerals.', 'Je haalt bijna al je vitaminen en mineralen.'),
      ok: tr(
        'You are short of a few vitamins or minerals. Not a problem for a week, but it adds up in the long run.',
        'Je komt een paar vitaminen of mineralen tekort. Voor een week geen probleem, maar op termijn telt het op.',
      ),
      poor: tr(
        'You are short of many vitamins and minerals. In the long run that can lead to tiredness, lower resistance and weaker bones.',
        'Je komt veel vitaminen en mineralen tekort. Op termijn kan dat leiden tot vermoeidheid, minder weerstand en zwakkere botten.',
      ),
      advice: tr(
        'Eat more varied: vegetables, fruit, wholegrains, nuts and dairy or fortified alternatives. See "Needs attention" below.',
        'Eet gevarieerder: groenten, fruit, volkoren, noten en zuivel of verrijkte alternatieven. Zie "Verdient aandacht" hieronder.',
      ),
    ),
    factor(
      'sugars',
      tr('Sugar', 'Suiker'),
      '${fmtNum(sugars, 0)}% $ofEnergy',
      rateDown(sugars, 15, 20),
      isKnown: known('sugars'),
      tips: labTips(['hba1c', 'glucose', 'triglycerides']),
      good: tr('Little sugar: good for your teeth, weight and blood sugar.', 'Weinig suiker: goed voor je tanden, je gewicht en je bloedsuiker.'),
      ok: tr(
        'Quite a lot of sugar. Sugar from fruit and milk is fine, added sugar is not.',
        'Vrij veel suiker. Suiker uit fruit en melk is geen probleem, toegevoegde suiker wel.',
      ),
      poor: tr(
        'A lot of sugar. Added sugar raises your risk of tooth decay, weight gain and type 2 diabetes.',
        'Veel suiker. Toegevoegde suiker verhoogt je kans op gaatjes, overgewicht en diabetes type 2.',
      ),
      advice: tr(
        'Fewer soft drinks, juice, sweets, biscuits and sweetened dairy. Fruit is fine.',
        'Minder frisdrank, sap, snoep, koeken en gezoete zuivel. Fruit mag gewoon.',
      ),
      note: tr(
        'The app cannot tell added sugar apart, so this is all sugar together.',
        'De app ziet niet welke suiker toegevoegd is, dus dit is alle suiker samen.',
      ),
    ),
    factor(
      'potassium',
      tr('Potassium', 'Kalium'),
      '${fmtNum(potassium, 0)} mg $perDay',
      rateUp(potassium, 3500, 2500),
      isKnown: known('potassium'),
      good: tr('Enough potassium: it helps keep your blood pressure low.', 'Genoeg kalium: dat helpt je bloeddruk laag te houden.'),
      ok: tr(
        'A bit too little potassium. Potassium counters the effect of salt on your blood pressure.',
        'Iets te weinig kalium. Kalium gaat het effect van zout op je bloeddruk tegen.',
      ),
      poor: tr(
        'Too little potassium. Together with salt, that raises your blood pressure.',
        'Te weinig kalium. Samen met zout verhoogt dat je bloeddruk.',
      ),
      advice: tr('More vegetables, fruit, legumes, potatoes and nuts.', 'Meer groenten, fruit, peulvruchten, aardappelen en noten.'),
    ),
    factor(
      'epa_dha',
      tr('Omega-3 from fish', 'Omega-3 uit vis'),
      '${fmtNum(epaDha, 0)} mg $perDay',
      rateUp(epaDha, 250, 100),
      isKnown: known('epa_dha'),
      good: tr('Enough omega-3 (EPA and DHA): good for your heart and brain.', 'Genoeg omega-3 (EPA en DHA): goed voor je hart en je hersenen.'),
      ok: tr('Somewhat little omega-3 (EPA and DHA).', 'Wat weinig omega-3 (EPA en DHA).'),
      poor: tr(
        'Hardly any omega-3 (EPA and DHA). These fats protect your heart and blood vessels.',
        'Bijna geen omega-3 (EPA en DHA). Die vetten beschermen je hart en bloedvaten.',
      ),
      advice: tr(
        'Eat fish once or twice a week, once oily fish such as salmon, mackerel or herring. Without fish: an algae oil supplement.',
        'Eet 1 à 2 keer per week vis, waarvan één keer vette vis zoals zalm, makreel of haring. Zonder vis: een supplement met algenolie.',
      ),
    ),
    factor(
      'protein',
      tr('Protein', 'Eiwit'),
      '${fmtNum(protein)} g ${tr('per kg', 'per kg')}',
      rateUp(protein, 0.83, 0.66),
      isKnown: weightKg > 0,
      tips: kidneys ? labTips(['egfr']) : proteinTips,
      good: tr('Enough protein to maintain your muscles.', 'Genoeg eiwit om je spieren te onderhouden.'),
      ok: tr('Slightly too little protein.', 'Net wat te weinig eiwit.'),
      poor: tr(
        'Too little protein. In the long run you lose muscle and recover more slowly.',
        'Te weinig eiwit. Op termijn verlies je spiermassa en herstel je trager.',
      ),
      advice: tr(
        'Add a protein source to every meal: dairy, eggs, fish, meat, legumes or tofu.',
        'Voeg bij elke maaltijd een eiwitbron toe: zuivel, eieren, vis, vlees, peulvruchten of tofu.',
      ),
    ),
    factor(
      'alcohol',
      tr('Alcohol', 'Alcohol'),
      tr('${fmtNum(glasses)} drinks per week', '${fmtNum(glasses)} glazen per week'),
      rateDown(glasses, 1, 7),
      tips: labTips(['ggt', 'alt', 'uric_acid']),
      good: tr('Little or no alcohol: the best for your health.', 'Weinig of geen alcohol: het beste voor je gezondheid.'),
      ok: tr(
        'Some alcohol. There is no safe amount: the less, the better.',
        'Wat alcohol. Er bestaat geen veilige hoeveelheid: hoe minder, hoe beter.',
      ),
      poor: tr(
        'A lot of alcohol. That raises your risk of cancer, liver disease and high blood pressure, and you sleep worse.',
        'Veel alcohol. Dat verhoogt je kans op kanker, leverziekte en hoge bloeddruk, en je slaapt slechter.',
      ),
      advice: tr(
        'Drink less than 10 drinks a week and keep several days a week without alcohol.',
        'Drink minder dan 10 glazen per week en houd een paar dagen per week zonder alcohol.',
      ),
      note: tr('One drink = 10 g of alcohol.', 'Eén glas = 10 g alcohol.'),
    ),
  ];

  // ── Beweging (WHO 2020): 150–300 minuten matig of 75–150 minuten intensief per week, 2 dagen spierversterkend ──
  final days7 = 7 / activity.days.clamp(1, 7);
  final running = activity.days < 7
      ? tr(
          ' This week is still running: counted as if the rest goes the same way.',
          ' Deze week loopt nog: omgerekend alsof de rest net zo verloopt.',
        )
      : '';
  if (activity.tracksExercise || activity.exercises.isNotEmpty) {
    // Intensiteit uit de verbrande energie: MET = kcal per minuut × 200 / (3,5 × kg). Intensief (≥ 6 MET) telt dubbel,
    // licht (< 3 MET) niet mee
    var minutes = 0.0;
    for (final e in activity.exercises) {
      final m = e.minutes;
      if (m == null || m <= 0) continue;
      final met = weightKg > 0 ? e.kcal / m * 200 / (3.5 * weightKg) : 4;
      minutes += m * (met >= 6 ? 2 : (met >= 3 ? 1 : 0));
    }
    minutes *= days7;
    factors.add(
      factor(
        'exercise',
        tr('Exercise', 'Bewegen'),
        tr('${fmtNum(minutes, 0)} min per week', '${fmtNum(minutes, 0)} min per week'),
        rateUp(minutes, 150, 75),
        weight: 2,
        good: tr(
          'Enough exercise: that lowers your risk of heart disease, type 2 diabetes, some cancers and depression, and you sleep better.',
          'Genoeg beweging: dat verlaagt je kans op hart- en vaatziekten, diabetes type 2, sommige kankers en depressie, en je slaapt beter.',
        ),
        ok: tr('Somewhat little exercise. Every extra 10 minutes already counts.', 'Wat weinig beweging. Elke 10 minuten extra telt al.'),
        poor: tr(
          'Too little exercise. That is one of the biggest risks for heart disease and type 2 diabetes.',
          'Te weinig beweging. Dat is een van de grootste risico\'s voor hart- en vaatziekten en diabetes type 2.',
        ),
        advice: tr(
          'Aim for at least 150 minutes a week of moderate exercise (brisk walking, cycling) or 75 minutes of intense exercise (running, swimming).',
          'Mik op minstens 150 minuten per week matig intensief bewegen (stevig wandelen, fietsen) of 75 minuten intensief (lopen, zwemmen).',
        ),
        note:
            tr(
              'Intense exercise counts double, as in the WHO guideline; the app estimates the intensity from the energy you burned.',
              'Intensief bewegen telt dubbel, zoals in de WHO-richtlijn; de app schat de intensiteit uit de verbrande energie.',
            ) +
            running,
      ),
    );
    final strengthDays = {
      for (final e in activity.exercises)
        if (e.strength) e.day,
    }.length;
    factors.add(
      factor(
        'strength',
        tr('Strength training', 'Krachttraining'),
        tr('$strengthDays ${strengthDays == 1 ? 'day' : 'days'} per week', '$strengthDays ${strengthDays == 1 ? 'dag' : 'dagen'} per week'),
        strengthDays >= 2 ? HealthRating.good : (strengthDays == 1 ? HealthRating.ok : HealthRating.poor),
        good: tr(
          'Enough strength training: strong muscles and bones, better blood sugar, and less risk of falling as you get older.',
          'Genoeg krachttraining: sterke spieren en botten, een betere bloedsuiker, en minder kans om te vallen als je ouder wordt.',
        ),
        ok: tr('Strength training once. Twice a week is the advice.', 'Eén keer krachttraining. Twee keer per week is het advies.'),
        poor: tr(
          'No strength training this week. Muscle strength protects your bones, your blood sugar and your independence later in life.',
          'Geen krachttraining deze week. Spierkracht beschermt je botten, je bloedsuiker en je zelfstandigheid op latere leeftijd.',
        ),
        advice: tr(
          'Twice a week, train all large muscle groups: with weights, bands or your own body weight (squats, push-ups).',
          'Train 2 keer per week alle grote spiergroepen: met gewichten, elastieken of je eigen lichaamsgewicht (squats, push-ups).',
        ),
        note: tr(
          'The app recognises strength training by its name (strength training, fitness, weightlifting, ...).',
          'De app herkent krachttraining aan de naam (krachttraining, fitness, gewichtheffen, ...).',
        ),
      ),
    );
  }
  if (activity.steps.length >= 3) {
    // Paluch e.a. (Lancet Public Health 2022): het voordeel vlakt af rond 8000–10 000 stappen, vanaf 60 jaar rond 6000–8000
    final older = age != null && age >= 60;
    final steps = activity.steps.reduce((a, b) => a + b) / activity.steps.length;
    factors.add(
      factor(
        'steps',
        tr('Steps', 'Stappen'),
        '${fmtNum(steps, 0)} $perDay',
        rateUp(steps, older ? 6000 : 8000, older ? 4000 : 5000),
        good: tr(
          'Enough steps: people who walk this much every day live longer and healthier on average.',
          'Genoeg stappen: wie elke dag zoveel stapt, leeft gemiddeld langer en gezonder.',
        ),
        ok: tr(
          'A bit too few steps. Every 1000 steps a day more goes with a lower risk of heart disease.',
          'Iets te weinig stappen. Elke 1000 stappen per dag meer hangt samen met minder kans op hart- en vaatziekten.',
        ),
        poor: tr(
          'Few steps. Sitting a lot raises your risk of heart disease and type 2 diabetes, even if you exercise.',
          'Weinig stappen. Veel stilzitten verhoogt je kans op hart- en vaatziekten en diabetes type 2, ook als je sport.',
        ),
        advice: tr(
          'Walk 10 minutes after a meal, take the stairs, get off a stop earlier or walk while you call.',
          'Wandel 10 minuten na het eten, neem de trap, stap een halte vroeger af of bel al wandelend.',
        ),
        note: tr(
          'Goal: ${older ? '6000' : '8000'} steps a day${older ? ' from 60' : ''}. Average of the ${activity.steps.length} days with step data.',
          'Doel: ${older ? '6000' : '8000'} stappen per dag${older ? ' vanaf 60 jaar' : ''}. Gemiddelde van de ${activity.steps.length} dagen met stappen.',
        ),
      ),
    );
  }

  final rated = factors.where((f) => f.rating != HealthRating.unknown);
  final totalWeight = rated.fold(0.0, (s, f) => s + f.weight);
  final score = totalWeight == 0 ? 0 : (rated.fold(0.0, (s, f) => s + f.points) / totalWeight / 2 * 100).round();
  // Eerst wat slecht is (zwaarste factoren bovenaan), dan oké, dan goed
  int order(HealthFactor f) => switch (f.rating) {
    HealthRating.poor => 0,
    HealthRating.ok => 1,
    HealthRating.good => 2,
    HealthRating.unknown => 3,
  };
  factors.sort((a, b) => order(a) != order(b) ? order(a) - order(b) : b.weight.compareTo(a.weight));
  return HealthCheck(
    days: n,
    factors: factors,
    score: score,
    rating: score >= 80 ? HealthRating.good : (score >= 50 ? HealthRating.ok : HealthRating.poor),
  );
}

extension on HealthFactor {
  double get points => rating.points * weight;
}
