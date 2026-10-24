/// Gezondheidscheck voor een week: hoe je eetpatroon je gezondheid op termijn beïnvloedt, per factor
/// (vezels, verzadigd vet, zout, ...) met een oordeel goed, oké of kan beter, en een eindoordeel.
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
    // Geen "Slecht": wie net begint, moet zich niet gebuisd voelen
    poor => tr('Room to improve', 'Kan beter'),
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
    this.aim,
  });

  final String key, title;

  /// Bv. "23 g per dag".
  final String value;

  /// Het doel waartegen het oordeel geldt, bv. "doel ≤ 5 g".
  final String? aim;
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
    aim: aim,
  );
}

class HealthCheck {
  const HealthCheck({required this.days, required this.factors, required this.score, required this.rating, this.labDay, this.energyFirst = false});

  /// Dag (jjjj-mm-dd) van de bloedafname waarop het advies steunt, of null zonder bloedwaarden.
  final String? labDay;

  /// Volledig gelogde dagen waarop het oordeel steunt.
  final int days;
  final List<HealthFactor> factors;

  /// 0–100.
  final int score;
  final HealthRating rating;

  /// Je gewicht gaat tegen je plan in en je energie verklaart dat: dan is energie het eerste punt.
  final bool energyFirst;

  /// Wat goed gaat, zwaarste factoren eerst.
  List<HealthFactor> get goingWell => [
    for (final f in factors)
      if (f.rating == HealthRating.good) f,
  ];

  /// Alles wat beter kan, belangrijkste eerst: energie als die ver van je doel zit, dan wat het meeste oplevert.
  /// Het rapport toont er hooguit [maxWorkPoints]; de rest staat onder "Meer punten".
  List<HealthFactor> get toWorkOn {
    int energy(HealthFactor f) => f.key == 'energy' && (energyFirst || f.rating == HealthRating.poor) ? 0 : 1;
    return [
      for (final f in factors)
        if (f.rating == HealthRating.ok || f.rating == HealthRating.poor) f,
    ]..sort((a, b) {
      if (energy(a) != energy(b)) return energy(a) - energy(b);
      if (a.gain != b.gain) return b.gain.compareTo(a.gain);
      if (a.rating != b.rating) return a.rating == HealthRating.poor ? -1 : 1;
      return b.weight.compareTo(a.weight);
    });
  }

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

  /// Eerst wat goed gaat, dan in rustige taal waar je best begint. Geen sterftecijfers of ziektes: die staan bij
  /// elk punt onder "Waarom het telt".
  String get summary {
    final good = [for (final f in goingWell.take(3)) f.title.toLowerCase()];
    final and = tr('and', 'en');
    final list = good.length < 2 ? good.join() : '${good.sublist(0, good.length - 1).join(', ')} $and ${good.last}';
    final energy = factors.where((f) => f.key == 'energy').firstOrNull;
    final rest = energyFirst
        ? tr(
            'Your weight is moving away from your plan, so energy is the main point this week.',
            'Je gewicht gaat een andere kant op dan je plan, dus energie is deze week het belangrijkste punt.',
          )
        : energy?.rating == HealthRating.poor
        ? tr('Your energy is far from your goal: start there.', 'Je energie zit ver van je doel: begin daar.')
        : switch (rating) {
            HealthRating.good => tr('A healthy week. Keep it up.', 'Een gezonde week. Ga zo door.'),
            HealthRating.ok => tr(
              'Below are the points that make the biggest difference.',
              'Hieronder staan de punten die het meeste verschil maken.',
            ),
            HealthRating.poor => tr(
              'There is room to improve. Start with the first point below: one small step at a time is enough.',
              'Er is ruimte om te verbeteren. Begin met het eerste punt hieronder: één kleine stap tegelijk is genoeg.',
            ),
            HealthRating.unknown => '',
          };
    return [if (good.isNotEmpty) tr('Going well: $list.', 'Goed bezig: $list.'), rest].join(' ');
  }
}

/// Zoveel werkpunten toont het rapport hooguit.
const maxWorkPoints = 3;

