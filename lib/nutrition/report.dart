/// Weekrapport: je gemiddelde voedingsscore tegenover de week ervoor, je beste en zwakste voedingsstoffen en een
/// tip voor de komende week.
library;

import '../data/food.dart';
import 'health.dart';
import 'health.dart' as h show energyCase;
import 'nutrients.dart';
import 'targets.dart';

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

/// Koolhydraten, suiker en bloedsuiker van de week, voor wie "Let op suiker" aan heeft. Gemiddelden over de
/// volledig gelogde dagen ([days]).
class SugarWeek {
  const SugarWeek({
    required this.days,
    required this.carbs,
    this.carbsGoal,
    this.carbDaysOver = 0,
    required this.sugars,
    this.freeSugars,
    this.freeSugarsMax,
    this.freeSugarDaysOver = 0,
    this.glucose,
    this.glucoseCount = 0,
  });
  final int days;

  /// Gemiddeld per dag (g); [carbsGoal] = je gemiddelde koolhydratendoel.
  final double carbs, sugars;
  final double? carbsGoal, freeSugars, freeSugarsMax;

  /// Dagen boven je koolhydratendoel (+10%) en boven je maximum vrije suiker.
  final int carbDaysOver, freeSugarDaysOver;

  /// Gemiddelde bloedsuiker (mmol/L) over [glucoseCount] metingen in de week.
  final double? glucose;
  final int glucoseCount;
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
    this.goals = const {},
    this.weightTrend,
    this.plan = Goal.maintain,
    this.sugar,
    this.upperShare = const {},
    this.topFoods = const [],
  });

  /// Gemiddelde inname tegenover de gemiddelde veilige bovengrens, per stof met een bovengrens (1,3 = 30% erboven).
  final Map<String, double> upperShare;

  /// De producten met de meeste energie deze week, als gewone namen (zonder merk; eigen producten en recepten zonder
  /// hun naam). Voor de wekelijkse coach.
  final List<String> topFoods;

  /// Gemiddeld dagdoel per stof (in de eenheid van de stof), om bij elke stof het doel te tonen.
  final Map<String, double> goals;

  /// Gewichtsverloop over deze en de vorige week (zie [WeightTrend]), en of je wil afvallen, behouden of aankomen.
  final WeightTrend? weightTrend;
  final Goal plan;

  /// Alleen bij "Let op suiker".
  final SugarWeek? sugar;

  /// Energie samen gelezen met je gewicht, met dezelfde marge als [energyOff].
  EnergyCase get energyCase => kcalAvg == null || kcalGoal == null
      ? EnergyCase.onTarget
      : h.energyCase(eaten: kcalAvg!, goal: kcalGoal!, trend: weightTrend, plan: plan, margin: 1 - reportEnergyLow);

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

/// Voedingsstoffen in de heatmap van het uitgebreide jaaroverzicht (Pro): vezels en de vitaminen en mineralen waar
/// het vaakst iets aan ontbreekt.
const recapHeatmapKeys = ['fiber', 'vit_d', 'vit_c', 'b12', 'b9', 'calcium', 'iron', 'magnesium', 'potassium', 'zinc', 'iodine', 'selenium'];

enum RecapRecordKind { bestScore, mostProtein, mostFiber, mostFoods, busiestMonth }

/// Een record uit je jaar: de waarde en de dag (of bij [RecapRecordKind.busiestMonth] de eerste van die maand).
class RecapRecord {
  const RecapRecord(this.kind, this.value, this.day);
  final RecapRecordKind kind;
  final double value;
  final DateTime day;
}

/// Extra's van het jaaroverzicht voor wie Pro heeft. Los van [Recap], zodat het gratis overzicht niet verandert.
class RecapExtras {
  const RecapExtras({required this.monthNutrients, required this.topFoods, required this.records});

  /// Per voedingsstof uit [recapHeatmapKeys]: 12 waarden (januari tot december), het gemiddelde deel van je doel
  /// op de gelogde dagen van die maand (hoogstens 1,5), of null als je die maand niets logde.
  final Map<String, List<double?>> monthNutrients;

  /// (naam, aantal keer gelogd), hoogstens 10.
  final List<(String, int)> topFoods;
  final List<RecapRecord> records;
}
