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
    this.bloodTips = const [],
    this.weight = 1,
    this.impact,
    this.gain = 0,
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

  /// Advies op basis van je bloedwaarden (zie [HealthCheck.labDay]).
  final List<String> bloodTips;

  /// Gewicht in het eindoordeel: de grote risicofactoren tellen dubbel.
  final double weight;

  /// Wat dit ongeveer betekent voor je gezondheid, in cijfers uit grote studies (zie [healthImpact]).
  final String? impact;

  /// Hoeveel je ongeveer wint door dit te verbeteren (procent minder risico), om de grootste winst te kiezen.
  final double gain;

  HealthFactor withImpact(String? impact, double gain) => HealthFactor(
    key: key,
    title: title,
    value: value,
    rating: rating,
    effect: effect,
    advice: advice,
    note: note,
    tips: tips,
    bloodTips: bloodTips,
    weight: weight,
    impact: impact,
    gain: gain,
  );
}

class HealthCheck {
  const HealthCheck({required this.days, required this.factors, required this.score, required this.rating, this.labDay});

  /// Dag (jjjj-mm-dd) van de bloedafname waarop het advies steunt, of null zonder bloedwaarden.
  final String? labDay;

  /// Volledig gelogde dagen waarop het oordeel steunt.
  final int days;
  final List<HealthFactor> factors;

  /// 0–100.
  final int score;
  final HealthRating rating;

