/// Weekrapport: je gemiddelde voedingsscore tegenover de week ervoor, je beste en zwakste voedingsstoffen en een
/// tip voor de komende week.
library;

import '../data/food.dart';
import 'health.dart';
import 'nutrients.dart';

class WeeklyTip {
  const WeeklyTip(this.nutrient, this.food, this.grams, this.amountLabel, this.fraction);
  final Nutrient nutrient;
  final Food food;
  final double grams;

  /// Bv. "1 egg (50 g)" of "100 g".
  final String amountLabel;

  /// Deel van je dagdoel in die hoeveelheid.
  final double fraction;
}

/// Energie telt als duidelijk te laag of te hoog buiten deze delen van je doel (gemiddeld over de week).
const reportEnergyLow = 0.85, reportEnergyHigh = 1.15;

/// Eiwit telt als duidelijk te laag onder dit deel van je doel.
const reportProteinLow = 0.8;

/// Natrium in een portie (mg) waarboven een product nooit als tip komt: dat is al ongeveer 1 g zout.
const tipSodiumMax = 400.0;

/// Wie al op of boven zijn natriumdoel zit, krijgt alleen producten met hooguit zoveel natrium per portie (mg).
const tipSodiumMaxWhenHigh = 120.0;

/// Te zout voor een tip: veel natrium in de portie, of al genoeg zout gegeten ([sodiumFraction] = gemiddeld deel
/// van je natriumdoel) en toch merkbaar natrium in de portie.
bool tooSaltyForTip(double sodiumInPortion, double? sodiumFraction) =>
    sodiumInPortion > tipSodiumMax || ((sodiumFraction ?? 0) >= 1 && sodiumInPortion > tipSodiumMaxWhenHigh);

/// Wat aandacht verdient: eerst een duidelijk probleem met energie of eiwit, dan de zwakste vitaminen en mineralen.
/// [avg] = gemiddeld deel van het doel per stof; [micros] = de vitaminen en mineralen van laag naar hoog.
List<MapEntry<String, double>> attentionOrder(Map<String, double> avg, List<MapEntry<String, double>> micros, {int take = 3}) {
  final energy = avg['energy'];
  final protein = avg['protein'];
  return [
    if (energy != null && (energy < reportEnergyLow || energy > reportEnergyHigh)) MapEntry('energy', energy),
    if (protein != null && protein < reportProteinLow) MapEntry('protein', protein),
    ...micros,
  ].take(take).toList();
}

/// Beweging in de week van het rapport.
class WeeklyExercise {
  const WeeklyExercise({this.sessions = 0, this.minutes = 0, this.kcal = 0});
  final int sessions;
  final double minutes, kcal;
}

class WeeklyReport {
  const WeeklyReport({
    required this.monday,
    required this.score,
    required this.days,
    this.partialDays = 0,
    this.prevScore,
    required this.best,
    required this.worst,
    this.tip,
    this.health,
    this.prevHealthScore,
    this.avg = const {},
    this.prevAvg = const {},
    this.kcalAvg,
    this.kcalGoal,
    this.prevKcalAvg,
    this.weightStart,
    this.weightEnd,
    this.exercise = const WeeklyExercise(),
    this.notes = const {},
  });

  final DateTime monday;

  /// [days] = volledig gelogde dagen waarop score en gemiddelden steunen (zie [isFullDay]; vandaag telt nog niet mee).
  final int score, days;

  /// Dagen met iets gelogd die niet meetellen: te weinig gelogd of vandaag (nog bezig).
  final int partialDays;
  final int? prevScore;

  /// (stof, gemiddeld deel van het doel per volledig gelogde dag).
  final List<(Nutrient, double)> best, worst;
  final WeeklyTip? tip;

  /// Gemiddeld deel van het doel per stof (ook 'energy' en 'protein'), deze en vorige week.
  final Map<String, double> avg, prevAvg;

