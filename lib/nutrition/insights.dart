/// Afgeleide inzichten: status per voedingsstof, volledigheidsscore, wat aandacht vraagt,
/// trendgewicht en een geschat verbruik uit gewicht en logboek. Zonder Flutter, zodat het testbaar is.
library;

import 'dart:math' as math;

import 'nutrients.dart';
import 'targets.dart';
import 'values.dart';
import '../i18n.dart';

/// Status van een voedingsstof ten opzichte van de richtwaarde.
enum Level { none, low, ok, high }

/// Eén kleurregel voor alle schermen: onder het doel is laag, boven de bovengrens is te veel, en bij een doel om
/// ongeveer te halen (energie, koolhydraten, vet) telt meer dan 10% erboven ook als te veel, nooit als groen.
Level levelOf(double amount, Target? t) {
  if (t == null) return Level.none;
  if (t.upper != null && amount > t.upper!) return Level.high;
  if (t.goal == null) return Level.ok;
  if (t.about && amount > t.goal! * 1.1) return Level.high;
  return amount >= t.goal! ? Level.ok : Level.low;
}

/// Hoeveelheid als deel van het doel (of van het maximum bij een limiet), of null zonder richtwaarde.
double? fractionOf(double amount, Target? t) {
  final ref = t?.goal ?? t?.upper;
  return ref == null || ref <= 0 ? null : amount / ref;
}

/// De 25 vitaminen en mineralen in het overzicht van Vandaag, met hun afkorting.
const stripVitamins = [
  ('vit_a', 'A'),
  ('vit_c', 'C'),
  ('vit_d', 'D'),
  ('vit_e', 'E'),
  ('vit_k', 'K'),
  ('b1', 'B1'),
  ('b2', 'B2'),
  ('b3', 'B3'),
  ('b5', 'B5'),
  ('b6', 'B6'),
  ('b7', 'B7'),
  ('b9', 'B9'),
  ('b12', 'B12'),
  ('choline', 'Ch'),
];
const stripMinerals = [
  ('calcium', 'Ca'),
  ('copper', 'Cu'),
  ('iodine', 'I'),
  ('iron', 'Fe'),
  ('magnesium', 'Mg'),
  ('manganese', 'Mn'),
  ('phosphorus', 'P'),
  ('potassium', 'K'),
  ('selenium', 'Se'),
  ('sodium', 'Na'),
  ('zinc', 'Zn'),
];
final stripKeys = [
  for (final (k, _) in [...stripVitamins, ...stripMinerals]) k,
];

/// Volledigheidsscore 0–100: hoe dicht je bij je doel zit voor de 25 vitaminen en mineralen.
/// Per stof telt het deel van het doel (maximaal 100%); boven een bovengrens of limiet daalt de score.
int completenessScore(NutrientMap values, Map<String, Target> targets) {
  var sum = 0.0, n = 0;
  for (final k in stripKeys) {
    final t = targets[k];
    if (t == null || (t.goal == null && t.upper == null)) continue;
    final v = values[k] ?? 0;
    double s;
    if (t.upper != null && v > t.upper!) {
      s = t.upper! / v;
    } else if (t.goal == null) {
      // Alleen een bovengrens, geen streefwaarde: bij nul inname telt dit niet mee als "gehaald".
      if (v <= 0) continue;
      s = 1;
    } else {
      s = math.min(1, v / t.goal!);
    }
    sum += s;
    n++;
  }
  return n == 0 ? 0 : (sum / n * 100).round();
}

/// Deel van je kcal waarvoor gegevens bestaan, gemiddeld over de 25 stoffen (1 = alles bekend).
double dataCoverage(NutrientTotals totals) {
  final energy = totals.values['energy'] ?? 0;
  if (energy <= 0) return 1;
  var sum = 0.0;
  for (final k in stripKeys) {
    sum += 1 - math.min(1, (totals.missingEnergy[k] ?? 0) / energy);
  }
  return sum / stripKeys.length;
}

/// Wat aandacht vraagt: eerst wat boven een bovengrens of limiet zit, dan de grootste tekorten.
List<(Nutrient, double, Level)> attentionList(NutrientMap values, Map<String, Target> targets, {int limit = 3}) {
  final high = <(Nutrient, double, Level)>[];
  final low = <(Nutrient, double, Level)>[];
  for (final k in stripKeys) {
    final t = targets[k];
    final f = fractionOf(values[k] ?? 0, t);
    if (f == null) continue;
    final level = levelOf(values[k] ?? 0, t);
    final n = nutrientByKey[k]!;
    if (level == Level.high) high.add((n, f, level));
    if (level == Level.low) low.add((n, f, level));
  }
  low.sort((a, b) => a.$2.compareTo(b.$2));
  high.sort((a, b) => b.$2.compareTo(a.$2));
  // Hooguit één "te veel" bovenaan, zodat de tekorten zichtbaar blijven
  return [...low.take(limit - math.min(1, high.length)), ...high.take(1)].take(limit).toList()
    ..sort((a, b) => a.$3 == b.$3 ? a.$2.compareTo(b.$2) : (a.$3 == Level.low ? -1 : 1));
}

/// Verdeling van de energie over eiwit, koolhydraten en vet, in delen van 1 (samen 1), of null zonder energie.
(double, double, double)? macroSplit(NutrientMap v) {
  final p = (v['protein'] ?? 0) * 4, c = (v['carbs'] ?? 0) * 4, f = (v['fat'] ?? 0) * 9;
  final total = p + c + f;
  return total <= 0 ? null : (p / total, c / total, f / total);
}