/// Je gewicht telt als stabiel als het over minstens [weightStableDays] dagen niet meer dan dit verandert (kg).
const weightStableKg = 0.3;
const weightStableDays = 12;

/// Gewichtsverloop: de verandering (kg) volgens een rechte lijn door je wegingen, zodat één zware dag de trend
/// niet omgooit.
class WeightTrend {
  const WeightTrend({required this.change, required this.days, required this.count});

  /// Verandering over [days] dagen, van eerste tot laatste weging.
  final double change;
  final int days, count;

  /// Over minstens twee weken gewogen en nauwelijks veranderd.
  bool get stable => days >= weightStableDays && count >= 3 && change.abs() <= weightStableKg;

  /// Duidelijk omhoog (1), omlaag (-1) of niet te zeggen (0). Pas vanaf een week wegen.
  int get direction => days < 6 || count < 2 ? 0 : (change > weightStableKg ? 1 : (change < -weightStableKg ? -1 : 0));

  /// Trend uit (dag, gewicht), of null bij minder dan twee wegingen.
  static WeightTrend? of(List<(DateTime, double)> points) {
    if (points.length < 2) return null;
    final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    final t0 = sorted.first.$1;
    final xs = [for (final p in sorted) p.$1.difference(t0).inHours / 24];
    final ys = [for (final p in sorted) p.$2];
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    final slope = sxx == 0 ? 0.0 : sxy / sxx;
    return WeightTrend(change: slope * xs.last, days: xs.last.round(), count: n);
  }
}

/// Hoe je energie zich verhoudt tot je doel, samen gelezen met je gewicht.
enum EnergyCase {
  /// Binnen de marge van je doel.
  onTarget,
  under,
  over,

  /// Je gewicht blijft gelijk (of gaat de andere kant op) bij wat je logt: je doel klopt waarschijnlijk niet.
  goalOff,

  /// Je logt minder dan je doel, maar je komt aan: waarschijnlijk is niet alles gelogd.
  missingLogs,

  /// Je gewicht gaat tegen je plan in, en je energie verklaart dat.
  againstPlan,
}

/// Energie tegenover je doel, met [margin] als deel van het doel dat nog "op doel" is.
EnergyCase energyCase({required double eaten, required double goal, WeightTrend? trend, Goal plan = Goal.maintain, double margin = 0.1}) {
  if (goal <= 0 || (eaten - goal).abs() / goal <= margin) return EnergyCase.onTarget;
  final under = eaten < goal;
  if (trend != null && trend.stable) {
    // Stabiel terwijl je wil aankomen (onder je doel) of afvallen (boven je doel): dan klopt het doel wel, en
    // verklaart je eten waarom het niet lukt
    return (under && plan == Goal.gain) || (!under && plan == Goal.lose) ? EnergyCase.againstPlan : EnergyCase.goalOff;
  }
  final dir = trend?.direction ?? 0;
  if (under) {
    if (dir > 0) return EnergyCase.missingLogs;
    if (dir < 0 && plan != Goal.lose) return EnergyCase.againstPlan;
  } else {
    if (dir < 0) return EnergyCase.goalOff;
    if (dir > 0 && plan != Goal.gain) return EnergyCase.againstPlan;
  }
  return under ? EnergyCase.under : EnergyCase.over;
}