  /// Gemiddelde energie per volledige dag en je gemiddelde energiedoel (kcal), en vorige week.
  final double? kcalAvg, kcalGoal, prevKcalAvg;

  /// Eerste en laatste gewicht van de week (kg), als je je woog.
  final double? weightStart, weightEnd;
  final WeeklyExercise exercise;

  /// Dagnotities (jjjj-mm-dd → tekst), alleen dagen met een notitie.
  final Map<String, String> notes;

  /// Gewichtsverandering over de week (kg), als je je minstens twee keer woog.
  double? get weightChange => weightStart == null || weightEnd == null ? null : weightEnd! - weightStart!;

  /// Gemiddeld tekort (negatief) of overschot (positief) tegenover je energiedoel, in kcal per dag.
  double? get energyBalance => kcalAvg == null || kcalGoal == null || kcalGoal! <= 0 ? null : kcalAvg! - kcalGoal!;

  /// Energie duidelijk te laag (-1), te hoog (1) of in orde (0).
  int get energyOff {
    final f = avg['energy'];
    if (f == null) return 0;
    return f < reportEnergyLow ? -1 : (f > reportEnergyHigh ? 1 : 0);
  }

  /// Verschil in deel van het doel tegenover vorige week (0,12 = 12 procentpunt meer), of null.
  double? changeFor(String key) {
    final now = avg[key], prev = prevAvg[key];
    return now == null || prev == null ? null : now - prev;
  }

  int? get kcalChange => kcalAvg == null || prevKcalAvg == null ? null : (kcalAvg! - prevKcalAvg!).round();

  /// Gezondheidscheck, of null bij minder dan [healthMinDays] volledig gelogde dagen.
  final HealthCheck? health;
  final int? prevHealthScore;

  int? get healthChange => health == null || prevHealthScore == null ? null : health!.score - prevHealthScore!;

  int? get change => prevScore == null ? null : score - prevScore!;
}

/// Maand- of jaaroverzicht.
class Recap {
  const Recap({
    required this.from,
    required this.to,
    required this.year,
    required this.daysLogged,
    required this.daysInPeriod,
    required this.distinctFoods,
    required this.entries,
    required this.topFoods,
    required this.avgScore,
    this.bestDay,
    this.bestMonth,
    required this.longestStreak,
    required this.xp,
    required this.avgKcal,
    this.topNutrient,
    this.favouriteBreakfast,
    this.weakNutrient,
    this.dayScores = const {},
    this.dayKcal = const {},
    this.kcalGoal = 0,
    this.split,
    this.avgProtein = 0,
    this.previous,
  });

  final DateTime from, to;
  final bool year;
  final int daysLogged, daysInPeriod, distinctFoods, entries, avgScore, longestStreak, xp, avgKcal;

  /// (naam, aantal keer gelogd)
  final List<(String, int)> topFoods;
  final (DateTime, int)? bestDay;

  /// Alleen bij een jaar: (maand, gemiddelde score)
  final (DateTime, int)? bestMonth;

  /// Stof die je het best haalde (naam, gemiddeld deel van het doel).
  final (Nutrient, double)? topNutrient;
  final String? favouriteBreakfast;

  /// Stof die je het minst haalde (naam, gemiddeld deel van het doel): iets om aan te werken.
  final (Nutrient, double)? weakNutrient;

  /// Per gelogde dag (jjjj-mm-dd): Voedingsscore en kcal.
  final Map<String, int> dayScores;
  final Map<String, double> dayKcal;

  /// Gemiddeld energiedoel over de gelogde dagen.
  final int kcalGoal;

  /// Gemiddelde verdeling van de energie over eiwit, koolhydraten en vet (samen 1).
  final (double, double, double)? split;
  final int avgProtein;

  /// Dezelfde cijfers voor de vorige periode (vorige maand of vorig jaar), om te vergelijken.
  final Recap? previous;
}