/// Trendgewicht: exponentieel gewogen gemiddelde per dag, zodat schommelingen van vocht en eten wegvallen.
/// [weights] per dag (jjjj-mm-dd); dagen zonder weging nemen de vorige trend over. Null tot de eerste weging.
List<double?> weightTrend(Map<String, double> weights, List<String> days, {double alpha = 0.1}) {
  double? t;
  return [
    for (final d in days)
      if (weights[d] case final w?) t = t == null ? w : t + alpha * (w - t) else t,
  ];
}

/// Geschat verbruik uit wat je at en hoe je trendgewicht veranderde (7700 kcal per kg lichaamsgewicht).
class EnergyEstimate {
  const EnergyEstimate({required this.tdee, required this.avgIntake, required this.trendChange, required this.days});

  /// Geschat dagelijks verbruik in kcal.
  final double tdee;

  /// Gemiddelde inname op gelogde dagen.
  final double avgIntake;

  /// Verandering van het trendgewicht over de periode, in kg.
  final double trendChange;

  /// Aantal dagen in de periode.
  final int days;
}

/// Pas betrouwbaar met genoeg gegevens: minstens 14 dagen, 10 gelogde dagen en 5 wegingen.
/// Dagen met minder dan 800 kcal gelden als onvolledig gelogd en tellen niet mee.
EnergyEstimate? estimateEnergy(Map<String, double> kcalPerDay, Map<String, double> weights, List<String> days) {
  if (days.length < 14) return null;
  final logged = [
    for (final d in days)
      if ((kcalPerDay[d] ?? 0) >= 800) kcalPerDay[d]!,
  ];
  // Helling van het gewicht via kleinste kwadraten: zonder de vertraging van een voortschrijdend gemiddelde
  final xs = <double>[], ys = <double>[];
  for (final (i, d) in days.indexed) {
    if (weights[d] case final w?) {
      xs.add(i.toDouble());
      ys.add(w);
    }
  }
  if (logged.length < 10 || xs.length < 5 || xs.last - xs.first < 13) return null;
  final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
  var sxy = 0.0, sxx = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
  }
  final slope = sxy / sxx; // kg per dag
  final avg = logged.reduce((a, b) => a + b) / logged.length;
  return EnergyEstimate(tdee: avg - slope * 7700, avgIntake: avg, trendChange: slope * days.length, days: days.length);
}

/// Reeks dagelijks loggen: hoeveel dagen op rij tot vandaag (of tot gisteren, als je vandaag nog niets logde),
/// en de langste reeks ooit. [days] zijn dagen in de vorm jjjj-mm-dd.
({int current, int longest}) loggingStreak(Set<String> days, DateTime today) {
  String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  var d = DateTime(today.year, today.month, today.day);
  if (!days.contains(key(d))) d = DateTime(d.year, d.month, d.day - 1);
  var current = 0;
  while (days.contains(key(d))) {
    current++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  var longest = 0, run = 0;
  DateTime? prev;
  for (final k in days.toList()..sort()) {
    final x = DateTime.parse(k);
    run = (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == x) ? run + 1 : 1;
    longest = math.max(longest, run);
    prev = x;
  }
  return (current: current, longest: longest);
}

/// Plan om van [current] naar [target] kg te gaan in [months] maanden, bij een verbruik van [tdee] kcal per dag.
class WeightPlan {
  WeightPlan._(this.weeks, this.ratePerWeek, this.dailyChange, this.dailyKcal, this.warnings, {this.unsafe = false});

  final double weeks;

  /// kg per week (negatief = afvallen).
  final double ratePerWeek;

  /// Tekort (negatief) of overschot per dag in kcal.
  final double dailyChange;

  /// Wat je per dag mag eten.
  final double dailyKcal;
  final List<String> warnings;

  /// Te weinig eten of een ongezond doelgewicht: niet als plan aanbieden.
  final bool unsafe;

  factory WeightPlan.of({
    required double current,
    required double target,
    required double months,
    required double tdee,
    required double bmr,
    required bool male,
    double? heightCm,
  }) {
    final weeks = months * 52 / 12;
    final rate = (target - current) / weeks;
    final change = rate * kcalPerKg / 7;
    final kcal = tdee + change;
    final minimum = male ? 1500.0 : 1200.0;
    final bmi = heightCm == null || heightCm <= 0 ? null : target / ((heightCm / 100) * (heightCm / 100));
    final underweight = bmi != null && bmi < 18.5 && target < current;
    return WeightPlan._(weeks, rate, change, kcal, unsafe: kcal < minimum || underweight, [
      if (underweight)
        tr(
          'A goal of ${target.round()} kg gives a BMI of ${bmi.toStringAsFixed(1)}, which is underweight. Choose a higher goal.',
          'Een doel van ${target.round()} kg geeft een BMI van ${bmi.toStringAsFixed(1).dec}: dat is ondergewicht. Kies een hoger doel.',
        ),
      if (rate < 0 && -rate > current * 0.01)
        tr(
          'More than 1% of your weight per week is hard to sustain and costs muscle. Better take more time.',
          'Meer dan 1% van je gewicht per week is zwaar vol te houden en kost spiermassa. Neem liever meer tijd.',
        ),
      if (rate > 0.5)
        tr(
          'Gaining more than half a kilo per week is mostly fat. Better take more time.',
          'Meer dan een halve kilo per week aankomen is vooral vet. Neem liever meer tijd.',
        ),
      if (kcal < minimum)
        tr(
          'Less than ${minimum.round()} kcal per day is too little to get enough nutrients.',
          'Minder dan ${minimum.round()} kcal per dag is te weinig om genoeg voedingsstoffen binnen te krijgen.',
        )
      else if (kcal < bmr)
        tr(
          'That is less than your body burns at rest (${bmr.round()} kcal).',
          'Dat is minder dan je lichaam in rust verbruikt (${bmr.round()} kcal).',
        ),
    ]);
  }
}