  /// Het punt waar je het meest wint, of null als alles goed is.
  HealthFactor? get biggestGain {
    final open = [
      for (final f in factors)
        if (f.gain > 0 && f.impact != null && (f.rating == HealthRating.ok || f.rating == HealthRating.poor)) f,
    ]..sort((a, b) => b.gain.compareTo(a.gain));
    return open.firstOrNull;
  }

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

/// Minstens zoveel volledig gelogde dagen om alcohol naar een week om te rekenen.
const alcoholMinDays = 4;

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
    List<String> bloodTips = const [],
    double weight = 1,
    bool isKnown = true,
    String? unknown,
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
        HealthRating.unknown =>
          unknown ??
              tr(
                'Too many of the foods you logged have no data for this, so the app cannot judge it.',
                'Van te veel producten die je logde ontbreken gegevens hierover, dus de app kan dit niet beoordelen.',
              ),
      },
      advice: r == HealthRating.ok || r == HealthRating.poor ? advice : null,
      note: note,
      tips: r == HealthRating.unknown ? const [] : tips,
      bloodTips: bloodTips,
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
  // Alcohol in standaardglazen van 10 g per week. Pas vanaf [alcoholMinDays] volledige dagen omrekenen naar een week:
  // uit 3 dagen een weekcijfer maken, overdrijft een feestje of verbergt een gewone week
  final glasses = avg('alcohol') * 7 / 10;
  final alcoholKnown = n >= alcoholMinDays;
  final drinksLogged = full.fold(0.0, (s, d) => s + d.$1['alcohol']) / 10;
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
    final shown = '${v.comparator ?? ''}${fmtNum(v.value, m.decimals)} ${v.unit ?? m.unit}';
    final word = v.status < 0 ? tr('low', 'laag') : tr('high', 'hoog');
    return '${m.name} $shown ($word). ${tr(text.$1, text.$2)}';
  }

  List<String> labTips(List<String> keys) => [for (final k in keys) ?lab(k)];
  // Verminderde nierfunctie: dan geen advies om meer eiwit te eten
  final kidneys = labs['egfr']?.value.status == -1;

  // Energie: at je ongeveer wat je doel vraagt? Een groot tekort of overschot verdient de eerste plaats
  final kcalGoal = full.fold(0.0, (s, d) => s + (d.$2['energy']?.goal ?? 0)) / n;
  final kcalEaten = energy / n;
  final kcalGap = kcalEaten - kcalGoal;
  final kcalOff = kcalGoal <= 0 ? 0.0 : kcalGap.abs() / kcalGoal;
  final under = kcalGap < 0;
  final factors = [
    if (kcalGoal > 0)
      factor(
        'energy',
        tr('Energy', 'Energie'),
        '${fmtNum(kcalEaten, 0)} / ${fmtNum(kcalGoal, 0)} kcal $perDay',
        kcalOff <= 0.1 ? HealthRating.good : (kcalOff <= 0.2 ? HealthRating.ok : HealthRating.poor),
        good: tr('You eat about what your goal asks for.', 'Je eet ongeveer wat je doel vraagt.'),
        ok: tr(
          'You ate on average ${fmtNum(kcalGap.abs(), 0)} kcal a day ${under ? 'below' : 'above'} your goal.',
          'Je at gemiddeld ${fmtNum(kcalGap.abs(), 0)} kcal per dag ${under ? 'onder' : 'boven'} je doel.',
        ),
        poor: tr(
          'You ate on average ${fmtNum(kcalGap.abs(), 0)} kcal a day ${under ? 'below' : 'above'} your goal, so your weight will not go the way you planned.',
          'Je at gemiddeld ${fmtNum(kcalGap.abs(), 0)} kcal per dag ${under ? 'onder' : 'boven'} je doel, dus je gewicht gaat niet de kant op die je plande.',
        ),
        advice: under
            ? tr(
                'Add about ${fmtNum(kcalGap.abs() / 100, 0)}00 kcal a day: an extra snack, a bigger portion of your usual meal or a glass of milk.',
                'Voeg ongeveer ${fmtNum(kcalGap.abs() / 100, 0)}00 kcal per dag toe: een extra tussendoortje, een grotere portie van je gewone maaltijd of een glas melk.',
              )
            : tr(
                'Eat about ${fmtNum(kcalGap.abs() / 100, 0)}00 kcal a day less: a smaller portion, fewer snacks or fewer sweet drinks.',
                'Eet ongeveer ${fmtNum(kcalGap.abs() / 100, 0)}00 kcal per dag minder: een kleinere portie, minder tussendoortjes of minder zoete drank.',
              ),
        weight: 2,
      ),
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
      bloodTips: labTips(['ldl', 'non_hdl', 'hdl']),
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
      tips: fiberTips,
      bloodTips: [
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
      'Nutrient score ${micro.round()}',
      rateUp(micro, 85, 70),
      weight: 2,
      tips: microTips,
      bloodTips: labTips(['vit_d', 'ferritin', 'transferrin_sat', 'b12', 'folate', 'hemoglobin', 'magnesium']),
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
      bloodTips: labTips(['hba1c', 'glucose', 'triglycerides']),
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
      tips: kidneys ? const [] : proteinTips,
      bloodTips: labTips(['egfr']),
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
      alcoholKnown
          ? tr('${fmtNum(glasses)} drinks per week', '${fmtNum(glasses)} glazen per week')
          : tr('${fmtNum(drinksLogged)} drinks in $n days', '${fmtNum(drinksLogged)} glazen in $n dagen'),
      rateDown(glasses, 1, 7),
      isKnown: alcoholKnown,
      unknown: tr(
        'Too few fully logged days to work out a weekly figure. Log at least $alcoholMinDays days.',
        'Te weinig volledig gelogde dagen om een weekcijfer te berekenen. Log minstens $alcoholMinDays dagen.',
      ),
      bloodTips: labTips(['ggt', 'alt', 'uric_acid']),
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
  double? exerciseMinutes, stepsPerDay;
  int? strengthDayCount;
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
    exerciseMinutes = minutes;
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
    strengthDayCount = strengthDays;
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
    stepsPerDay = steps;
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

  final impacts = healthImpact(
    salt: sodium * 2.5 / 1000,
    sfa: sfa,
    fiber: fiber,
    potassium: potassium,
    epaDha: epaDha,
    glasses: glasses,
    exerciseMinutes: exerciseMinutes,
    strengthDays: strengthDayCount,
    steps: stepsPerDay,
  );
  for (final (i, f) in factors.indexed) {
    if (f.rating == HealthRating.unknown) continue;
    if (impacts[f.key] case (final text, final gain)) factors[i] = f.withImpact(text, gain);
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
    labDay: labs.values.map((r) => r.day).fold<String?>(null, (a, d) => a == null || d.compareTo(a) > 0 ? d : a),
    factors: factors,
    score: score,
    rating: score >= 80 ? HealthRating.good : (score >= 50 ? HealthRating.ok : HealthRating.poor),
  );
}

extension on HealthFactor {
  double get points => rating.points * weight;
}

/// Wat je gewoonten ongeveer betekenen, in cijfers uit grote studies. Per punt (tekst, winst in procent minder risico
/// als je de richtlijn haalt). Het zijn gemiddelden over grote groepen mensen en meestal verbanden: ze tonen wat
/// ongeveer op het spel staat, geen voorspelling voor één persoon.
///
/// Bronnen: Arem e.a. 2015 (JAMA Intern Med, beweging), Paluch e.a. 2022 (Lancet Public Health, stappen), Momma e.a.
/// 2022 (Br J Sports Med, krachttraining), Reynolds e.a. 2019 (Lancet, vezels), Strazzullo e.a. 2009 (BMJ, zout),
/// Hooper e.a. 2020 (Cochrane, verzadigd vet), Aburto e.a. 2013 (BMJ, kalium), Mozaffarian & Rimm 2006 (JAMA, vis),
/// Wood e.a. 2018 (Lancet, alcohol).
Map<String, (String, double)> healthImpact({
  required double salt,
  required double sfa,
  required double fiber,
  required double potassium,
  required double epaDha,
  required double glasses,
  double? exerciseMinutes,
  int? strengthDays,
  double? steps,
}) {
  String pct(double v) => '${(v / 5).round() * 5}%';
  final out = <String, (String, double)>{};

  // Beweging: minder kans op vroegtijdig overlijden dan wie niet beweegt (Arem 2015)
  if (exerciseMinutes case final m?) {
    final r = m <= 0 ? 0.0 : (m < 150 ? 20.0 : (m < 300 ? 31.0 : (m < 450 ? 37.0 : 39.0)));
    out['exercise'] = m >= 150
        ? (
            tr(
              'About ${pct(r)} less chance of dying early than people who do not exercise.',
              'Ongeveer ${pct(r)} minder kans om vroegtijdig te overlijden dan wie niet beweegt.',
            ),
            0,
          )
        : (
            m <= 0
                ? tr(
                    '150 minutes a week means about 30% less chance of dying early.',
                    '150 minuten per week betekent ongeveer 30% minder kans om vroegtijdig te overlijden.',
                  )
                : tr(
                    'Now about ${pct(r)} less chance of dying early than people who do not exercise; with 150 minutes a week about 30%.',
                    'Nu ongeveer ${pct(r)} minder kans om vroegtijdig te overlijden dan wie niet beweegt; met 150 minuten per week ongeveer 30%.',
                  ),
            31 - r,
          );
  }

  // Stappen: tegenover ongeveer 3500 per dag (Paluch 2022: 3500 → 5800 → 7800 → 10 900 stappen = 0, 40, 45, 53%)
  if (steps case final st?) {
    double at(double x) {
      const pts = [(3500.0, 0.0), (5800.0, 40.0), (7800.0, 45.0), (10900.0, 53.0)];
      if (x <= pts.first.$1) return 0;
      if (x >= pts.last.$1) return pts.last.$2;
      for (var i = 1; i < pts.length; i++) {
        if (x <= pts[i].$1) return pts[i - 1].$2 + (x - pts[i - 1].$1) / (pts[i].$1 - pts[i - 1].$1) * (pts[i].$2 - pts[i - 1].$2);
      }
      return 0;
    }

    final r = at(st);
    out['steps'] = r >= 40
        ? (
            tr(
              'About ${pct(r)} less chance of dying early than people who walk around 3500 steps a day.',
              'Ongeveer ${pct(r)} minder kans om vroegtijdig te overlijden dan wie rond 3500 stappen per dag blijft.',
            ),
            0,
          )
        : (
            tr(
              'Going to 6000 steps a day goes with about 40% less chance of dying early than staying around 3500.',
              'Naar 6000 stappen per dag gaan hangt samen met ongeveer 40% minder kans om vroegtijdig te overlijden dan rond 3500 blijven.',
            ),
            at(6000) - r,
          );
  }

  // Krachttraining: 30–60 minuten per week, 10 à 20% minder sterfte, hart- en vaatziekten en diabetes (Momma 2022)
  if (strengthDays case final d?) {
    out['strength'] = d >= 1
        ? (
            tr(
              'Strength training goes with 10 to 20% less chance of dying early, heart disease and diabetes.',
              'Krachttraining hangt samen met 10 à 20% minder kans op vroegtijdig overlijden, hart- en vaatziekten en diabetes.',
            ),
            d >= 2 ? 0 : 5,
          )
        : (
            tr(
              '30 to 60 minutes of strength training a week goes with 10 to 20% less chance of dying early, heart disease and diabetes.',
              '30 à 60 minuten krachttraining per week hangt samen met 10 à 20% minder kans op vroegtijdig overlijden, hart- en vaatziekten en diabetes.',
            ),
            15,
          );
  }

  // Vezels: 25–29 g tegenover minder dan 15 g, 15 à 30% minder sterfte en hart- en vaatziekten (Reynolds 2019)
  out['fiber'] = fiber >= 25
      ? (
          tr(
            'About 15 to 30% less chance of dying of heart disease than people under 15 g a day.',
            'Ongeveer 15 à 30% minder kans om te overlijden aan hart- en vaatziekten dan wie onder 15 g per dag blijft.',
          ),
          0,
        )
      : (
          tr(
            'Going to 25 g a day goes with up to 15 to 30% less chance of heart disease, type 2 diabetes and bowel cancer.',
            'Naar 25 g per dag gaan hangt samen met tot 15 à 30% minder kans op hart- en vaatziekten, diabetes type 2 en darmkanker.',
          ),
          fiber < 15 ? 20 : 10,
        );

  // Zout: 5 g per dag meer = 23% meer beroertes (Strazzullo 2009), dus ongeveer 5% per gram
  out['sodium'] = salt > 5
      ? (
          tr(
            'Your ${fmtNum(salt - 5)} g of salt a day above 5 g means about ${pct((salt - 5) * 4.6)} more chance of a stroke.',
            'Je ${fmtNum(salt - 5)} g zout per dag boven 5 g betekent ongeveer ${pct((salt - 5) * 4.6)} meer kans op een beroerte.',
          ),
          ((salt - 5) * 4.6).clamp(0, 40).toDouble(),
        )
      : (
          tr(
            'Every gram of salt a day less means about 5% less chance of a stroke.',
            'Elke gram zout per dag minder betekent ongeveer 5% minder kans op een beroerte.',
          ),
          0,
        );

  // Verzadigd vet minder en vervangen door onverzadigd: 17% minder hart- en vaatziekten (Hooper 2020)
  out['sfa'] = sfa > 10
      ? (
          tr(
            'Less saturated fat, replaced by unsaturated fat, goes with about 17% fewer heart and vascular events.',
            'Minder verzadigd vet, vervangen door onverzadigd vet, geeft ongeveer 17% minder hart- en vaatziekten.',
          ),
          sfa > 12 ? 17 : 8,
        )
      : (
          tr(
            'Keeping saturated fat low goes with about 17% fewer heart and vascular events than eating a lot of it.',
            'Weinig verzadigd vet geeft ongeveer 17% minder hart- en vaatziekten dan veel.',
          ),
          0,
        );

  // Kalium: meer kalium, 24% minder beroertes (Aburto 2013)
  out['potassium'] = potassium >= 3500
      ? (tr('About 24% less chance of a stroke than with little potassium.', 'Ongeveer 24% minder kans op een beroerte dan met weinig kalium.'), 0)
      : (
          tr('More potassium goes with up to 24% less chance of a stroke.', 'Meer kalium hangt samen met tot 24% minder kans op een beroerte.'),
          ((3500 - potassium) / 1500 * 24).clamp(0, 24).toDouble(),
        );

  // Vis: 250 mg EPA + DHA per dag, 36% minder sterfte aan hartziekten (Mozaffarian 2006)
  final fish = (epaDha.clamp(0, 250) / 250 * 36).toDouble();
  out['epa_dha'] = epaDha >= 250
      ? (
          tr(
            'About 36% less chance of dying of heart disease than people who eat no fish.',
            'Ongeveer 36% minder kans om te overlijden aan hartziekten dan wie geen vis eet.',
          ),
          0,
        )
      : (
          tr(
            'Fish once or twice a week (250 mg EPA + DHA a day) goes with about 36% less chance of dying of heart disease.',
            'Vis 1 à 2 keer per week (250 mg EPA + DHA per dag) hangt samen met ongeveer 36% minder kans om te overlijden aan hartziekten.',
          ),
          36 - fish,
        );

  // Alcohol en levensverwachting op 40 jaar, tegenover minder dan 10 glazen per week (Wood 2018)
  out['alcohol'] = glasses < 10
      ? (
          tr(
            'Under 10 drinks a week large studies see no measurable loss of life expectancy, though every drink slightly raises your cancer risk.',
            'Onder 10 glazen per week zien grote studies geen meetbaar verlies aan levensverwachting, al verhoogt elk glas je kans op kanker licht.',
          ),
          0,
        )
      : (
          glasses < 20
              ? tr(
                  'At this level, life expectancy is about 6 months shorter.',
                  'Bij deze hoeveelheid is de levensverwachting ongeveer 6 maanden korter.',
                )
              : (glasses < 35
                    ? tr(
                        'At this level, life expectancy is about 1 to 2 years shorter.',
                        'Bij deze hoeveelheid is de levensverwachting ongeveer 1 à 2 jaar korter.',
                      )
                    : tr(
                        'At this level, life expectancy is about 4 to 5 years shorter.',
                        'Bij deze hoeveelheid is de levensverwachting ongeveer 4 à 5 jaar korter.',
                      )),
          glasses < 20 ? 5 : (glasses < 35 ? 15 : 30),
        );
  return out;
}
