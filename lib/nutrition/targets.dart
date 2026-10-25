/// Persoonlijk profiel en dagelijkse richtwaarden.
///
/// Bron micronutriënten: EFSA Dietary Reference Values voor gezonde volwassenen (PRI of AI, en de
/// Tolerable Upper Intake Level als bovengrens). Essentiële aminozuren: WHO/FAO/UNU 2007 (mg per kg
/// lichaamsgewicht). Energie: Mifflin-St Jeor x activiteitsfactor. Geen medisch advies.
library;

import 'dart:math' as math;

import '../day_clock.dart';
import '../i18n.dart';

enum Sex {
  male('Male', 'Man'),
  female('Female', 'Vrouw');

  const Sex(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

enum Activity {
  sedentary(1.2, ('Sedentary', 'Zittend'), ('Little or no exercise', 'Weinig of geen beweging')),
  light(1.375, ('Lightly active', 'Licht actief'), ('Exercise 1 to 3 times a week', '1 à 3 keer per week sporten')),
  moderate(1.55, ('Moderately active', 'Matig actief'), ('Exercise 3 to 5 times a week', '3 à 5 keer per week sporten')),
  active(1.725, ('Active', 'Actief'), ('Exercise 6 to 7 times a week', '6 à 7 keer per week sporten')),
  veryActive(
    1.9,
    ('Very active', 'Zeer actief'),
    ('Heavy physical work or intense daily training', 'Zwaar fysiek werk of dagelijks intensief trainen'),
  );

  const Activity(this.factor, this._label, this._description);
  final double factor;
  final (String, String) _label, _description;
  String get label => tr(_label.$1, _label.$2);
  String get description => tr(_description.$1, _description.$2);
}

enum Goal {
  lose(-0.5, 'Lose', 'Afvallen'),
  maintain(0, 'Maintain', 'Behouden'),
  gain(0.25, 'Gain', 'Aankomen');

  const Goal(this.defaultRate, this.en, this.nl);

  /// Standaardtempo in kg per week.
  final double defaultRate;
  final String en, nl;
  String get label => tr(en, nl);
}

/// Energie in 1 kg lichaamsgewicht (vet + wat water en spier), gebruikelijke benadering.
const kcalPerKg = 7700;

class Profile {
  const Profile({
    this.sex = Sex.male,
    this.birthYear = 1995,
    this.weightKg = 75,
    this.heightCm = 178,
    this.activity = Activity.light,
    this.goal = Goal.maintain,
    this.proteinPct = 20,
    this.carbsPct = 50,
    this.fatPct = 30,
    this.energyOverride,
    this.rateKgPerWeek,
    this.targetWeightKg,
    this.targetDate,
  });

  final Sex sex;
  final int birthYear;
  final double weightKg;
  final double heightCm;
  final Activity activity;
  final Goal goal;

  /// Verdeling van de energie over de macro's, in procent (samen 100).
  final double proteinPct;
  final double carbsPct;
  final double fatPct;

  /// Eigen energiedoel in kcal; null = berekenen uit het profiel.
  final double? energyOverride;

  /// Gewenst tempo in kg per week (negatief = afvallen); null = standaard van het doel.
  final double? rateKgPerWeek;

  /// Doelgewicht met een datum: het tempo volgt dan vanzelf uit wat er nog rest. null = geen plan.
  final double? targetWeightKg;
  final DateTime? targetDate;

  bool get hasPlan => targetWeightKg != null && targetDate != null && goal != Goal.maintain;

  /// Hoogste tempo dat de app instelt (kg per week), afvallen en aankomen.
  static const maxLoss = 1.0, maxGain = 0.5;

  /// Tempo dat het plan vandaag vraagt: wat er nog rest gedeeld door de weken tot de datum, zonder plafond.
  /// 0 als het doel bereikt is. null zonder plan.
  double? get planRate => planRateOn(logicalNow());

  /// Tempo dat het plan op [day] vroeg, gerekend vanaf die dag tot de datum: zo verandert het doel van een vroegere
  /// dag niet meer naarmate de datum dichterbij komt. Is de datum op [day] al voorbij, dan het standaardtempo van het
  /// doel (en niet het hoogste tempo) tot je een nieuwe datum kiest.
  double? planRateOn(DateTime day) {
    if (!hasPlan) return null;
    final left = targetWeightKg! - weightKg;
    if (goal == Goal.lose ? left > -0.05 : left < 0.05) return 0;
    final days = daysBetween(day, targetDate!);
    if (days <= 0) return rateKgPerWeek ?? goal.defaultRate;
    return left / (days < 7 ? 1 : days / 7);
  }

  /// Tempo dat geldt: bij "behouden" altijd 0; met een plan uit het plan, begrensd tot een gezond tempo.
  double get rate => rateOn(logicalNow());

  /// Zoals [rate], voor het plan zoals het op [day] gold.
  double rateOn(DateTime day) {
    if (goal == Goal.maintain) return 0;
    final plan = planRateOn(day);
    if (plan != null) return goal == Goal.lose ? plan.clamp(-maxLoss, 0) : plan.clamp(0, maxGain);
    return rateKgPerWeek ?? goal.defaultRate;
  }

  /// Dagelijks overschot of tekort voor het gekozen tempo.
  double get goalKcal => goalKcalOn(logicalNow());

  /// Zoals [goalKcal], voor [day].
  double goalKcalOn(DateTime day) => rateOn(day) * kcalPerKg / 7;

  int ageIn(int year) => year - birthYear;

  Profile copyWith({
    Sex? sex,
    int? birthYear,
    double? weightKg,
    double? heightCm,
    Activity? activity,
    Goal? goal,
    double? proteinPct,
    double? carbsPct,
    double? fatPct,
    double? Function()? energyOverride,
    double? Function()? rateKgPerWeek,
    double? Function()? targetWeightKg,
    DateTime? Function()? targetDate,
  }) => Profile(
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    weightKg: weightKg ?? this.weightKg,
    heightCm: heightCm ?? this.heightCm,
    activity: activity ?? this.activity,
    goal: goal ?? this.goal,
    proteinPct: proteinPct ?? this.proteinPct,
    carbsPct: carbsPct ?? this.carbsPct,
    fatPct: fatPct ?? this.fatPct,
    energyOverride: energyOverride != null ? energyOverride() : this.energyOverride,
    rateKgPerWeek: rateKgPerWeek != null ? rateKgPerWeek() : this.rateKgPerWeek,
    targetWeightKg: targetWeightKg != null ? targetWeightKg() : this.targetWeightKg,
    targetDate: targetDate != null ? targetDate() : this.targetDate,
  );

  Map<String, Object?> toJson() => {
    'sex': sex.name,
    'birthYear': birthYear,
    'weightKg': weightKg,
    'heightCm': heightCm,
    'activity': activity.name,
    'goal': goal.name,
    'proteinPct': proteinPct,
    'carbsPct': carbsPct,
    'fatPct': fatPct,
    'energyOverride': energyOverride,
    'rateKgPerWeek': rateKgPerWeek,
    'targetWeightKg': targetWeightKg,
    'targetDate': targetDate == null
        ? null
        : '${targetDate!.year}-${targetDate!.month.toString().padLeft(2, '0')}-${targetDate!.day.toString().padLeft(2, '0')}',
  };

  factory Profile.fromJson(Map<String, Object?> j) {
    const d = Profile();
    double num_(String k, double fallback) => (j[k] as num?)?.toDouble() ?? fallback;
    return Profile(
      sex: Sex.values.asNameMap()[j['sex']] ?? d.sex,
      birthYear: (j['birthYear'] as num?)?.toInt() ?? d.birthYear,
      weightKg: num_('weightKg', d.weightKg),
      heightCm: num_('heightCm', d.heightCm),
      activity: Activity.values.asNameMap()[j['activity']] ?? d.activity,
      goal: Goal.values.asNameMap()[j['goal']] ?? d.goal,
      proteinPct: num_('proteinPct', d.proteinPct),
      carbsPct: num_('carbsPct', d.carbsPct),
      fatPct: num_('fatPct', d.fatPct),
      energyOverride: (j['energyOverride'] as num?)?.toDouble(),
      rateKgPerWeek: (j['rateKgPerWeek'] as num?)?.toDouble(),
      targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
      targetDate: DateTime.tryParse(j['targetDate'] as String? ?? ''),
    );
  }
}

/// Richtwaarde voor één voedingsstof.
class Target {
  const Target({this.goal, this.upper, this.about = false});

  /// Hoeveel je best haalt per dag (aanbevolen inname). null = geen aanbeveling.
  final double? goal;

  /// Hoeveel je best niet overschrijdt (bovengrens of limiet). null = geen bovengrens.
  final double? upper;

  /// Een doel om ongeveer te halen (energie, koolhydraten, vet): ruim erboven is net zo goed naast het doel als eronder.
  final bool about;

  /// Alleen een limiet (bv. natrium, verzadigd vet): minder is beter.
  bool get isLimit => goal == null && upper != null;
}

/// Basaal metabolisme volgens Mifflin-St Jeor, in kcal per dag.
double bmr(Profile p, int age) => 10 * p.weightKg + 6.25 * p.heightCm - 5 * age + (p.sex == Sex.male ? 5 : -161);

/// Verbruik volgens de formule: ruststofwisseling × activiteit.
double formulaTdee(Profile p, int year) => bmr(p, p.ageIn(year)) * p.activity.factor;

/// Beweging die je activiteitsniveau al inrekent (de factor boven zittend), in kcal per dag. Alleen verbranding
/// daarboven komt bij je doel, zodat een training niet dubbel telt.
double exerciseInActivity(Profile p, int year) => bmr(p, p.ageIn(year)) * (p.activity.factor - Activity.sedentary.factor);

/// Hoeveel kg per week je ongeveer verandert als je [kcal] per dag eet bij een verbruik van [tdee] (negatief = afvallen).
double impliedRate(double kcal, double tdee) => (kcal - tdee) * 7 / kcalPerKg;

/// Minimum om genoeg voedingsstoffen binnen te krijgen (kcal per dag): 1500 voor mannen, 1200 voor vrouwen. Dezelfde
/// grens als bij het kiezen van een doelgewicht (`WeightPlan.of`).
double minimumKcal(Sex sex) => sex == Sex.male ? 1500 : 1200;

/// Bodem onder een berekend energiedoel bij afvallen: minstens je ruststofwisseling en minstens [minimumKcal]. Nooit
/// boven je onderhoud [tdee]: wie minder verbruikt dan die grens, krijgt zijn onderhoud en geen overschot.
double energyFloor(Profile p, int year, {double? tdee}) {
  final maintain = (tdee ?? formulaTdee(p, year)).roundToDouble();
  return math.max(0, math.min(math.max(bmr(p, p.ageIn(year)), minimumKcal(p.sex)).roundToDouble(), maintain));
}

/// Energiedoel zonder bodem (verbruik plus het tekort of overschot van je doel op [day]).
double _rawEnergy(Profile p, int year, double? tdee, DateTime? day) =>
    ((tdee ?? formulaTdee(p, year)) + p.goalKcalOn(day ?? logicalNow())).roundToDouble();

/// Energiebehoefte per dag inclusief activiteit en doel. [tdee] = verbruik uit een andere bron (adaptief). [day] = de
/// dag waarvoor het doel geldt (standaard vandaag): het tempo van een plan met een datum hangt daarvan af. Een
/// berekend doel zakt nooit onder [energyFloor]; een eigen doel blijft zoals je het typte.
double energyTarget(Profile p, int year, {double? tdee, DateTime? day}) =>
    p.energyOverride ?? math.max(_rawEnergy(p, year, tdee, day), energyFloor(p, year, tdee: tdee));

/// Houdt de bodem ([energyFloor]) het berekende doel op [day] tegen? Dan geeft het scherm uitleg.
bool energyFloored(Profile p, int year, {double? tdee, DateTime? day}) =>
    p.energyOverride == null && _rawEnergy(p, year, tdee, day) < energyFloor(p, year, tdee: tdee);

/// Minimum eiwit per kg lichaamsgewicht (EFSA PRI voor volwassenen).
const proteinMinPerKg = 0.83;

/// Energie waarop het eiwitdoel rust: je onderhoud, dus zonder het tekort of overschot van je doel, plus beweging.
/// Ook met een eigen energiedoel blijft dat je berekende onderhoud: zo daalt eiwit niet mee als je een lager doel
/// typt, net zoals bij afvallen met een tempo.
double maintenanceKcal(Profile p, int year, {double extraKcal = 0, double? tdee}) => (tdee ?? formulaTdee(p, year)).roundToDouble() + extraKcal;

/// Macro's in gram (eiwit, koolhydraten, vet) voor een dag met [kcal] als energiedoel.
///
/// Eiwit rekenen we eerst, op de onderhoudsenergie [maintenance]: afvallen verlaagt je eiwitdoel dus niet, want net
/// dan heb je eiwit nodig om je spieren te behouden. Nooit onder 0,83 g per kg. Wat overblijft van [kcal] gaat naar
/// koolhydraten en vet in hun onderlinge verhouding: die vangen het tekort of overschot op, en samen komen de macro's
/// zo precies uit op het energiedoel. Met een eigen eiwitdoel [proteinGoal] telt dat getal, en verdelen
/// koolhydraten en vet wat daarna overblijft.
(double, double, double) macroGrams(Profile p, double kcal, double maintenance, {double? proteinGoal}) {
  final cap = math.max(0.0, kcal) / 4;
  final protein = proteinGoal != null
      ? math.min(math.max(0.0, proteinGoal), cap)
      : math.min(math.max(maintenance * p.proteinPct / 100 / 4, proteinMinPerKg * p.weightKg), cap);
  final rest = math.max(0.0, kcal - protein * 4);
  final cf = p.carbsPct + p.fatPct;
  if (cf <= 0) return (protein, 0, 0);
  return (protein, rest * p.carbsPct / cf / 4, rest * p.fatPct / cf / 9);
}

/// Omgekeerd van [macroGrams]: welk percentage voor [key] (protein, carbs of fat) geeft [grams] gram. Eiwit is een
/// deel van de onderhoudsenergie; koolhydraten en vet een deel van wat na eiwit overblijft (geschaald naar procent).
double macroPctForGrams(String key, double grams, Profile p, double kcal, double maintenance, {double? proteinGoal}) {
  if (key == 'protein') return maintenance <= 0 ? p.proteinPct : grams * 4 / maintenance * 100;
  final rest = kcal - macroGrams(p, kcal, maintenance, proteinGoal: proteinGoal).$1 * 4;
  if (rest <= 0) return 0;
  return grams * (key == 'fat' ? 9 : 4) / rest * (100 - p.proteinPct);
}

/// Aandeel van een macro in het energiedoel, uit de echte grammen (0..1). Zo kloppen de procenten altijd met de
/// grammen ernaast, ook met een eigen eiwitdoel.
double macroShare(String key, double grams, double kcal) => kcal <= 0 ? 0 : grams * (key == 'fat' ? 9 : 4) / kcal;

/// Gemiddelde richtwaarden over een reeks dagen, voor gemiddelden over een week of maand: elke dag telt met het doel
/// dat toen gold.
Map<String, Target> averageTargets(Iterable<Map<String, Target>> days) {
  final list = days.toList();
  if (list.isEmpty) return const {};
  if (list.length == 1) return list.first;
  final out = <String, Target>{};
  for (final k in {for (final d in list) ...d.keys}) {
    final ts = [for (final d in list) ?d[k]];
    final goals = [for (final t in ts) ?t.goal];
    final uppers = [for (final t in ts) ?t.upper];
    double? avg(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    out[k] = Target(goal: avg(goals), upper: avg(uppers), about: ts.last.about);
  }
  return out;
}

/// Doel voor een kop boven een week of maand: één getal als het doel niet veranderde, anders het doel van nu met
/// het gemiddelde van de dagen ervoor ("2.000 (eerder 1.495)"). [goals] in volgorde, de laatste is nu.
String goalNowEarlier(List<double> goals, String Function(double) fmt) {
  if (goals.isEmpty) return '–';
  final now = goals.last;
  final earlier = goals.sublist(0, goals.length - 1).where((g) => fmt(g) != fmt(now)).toList();
  if (earlier.isEmpty) return fmt(now);
  final before = goals.sublist(0, goals.length - 1);
  return tr(
    '${fmt(now)} (earlier ${fmt(before.reduce((a, b) => a + b) / before.length)})',
    '${fmt(now)} (eerder ${fmt(before.reduce((a, b) => a + b) / before.length)})',
  );
}

/// Veilige bovengrens voor voorgevormd retinol in µg per dag (EFSA/SCF 2002), naar leeftijd.
double retinolUpperLimit(int age) => switch (age) {
  < 4 => 800,
  < 7 => 1100,
  < 11 => 1500,
  < 15 => 2000,
  < 18 => 2600,
  _ => 3000,
};

/// Richtwaarden voor een profiel. [extraKcal] = verbrande energie door beweging die bij het doel komt.
///
/// [proteinGoal] = een eigen eiwitdoel: koolhydraten en vet verdelen dan wat na dat eiwit overblijft.
///
/// [day] = de dag waarvoor de doelen gelden (standaard vandaag), zie [energyTarget].
Map<String, Target> targetsFor(Profile p, {required int year, double extraKcal = 0, double? tdee, double? proteinGoal, DateTime? day}) {
  final age = p.ageIn(year);
  final male = p.sex == Sex.male;
  // Nooit negatief: ook de doelen die van energie afhangen (eiwit, vetten, B1, B3) blijven zo 0 of meer
  final base = math.max(0.0, energyTarget(p, year, tdee: tdee, day: day));
  final kcal = base + math.max(0.0, extraKcal);
  // Energieafhankelijke vitaminen (B1, B3) rekenen we op je basisdoel, niet op de extra van een training:
  // je behoefte stijgt niet merkbaar door één work-out, en zo schieten ze niet boven de veilige grens.
  final mj = base * 4.184 / 1000;
  final kg = p.weightKg;
  // Essentiële aminozuren: mg per kg lichaamsgewicht -> g per dag
  Target aa(double mgPerKg) => Target(goal: mgPerKg * kg / 1000);

  final (protein, carbs, fat) = macroGrams(
    p,
    kcal,
    maintenanceKcal(p, year, extraKcal: extraKcal, tdee: tdee),
    proteinGoal: proteinGoal,
  );

  return {
    'energy': Target(goal: kcal, about: true),
    'protein': Target(goal: protein),
    'carbs': Target(goal: carbs, about: true),
    'fat': Target(goal: fat, about: true),
    'fiber': const Target(goal: 25),
    'sfa': Target(upper: kcal * 0.10 / 9),
    // Vrije suikers (WHO): minder dan 10% van de energie. Alle suikers samen (ook uit fruit en melk) hebben geen maximum.
    'free_sugars': Target(upper: kcal * 0.10 / 4),
    'trans': Target(upper: kcal * 0.01 / 9),
    'la': Target(goal: kcal * 0.04 / 9),
    'ala': Target(goal: kcal * 0.005 / 9),
    'epa_dha': const Target(goal: 250),
    'water': Target(goal: male ? 2500 : 2000),
    'caffeine': const Target(upper: 400),

    // Vitaminen
    'vit_a': Target(goal: male ? 750 : 650),
    // Voorgevormd retinol: alleen een bovengrens (EFSA/SCF 2002: 3000 µg per dag voor volwassenen, ook bij zwangerschap;
    // lager voor jongeren). Niet op het totaal (RE): dan zou 100 g wortel al rood zijn.
    'retinol': Target(upper: retinolUpperLimit(age)),
    'vit_c': Target(goal: male ? 110 : 95),
    'vit_d': const Target(goal: 15, upper: 100),
    'vit_e': Target(goal: male ? 13 : 11, upper: 300),
    'vit_k': const Target(goal: 70),
    'b1': Target(goal: 0.1 * mj),
    'b2': const Target(goal: 1.6),
    'b3': Target(goal: 1.6 * mj),
    'b5': const Target(goal: 5),
    'b6': Target(goal: male ? 1.7 : 1.6, upper: 12),
    'b7': const Target(goal: 40),
    'b9': const Target(goal: 330),
    'b12': const Target(goal: 4),
    'choline': const Target(goal: 400),

    // Mineralen
    'calcium': Target(goal: age < 25 ? 1000 : 950, upper: 2500),
    'chloride': const Target(goal: 3100),
    'copper': Target(goal: male ? 1.6 : 1.3, upper: 5),
    'fluoride': Target(goal: male ? 3.4 : 2.9, upper: 7),
    'iodine': const Target(goal: 150, upper: 600),
    // Vrouwen na de menopauze hebben minder ijzer nodig; 50 jaar als benadering
    'iron': Target(goal: male || age >= 50 ? 11 : 16),
    'magnesium': Target(goal: male ? 350 : 300),
    'manganese': const Target(goal: 3),
    'molybdenum': const Target(goal: 65, upper: 600),
    'phosphorus': const Target(goal: 550),
    'potassium': const Target(goal: 3500),
    'selenium': const Target(goal: 70, upper: 255),
    'sodium': const Target(upper: 2000),
    // Zink hangt af van fytaat in de voeding; dit is de waarde bij een gemiddelde inname (600 mg)
    'zinc': Target(goal: male ? 11.7 : 9.3, upper: 25),

    // Essentiële aminozuren (WHO/FAO/UNU 2007)
    'histidine': aa(10),
    'isoleucine': aa(20),
    'leucine': aa(39),
    'lysine': aa(30),
    'met_cys': aa(15),
    'phe_tyr': aa(25),
    'threonine': aa(15),
    'tryptophan': aa(4),
    'valine': aa(26),
  };
}

/// Voedingsstijl: een vertrekpunt voor de verdeling van de macro's (eiwit, koolhydraten, vet in %).
enum DietPreset {
  balanced('Balanced', 'Gebalanceerd', 20, 50, 30),
  // Duidelijk meer eiwit dan gebalanceerd: 30% van de onderhoudsenergie is voor de meesten 1,6 à 2,2 g per kg
  highProtein('High protein', 'Eiwitrijk', 30, 40, 30),
  lowCarb('Low carb', 'Koolhydraatarm', 30, 20, 50),
  keto('Keto', 'Keto', 25, 5, 70),
  mediterranean('Mediterranean', 'Mediterraan', 18, 45, 37),
  endurance('Endurance', 'Duursport', 18, 60, 22);

  const DietPreset(this.en, this.nl, this.protein, this.carbs, this.fat);
  final String en, nl;
  String get label => tr(en, nl);
  final double protein;
  final double carbs;
  final double fat;
}

/// Eigen doelen en instellingen bovenop het profiel.
class TargetSettings {
  const TargetSettings({
    this.overrides = const {},
    this.schedule = const {},
    this.addExercise = true,
    this.adaptiveEnergy = false,
    this.trackWater = true,
  });

  /// Eigen richtwaarde per voedingsstof (vervangt EFSA).
  final Map<String, Target> overrides;

  /// Macroverdeling per weekdag (1 = maandag ... 7 = zondag): (eiwit, koolhydraten, vet) in %.
  final Map<int, (double, double, double)> schedule;

  /// Verbrande kcal door beweging bij het energiedoel optellen.
  final bool addExercise;

  /// Verbruik schatten uit gewicht en logboek in plaats van uit de formule (zodra er genoeg gegevens zijn).
  final bool adaptiveEnergy;

  /// Water bijhouden (doel, lijsten en score). Uit = water telt nergens mee.
  final bool trackWater;

  TargetSettings copyWith({
    Map<String, Target>? overrides,
    Map<int, (double, double, double)>? schedule,
    bool? addExercise,
    bool? adaptiveEnergy,
    bool? trackWater,
  }) => TargetSettings(
    overrides: overrides ?? this.overrides,
    schedule: schedule ?? this.schedule,
    addExercise: addExercise ?? this.addExercise,
    adaptiveEnergy: adaptiveEnergy ?? this.adaptiveEnergy,
    trackWater: trackWater ?? this.trackWater,
  );

  Map<String, Object?> toJson() => {
    'overrides': {
      for (final e in overrides.entries) e.key: {'goal': e.value.goal, 'upper': e.value.upper},
    },
    'schedule': {
      for (final e in schedule.entries) '${e.key}': [e.value.$1, e.value.$2, e.value.$3],
    },
    'addExercise': addExercise,
    'adaptiveEnergy': adaptiveEnergy,
    'trackWater': trackWater,
  };

  factory TargetSettings.fromJson(Map<String, Object?> j) => TargetSettings(
    overrides: {
      for (final e in ((j['overrides'] as Map?) ?? const {}).entries)
        e.key as String: Target(goal: ((e.value as Map)['goal'] as num?)?.toDouble(), upper: ((e.value as Map)['upper'] as num?)?.toDouble()),
    },
    schedule: {
      for (final e in ((j['schedule'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): (
          ((e.value as List)[0] as num).toDouble(),
          ((e.value as List)[1] as num).toDouble(),
          ((e.value as List)[2] as num).toDouble(),
        ),
    },
    addExercise: j['addExercise'] as bool? ?? true,
    adaptiveEnergy: j['adaptiveEnergy'] as bool? ?? false,
    trackWater: j['trackWater'] as bool? ?? true,
  );
}