/// Uitleg en advies bij [c]. Nooit blind "eet 900 kcal meer": wie op hetzelfde gewicht blijft, heeft eerder een
/// verkeerd doel of logt niet alles.
({String effect, String advice}) energyMessage(
  EnergyCase c, {
  required double eaten,
  required double goal,
  WeightTrend? trend,
  Goal plan = Goal.maintain,
}) {
  final gapKcal = (eaten - goal).abs();
  final gap = fmtNum(gapKcal, 0);
  final round = '${fmtNum(gapKcal / 100, 0)}00';
  final at = fmtNum((eaten / 50).round() * 50, 0);
  final under = eaten < goal;
  final moved = trend == null
      ? ''
      : ' (${trend.change > 0 ? '+' : '−'}${fmtNum(trend.change.abs())} kg ${tr('in ${trend.days} days', 'in ${trend.days} dagen')})';
  final want = switch (plan) {
    Goal.lose => tr('lose weight', 'afvallen'),
    Goal.gain => tr('gain weight', 'aankomen'),
    Goal.maintain => tr('keep your weight', 'je gewicht behouden'),
  };
  return switch (c) {
    EnergyCase.onTarget => (effect: tr('You eat about what your goal asks for.', 'Je eet ongeveer wat je doel vraagt.'), advice: ''),
    EnergyCase.goalOff when under => (
      effect: tr(
        'Your weight is stable at about $at kcal a day: your goal may be too high, or not everything is logged.',
        'Je gewicht is stabiel bij ongeveer $at kcal per dag: je doel ligt misschien te hoog, of niet alles is gelogd.',
      ),
      advice: tr(
        'Check that you log everything (drinks, cooking oil, snacks). If you do, lower your energy goal.',
        'Kijk na of je alles logt (drank, olie bij het koken, tussendoortjes). Doe je dat, verlaag dan je energiedoel.',
      ),
    ),
    EnergyCase.goalOff => (
      effect: (trend?.direction ?? 0) < 0
          ? tr(
              'Your weight is going down$moved at about $at kcal a day: your goal may be too low.',
              'Je gewicht gaat omlaag$moved bij ongeveer $at kcal per dag: je doel ligt misschien te laag.',
            )
          : tr(
              'Your weight is stable at about $at kcal a day: your goal may be too low, or portions are logged too large.',
              'Je gewicht is stabiel bij ongeveer $at kcal per dag: je doel ligt misschien te laag, of je logt te grote porties.',
            ),
      advice: tr('If your portions are logged correctly, raise your energy goal.', 'Als je porties juist gelogd zijn, verhoog dan je energiedoel.'),
    ),
    EnergyCase.missingLogs => (
      effect: tr(
        'Your weight is going up$moved although you logged $gap kcal a day below your goal: probably not everything is logged.',
        'Je gewicht gaat omhoog$moved terwijl je $gap kcal per dag onder je doel logde: waarschijnlijk is niet alles gelogd.',
      ),
      advice: tr(
        'Also log drinks, snacks, sauces and cooking oil, and compare again next week.',
        'Log ook drank, tussendoortjes, sauzen en olie bij het koken, en vergelijk volgende week opnieuw.',
      ),
    ),
    EnergyCase.againstPlan => (
      effect: under
          ? tr(
              'You ate on average $gap kcal a day below your goal and your weight is going down$moved, while you want to $want.',
              'Je at gemiddeld $gap kcal per dag onder je doel en je gewicht gaat omlaag$moved, terwijl je wil $want.',
            )
          : tr(
              'You ate on average $gap kcal a day above your goal and your weight is going up$moved, while you want to $want.',
              'Je at gemiddeld $gap kcal per dag boven je doel en je gewicht gaat omhoog$moved, terwijl je wil $want.',
            ),
      advice: under
          ? tr(
              'Add about $round kcal a day: an extra snack, a bigger portion of your usual meal or a glass of milk.',
              'Voeg ongeveer $round kcal per dag toe: een extra tussendoortje, een grotere portie van je gewone maaltijd of een glas melk.',
            )
          : tr(
              'Eat about $round kcal a day less: a smaller portion, fewer snacks or fewer sweet drinks.',
              'Eet ongeveer $round kcal per dag minder: een kleinere portie, minder tussendoortjes of minder zoete drank.',
            ),
    ),
    _ => (
      effect: tr(
        'You ate on average $gap kcal a day ${under ? 'below' : 'above'} your goal.',
        'Je at gemiddeld $gap kcal per dag ${under ? 'onder' : 'boven'} je doel.',
      ),
      advice: under
          ? tr(
                  'If you logged everything, add about $round kcal a day: an extra snack or a bigger portion.',
                  'Als je alles logde, voeg dan ongeveer $round kcal per dag toe: een extra tussendoortje of een grotere portie.',
                ) +
                (plan == Goal.gain
                    ? ''
                    : tr(
                        ' Weigh yourself now and then: if your weight stays the same, your goal is probably too high.',
                        ' Weeg je af en toe: blijft je gewicht gelijk, dan ligt je doel waarschijnlijk te hoog.',
                      ))
          : tr(
              'Eat about $round kcal a day less: a smaller portion, fewer snacks or fewer sweet drinks.',
              'Eet ongeveer $round kcal per dag minder: een kleinere portie, minder tussendoortjes of minder zoete drank.',
            ),
    ),
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

/// Een Britse alcohol-unit: 8 g (10 ml) pure alcohol.
const ukUnitGrams = 8.0;

/// Een dag telt als volledig gelogd vanaf de helft van je energiedoel (en minstens 800 kcal).
bool isFullDay(NutrientTotals t, Map<String, Target> targets) => t['energy'] >= math.max(800, (targets['energy']?.goal ?? 0) * 0.5);

/// Gezondheidscheck over [days] (totalen en doelen per dag). [weightKg] voor eiwit per kilo; [age], [heightCm] en
/// [trains] (krachttraining of veel sport) geven persoonlijk advies, net als [labs]: je laatste bloedwaarden per stof
/// (zie lib/labs/markers.dart). [weightTrend] en [plan] (afvallen, behouden, aankomen) lezen je energie samen met je
/// gewicht (zie [energyCase]). Null als er te weinig volledig gelogde dagen zijn.
HealthCheck? healthCheck(
  List<(NutrientTotals, Map<String, Target>)> days, {
  required double weightKg,
  int? age,
  double? heightCm,
  bool trains = false,
  Map<String, LabResult> labs = const {},
  ActivityWeek activity = const ActivityWeek(),
  WeightTrend? weightTrend,
  Goal plan = Goal.maintain,
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
    String? aim,
  }) {
    final r = isKnown ? rating : HealthRating.unknown;
    return HealthFactor(
      key: key,
      title: title,
      value: value,
      aim: aim,
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
  String aimOf(String s) => tr('goal $s', 'doel $s');

  final fiber = avg('fiber');
  final sfa = pctEnergy('sfa', 9);
  final sodium = avg('sodium');
  final potassium = avg('potassium');
  // Vrije suikers (frisdrank, sap, snoep, gezoete producten) als die geschat zijn: suiker uit heel fruit, groenten en
  // gewone melk telt dan niet mee (WHO: minder dan 10% van je energie). Anders alle suiker samen, met ruimere grenzen.
  final freeSugars = full.any((d) => d.$1.values.containsKey('free_sugars'));
  final sugars = freeSugars ? pctEnergy('free_sugars', 4) : pctEnergy('sugars', 4);
  final epaDha = avg('epa_dha');
  final protein = weightKg > 0 ? avg('protein') / weightKg : 0.0;
  // Alcohol in standaardglazen van 10 g per week ([ukUnitGrams] voor Britse units). Pas vanaf [alcoholMinDays] volledige dagen omrekenen naar een week:
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

  // Eiwit beoordelen we tegen je eigen eiwitdoel, met dezelfde regel als de kleuren van Vandaag (levelOf): onder je
  // doel is nooit "goed". Een probleem is het pas onder 0,83 g per kg (EFSA); daartussen is het "kan beter".
  final proteinGoal = mean(full.map((d) => d.$2['protein']?.goal));
  final proteinOfGoal = proteinGoal == null || proteinGoal <= 0 ? null : avg('protein') / proteinGoal;
  final proteinRating = switch (proteinGoal) {
    final g? when g > 0 && levelOf(avg('protein'), Target(goal: g)) == Level.ok => HealthRating.good,
    final g? when g > 0 && protein >= proteinMinPerKg => HealthRating.ok,
    final g? when g > 0 => rateUp(protein, proteinMinPerKg, 0.66) == HealthRating.poor ? HealthRating.poor : HealthRating.ok,
    _ => rateUp(protein, proteinMinPerKg, 0.66),
  };

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
  // Samen gelezen met je gewicht: bij een stabiel gewicht ligt het eerder aan je doel of aan wat je niet logt
  final eCase = energyCase(eaten: kcalEaten, goal: kcalGoal, trend: weightTrend, plan: plan);
  final eText = energyMessage(eCase, eaten: kcalEaten, goal: kcalGoal, trend: weightTrend, plan: plan);
  final factors = [
    if (kcalGoal > 0)
      factor(
        'energy',
        tr('Energy', 'Energie'),
        '${fmtNum(kcalEaten, 0)} / ${fmtNum(kcalGoal, 0)} kcal $perDay',
        switch (eCase) {
          EnergyCase.onTarget => HealthRating.good,
          EnergyCase.goalOff || EnergyCase.missingLogs => HealthRating.ok,
          EnergyCase.againstPlan => HealthRating.poor,
          _ => kcalOff <= 0.2 ? HealthRating.ok : HealthRating.poor,
        },
        good: eText.effect,
        ok: eText.effect,
        poor: eText.effect,
        advice: eText.advice,
        weight: 2,
      ),
    factor(
      'sodium',
      tr('Salt', 'Zout'),
      '${fmtNum(sodium * 2.5 / 1000)} g $perDay',
      rateDown(sodium, 2000, 2400),
      weight: 2,
      isKnown: known('sodium'),
      aim: aimOf('≤ 5 g'),
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
      aim: aimOf('≤ 10%'),
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
      aim: aimOf('≥ 25 g'),
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
      tr('${micro.round()}% of your goals met', '${micro.round()}% van je doelen gehaald'),
      rateUp(micro, 85, 70),
      aim: aimOf('≥ 85%'),
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
      freeSugars ? tr('Free sugar', 'Vrije suiker') : tr('Sugar', 'Suiker'),
      '${fmtNum(sugars, 0)}% $ofEnergy',
      freeSugars ? rateDown(sugars, 10, 15) : rateDown(sugars, 15, 20),
      isKnown: known('sugars'),
      aim: aimOf(freeSugars ? '< 10%' : '< 15%'),
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
      note: freeSugars
          ? tr(
              'Only free sugar counts here (soft drinks, juice, sweets, sweetened products), estimated per product. Sugar in whole fruit, vegetables and plain milk does not. Aim: under 10% of your energy (WHO).',
              'Hier telt alleen vrije suiker (frisdrank, sap, snoep, gezoete producten), per product geschat. Suiker in heel fruit, groenten en gewone melk telt niet mee. Streef: minder dan 10% van je energie (WHO).',
            )
          : tr(
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
      aim: aimOf('≥ 3500 mg'),
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
      aim: aimOf('≥ 250 mg'),
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
      proteinOfGoal == null
          ? '${fmtNum(protein)} g ${tr('per kg', 'per kg')}'
          : '${fmtNum(protein)} g ${tr('per kg', 'per kg')} · ${fmtNum(proteinOfGoal * 100, 0)}% ${tr('of your goal', 'van je doel')}',
      proteinRating,
      isKnown: weightKg > 0,
      aim: proteinGoal == null ? aimOf('≥ ${fmtNum(proteinMinPerKg, 2)} g/kg') : aimOf('${fmtNum(proteinGoal, 0)} g $perDay'),
      tips: kidneys ? const [] : proteinTips,
      bloodTips: labTips(['egfr']),
      good: proteinOfGoal == null
          ? tr('Enough protein to maintain your muscles.', 'Genoeg eiwit om je spieren te onderhouden.')
          : tr('You reach your protein goal.', 'Je haalt je eiwitdoel.'),
      ok: protein >= proteinMinPerKg
          ? tr(
              'Below your own protein goal, but enough to maintain your muscles (at least 0.83 g per kg).',
              'Onder je eigen eiwitdoel, maar genoeg om je spieren te onderhouden (minstens 0,83 g per kg).',
            )
          : tr('Slightly too little protein.', 'Net wat te weinig eiwit.'),
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
          // In het Engels ook Britse units van 8 g (N48): een glas van 10 g is 1,25 unit
          ? tr('${fmtNum(glasses)} drinks per week (${fmtNum(glasses * 10 / ukUnitGrams)} UK units)', '${fmtNum(glasses)} glazen per week')
          : tr(
              '${fmtNum(drinksLogged)} drinks in $n days (${fmtNum(drinksLogged * 10 / ukUnitGrams)} UK units)',
              '${fmtNum(drinksLogged)} glazen in $n dagen',
            ),
      // Zelfde grens als de uitleg en het advies (Hoge Gezondheidsraad: hooguit 10 glazen per week): eronder "oké",
      // erboven "kan beter"
      rateDown(glasses, 1, 10),
      isKnown: alcoholKnown,
      aim: tr('at most 10 a week (12.5 UK units), less is better', 'hooguit 10 per week, minder is beter'),
      unknown: tr(
        'Too few fully logged days to work out a weekly figure. Log at least $alcoholMinDays days.',
        'Te weinig volledig gelogde dagen om een weekcijfer te berekenen. Log minstens $alcoholMinDays dagen.',
      ),
      bloodTips: labTips(['ggt', 'alt', 'uric_acid']),
      good: tr('Little or no alcohol: the best for your health.', 'Weinig of geen alcohol: het beste voor je gezondheid.'),
      ok: tr(
        'Some alcohol, within the limit of 10 drinks a week. Still, every drink counts: the less, the better.',
        'Wat alcohol, binnen de grens van 10 glazen per week. Toch telt elk glas: hoe minder, hoe beter.',
      ),
      poor: tr(
        'More than 10 drinks a week. That raises your risk of cancer, liver disease and high blood pressure, and you sleep worse.',
        'Meer dan 10 glazen per week. Dat verhoogt je kans op kanker, leverziekte en hoge bloeddruk, en je slaapt slechter.',
      ),
      advice: tr(
        'Stay at 10 drinks a week or less and keep several days a week without alcohol.',
        'Blijf op hooguit 10 glazen per week en houd een paar dagen per week zonder alcohol.',
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
    var minutes = 0.0, logged = 0.0;
    for (final e in activity.exercises) {
      final m = e.minutes;
      if (m == null || m <= 0) continue;
      logged += m;
      final met = weightKg > 0 ? e.kcal / m * 200 / (3.5 * weightKg) : 4;
      minutes += m * (met >= 6 ? 2 : (met >= 3 ? 1 : 0));
    }
    minutes *= days7;
    exerciseMinutes = minutes;
    // Eén getal dat overeenkomt met wat je logde, en erbij hoe het meetelt (intensief dubbel, lopende week omgerekend)
    final counted = fmtNum(minutes, 0), raw = fmtNum(logged, 0);
    factors.add(
      factor(
        'exercise',
        tr('Exercise', 'Bewegen'),
        counted == raw
            ? tr('$raw min per week', '$raw min per week')
            : tr('$raw min logged, counts as $counted min a week', '$raw min gelogd, telt als $counted min per week'),
        rateUp(minutes, 150, 75),
        aim: aimOf('≥ 150 min'),
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
        aim: aimOf(tr('2 days', '2 dagen')),
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
        aim: aimOf('${older ? '6000' : '8000'} $perDay'),
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
  var rating = score >= 80 ? HealthRating.good : (score >= 50 ? HealthRating.ok : HealthRating.poor);
  // Een energie ver van je doel past niet bij "een gezonde week"
  final energyPoor = factors.any((f) => f.key == 'energy' && f.rating == HealthRating.poor);
  if (energyPoor && rating == HealthRating.good) rating = HealthRating.ok;
  return HealthCheck(
    days: n,
    labDay: labs.values.map((r) => r.day).fold<String?>(null, (a, d) => a == null || d.compareTo(a) > 0 ? d : a),
    factors: factors,
    score: score,
    rating: rating,
    energyFirst: kcalGoal > 0 && eCase == EnergyCase.againstPlan,
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
  // (zelfde grens als het oordeel: tot 10 glazen is "oké")
  out['alcohol'] = glasses <= 10
      ? (
          tr(
            'Up to 10 drinks a week large studies see no measurable loss of life expectancy, though every drink slightly raises your cancer risk.',
            'Tot 10 glazen per week zien grote studies geen meetbaar verlies aan levensverwachting, al verhoogt elk glas je kans op kanker licht.',
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
