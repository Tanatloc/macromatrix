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

class WeeklyReport {
  const WeeklyReport({
    required this.monday,
    required this.score,
    required this.days,
    this.prevScore,
    required this.best,
    required this.worst,
    this.tip,
    this.health,
    this.prevHealthScore,
  });

  final DateTime monday;
  final int score, days;
  final int? prevScore;

  /// (stof, gemiddeld deel van het doel per gelogde dag).
  final List<(Nutrient, double)> best, worst;
  final WeeklyTip? tip;

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
}
