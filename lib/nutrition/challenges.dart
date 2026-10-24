/// Uitdagingen: een regel per dag (bv. "minstens 30 g vezels") die je een aantal dagen volhoudt, alleen of met
/// vrienden.
///
/// Alles hier is zuivere logica: sjablonen, de beoordeling van één dag en de ranglijst. Welke dagen je gelogd hebt
/// en hoeveel je at, komt uit het dagboek (zie state/challenge_days.dart). Naar vrienden gaat alleen per dag of je
/// hem gehaald hebt.
library;

import '../i18n.dart';
import 'nutrients.dart';

/// Pseudo-voedingsstof: porties groenten van 80 g (peulvruchten tellen hoogstens één portie).
const vegKey = 'veg_portions';

/// Gram per portie groenten (WHO, NHS).
const vegPortionGrams = 80.0;

enum ChallengeRule {
  /// Minstens [ChallengeTemplate.amount] per dag.
  min,

  /// Hoogstens [ChallengeTemplate.amount] per dag (een dag zonder eten telt niet als gehaald).
  max,

  /// Je eigen dagdoel halen (95% telt, zoals bij de badges).
  goal,
}

/// Voedingsstoffen waaruit je een eigen uitdaging kiest.
const challengeNutrients = [
  'fiber',
  'protein',
  // Koolhydraten (hoogstens of minstens), bv. bij diabetes (S07)
  'carbs',
  vegKey,
  'free_sugars',
  'sugars',
  'water',
  'sodium',
  'sfa',
  'omega3',
  'vit_c',
  'vit_d',
  'calcium',
  'iron',
  'potassium',
  'magnesium',
  'caffeine',
  'alcohol',
  'energy',
];

String challengeNutrientName(String key) => key == vegKey ? tr('Vegetable portions', 'Porties groenten') : (nutrientByKey[key]?.name ?? key);

String challengeNutrientUnit(String key) => key == vegKey ? '' : (nutrientByKey[key]?.unit ?? '');

/// Hoeveelheid met eenheid, zonder overbodige decimalen ("30 g", "5 porties", "2.300 mg").
String fmtChallengeAmount(String key, double v) {
  final s = fmtGrouped(v);
  if (key == vegKey) {
    return v == 1 ? tr('1 portion', '1 portie') : tr('$s portions', '$s porties');
  }
  final unit = challengeNutrientUnit(key);
  return unit.isEmpty ? s : '$s $unit';
}

class ChallengeTemplate {
  const ChallengeTemplate({required this.id, required this.nutrient, required this.rule, this.amount = 0, required this.days, int? need, this.title})
    : need = need ?? days;

  /// Sleutel van een ingebouwd sjabloon, of "custom".
  final String id;
  final String nutrient;
  final ChallengeRule rule;
  final double amount;

  /// Duur in dagen, en hoeveel dagen je moet halen om de uitdaging te winnen.
  final int days, need;

  /// Eigen naam (alleen bij een eigen uitdaging).
  final String? title;

  bool get builtin => id != 'custom';

  /// Naam zoals je ze ziet.
  String get name {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    final b = _builtinNames[id];
    if (b != null) return b();
    return '${dailyRule[0].toUpperCase()}${dailyRule.substring(1)}, ${durationText.toLowerCase()}';
  }

  /// De regel van één dag ("at least 30 g fiber").
  String get dailyRule {
    // Groenten: "5 porties groenten", niet "5 porties porties groenten" (S13)
    final n = nutrient == vegKey && rule != ChallengeRule.goal ? tr('of vegetables', 'groenten') : challengeNutrientName(nutrient).toLowerCase();
    return switch (rule) {
      ChallengeRule.min => tr('at least ${fmtChallengeAmount(nutrient, amount)} $n', 'minstens ${fmtChallengeAmount(nutrient, amount)} $n'),
      ChallengeRule.max => tr('no more than ${fmtChallengeAmount(nutrient, amount)} $n', 'hoogstens ${fmtChallengeAmount(nutrient, amount)} $n'),
      ChallengeRule.goal => tr('reach your $n goal', 'je doel voor $n halen'),
    };
  }

  /// "30 days" of "10 of 14 days".
  String get durationText => need >= days ? tr('$days days', '$days dagen') : tr('$need of $days days', '$need van de $days dagen');

  ChallengeTemplate copyWith({String? title}) =>
      ChallengeTemplate(id: id, nutrient: nutrient, rule: rule, amount: amount, days: days, need: need, title: title ?? this.title);

  Map<String, Object?> toJson() => {
    'id': id,
    'nutrient': nutrient,
    'rule': rule.name,
    'amount': amount,
    'days': days,
    'need': need,
    if (title != null) 'title': title,
  };

  factory ChallengeTemplate.fromJson(Map<String, Object?> j) {
    final days = ((j['days'] as num?)?.toInt() ?? 7).clamp(1, 90);
    return ChallengeTemplate(
      id: (j['id'] as String?) ?? 'custom',
      nutrient: (j['nutrient'] as String?) ?? 'fiber',
      rule: ChallengeRule.values.asNameMap()[j['rule']] ?? ChallengeRule.min,
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      days: days,
      need: ((j['need'] as num?)?.toInt() ?? days).clamp(1, days),
      title: j['title'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChallengeTemplate &&
      other.id == id &&
      other.nutrient == nutrient &&
      other.rule == rule &&
      other.amount == amount &&
      other.days == days &&
      other.need == need &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, nutrient, rule, amount, days, need, title);
}

final Map<String, String Function()> _builtinNames = {
  'fiber30': () => tr('30 days of 30 g fiber', '30 dagen 30 g vezels'),
  'sugar_week': () => tr('A week under 25 g free sugars', 'Een week onder 25 g vrije suikers'),
  'veg5': () => tr('5 portions of veg a day for 2 weeks', '2 weken lang 5 porties groenten per dag'),
  'protein10of14': () => tr('Protein goal 10 of 14 days', 'Eiwitdoel 10 van de 14 dagen'),
  'water21': () => tr('2 litres of water for 3 weeks', '3 weken lang 2 liter water'),
  'sodium14': () => tr('Two weeks under 2,000 mg sodium', 'Twee weken onder 2.000 mg natrium'),
};

/// Ingebouwde sjablonen.
const builtinChallenges = <ChallengeTemplate>[
  ChallengeTemplate(id: 'fiber30', nutrient: 'fiber', rule: ChallengeRule.min, amount: 30, days: 30),
  ChallengeTemplate(id: 'sugar_week', nutrient: 'free_sugars', rule: ChallengeRule.max, amount: 25, days: 7),
  ChallengeTemplate(id: 'veg5', nutrient: vegKey, rule: ChallengeRule.min, amount: 5, days: 14),
  ChallengeTemplate(id: 'protein10of14', nutrient: 'protein', rule: ChallengeRule.goal, days: 14, need: 10),
  ChallengeTemplate(id: 'water21', nutrient: 'water', rule: ChallengeRule.min, amount: 2000, days: 21),
  ChallengeTemplate(id: 'sodium14', nutrient: 'sodium', rule: ChallengeRule.max, amount: 2000, days: 14),
];

/// Hoe een dag ervoor staat.
enum ChallengeDayStatus {
  /// Gehaald.
  met,

  /// Niet gehaald (of niets gelogd).
  missed,

  /// Vandaag, nog niet beslist: bij "minstens" nog niet genoeg, bij "hoogstens" tot nu toe goed.
  open,

  /// Nog niet begonnen.
  upcoming,
}

/// Wat het dagboek over één dag weet.
class ChallengeDayInput {
  const ChallengeDayInput({required this.logged, this.value = 0, this.goal});

  /// Er is eten gelogd (supplementen alleen tellen niet).
  final bool logged;

  /// Hoeveel van de voedingsstof (of porties groenten).
  final double value;

  /// Je eigen dagdoel (bij [ChallengeRule.goal]).
  final double? goal;

  static const empty = ChallengeDayInput(logged: false);
}

/// Beoordeling van één dag. [today]: de dag loopt nog, dus een "minstens" die nog niet gehaald is en een
/// "hoogstens" die nog niet overschreden is, zijn nog open.
ChallengeDayStatus evaluateChallengeDay(ChallengeTemplate t, ChallengeDayInput d, {bool today = false}) {
  final undecided = today ? ChallengeDayStatus.open : ChallengeDayStatus.missed;
  if (!d.logged) return undecided;
  switch (t.rule) {
    case ChallengeRule.min:
      return d.value >= t.amount - 1e-9 ? ChallengeDayStatus.met : undecided;
    case ChallengeRule.max:
      if (d.value > t.amount + 1e-9) return ChallengeDayStatus.missed;
      return today ? ChallengeDayStatus.open : ChallengeDayStatus.met;
    case ChallengeRule.goal:
      final g = d.goal;
      if (g == null || g <= 0) return undecided;
      return d.value >= g * 0.95 ? ChallengeDayStatus.met : undecided;
  }
}

/// Doel van vandaag in getallen: bij "minstens" en "doel" wat je moet halen, bij "hoogstens" de grens.
double? challengeTarget(ChallengeTemplate t, ChallengeDayInput d) => t.rule == ChallengeRule.goal ? d.goal : t.amount;

/// Een uitdaging zoals de app ze bewaart (ook zonder account).
class Challenge {
  const Challenge({required this.id, required this.template, required this.start, this.remoteId, this.owner = true});

  /// Lokaal id.
  final String id;
  final ChallengeTemplate template;

  /// Eerste dag (00:00 lokale tijd).
  final DateTime start;

  /// Id op de server bij een groepsuitdaging; null = alleen voor jezelf.
  final String? remoteId;
  final bool owner;

  bool get group => remoteId != null;

  /// Laatste dag.
  DateTime get end => DateTime(start.year, start.month, start.day + template.days - 1);

  DateTime dayAt(int i) => DateTime(start.year, start.month, start.day + i);

  bool finishedOn(DateTime today) => _d(today).isAfter(end);
  bool startedOn(DateTime today) => !_d(today).isBefore(start);

  /// Loopt (of begint nog): nog niet voorbij.
  bool activeOn(DateTime today) => !finishedOn(today);

  Challenge copyWith({String? remoteId, ChallengeTemplate? template}) =>
      Challenge(id: id, template: template ?? this.template, start: start, remoteId: remoteId ?? this.remoteId, owner: owner);

  Map<String, Object?> toJson() => {
    'id': id,
    'template': template.toJson(),
    'start': _key(start),
    if (remoteId != null) 'remote': remoteId,
    'owner': owner,
  };

  factory Challenge.fromJson(Map<String, Object?> j) => Challenge(
    id: j['id'] as String,
    template: ChallengeTemplate.fromJson(((j['template'] as Map?) ?? const {}).cast<String, Object?>()),
    start: DateTime.parse(j['start'] as String),
    remoteId: j['remote'] as String?,
    owner: j['owner'] != false,
  );
}

DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);
String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Stand van een uitdaging op [today].
class ChallengeProgress {
  ChallengeProgress(this.challenge, this.statuses, {this.todayInput});

  final Challenge challenge;

  /// Per dag van de uitdaging (index 0 = startdag).
  final List<ChallengeDayStatus> statuses;

  /// Wat het dagboek vandaag weet (null als vandaag geen dag van de uitdaging is).
  final ChallengeDayInput? todayInput;

  int get met => statuses.where((s) => s == ChallengeDayStatus.met).length;
  int get missed => statuses.where((s) => s == ChallengeDayStatus.missed).length;

  /// Dagen die nog kunnen meetellen (vandaag als hij open is, en de dagen die nog komen).
  int get remaining => statuses.where((s) => s == ChallengeDayStatus.open || s == ChallengeDayStatus.upcoming).length;

  int get need => challenge.template.need;
  bool get won => met >= need;

  /// Niet meer te halen.
  bool get lost => !won && met + remaining < need;
  bool get finished => remaining == 0;

  /// Voor de ring: deel van de dagen die je moet halen.
  double get ring => need == 0 ? 1 : (met / need).clamp(0.0, 1.0);

  /// Hoeveelste dag het vandaag is (1 = startdag), of null buiten de looptijd.
  int? dayNumber(DateTime today) {
    final i = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(challenge.start.year, challenge.start.month, challenge.start.day)).inDays;
    return i < 0 || i >= statuses.length ? null : i + 1;
  }

  ChallengeDayStatus? statusOn(DateTime today) {
    final n = dayNumber(today);
    return n == null ? null : statuses[n - 1];
  }

  /// Per dag: gehaald of niet, voor de server (alleen dagen tot en met vandaag).
  Map<String, bool> pushable() => {
    for (final (i, s) in statuses.indexed)
      if (s != ChallengeDayStatus.upcoming) _key(challenge.dayAt(i)): s == ChallengeDayStatus.met,
  };
}

/// Stand van [c] op [today], met [input] per dag uit het dagboek.
ChallengeProgress challengeProgress(Challenge c, DateTime today, ChallengeDayInput Function(DateTime day) input) {
  final t = _d(today);
  ChallengeDayInput? todayInput;
  final statuses = <ChallengeDayStatus>[
    for (var i = 0; i < c.template.days; i++)
      () {
        final day = c.dayAt(i);
        if (day.isAfter(t)) return ChallengeDayStatus.upcoming;
        final d = input(day);
        final isToday = day == t;
        if (isToday) todayInput = d;
        return evaluateChallengeDay(c.template, d, today: isToday);
      }(),
  ];
  return ChallengeProgress(c, statuses, todayInput: todayInput);
}

/// Een deelnemer op de ranglijst.
class ChallengeEntry {
  const ChallengeEntry({required this.id, required this.name, this.avatar, this.level = 1, required this.met, this.me = false, this.accepted = true});
  final String id, name;
  final String? avatar;
  final int level, met;
  final bool me, accepted;
}

/// Ranglijst: aanvaarde deelnemers, meeste gehaalde dagen eerst; gelijk = zelfde plaats (1, 1, 3). Bij een
/// gelijke stand sta jij bovenaan, daarna op naam.
List<(int, ChallengeEntry)> rankChallenge(Iterable<ChallengeEntry> entries) {
  final list =
      [
        for (final e in entries)
          if (e.accepted) e,
      ]..sort((a, b) {
        final c = b.met.compareTo(a.met);
        if (c != 0) return c;
        if (a.me != b.me) return a.me ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  final out = <(int, ChallengeEntry)>[];
  for (final (i, e) in list.indexed) {
    final place = i > 0 && list[i - 1].met == e.met ? out[i - 1].$1 : i + 1;
    out.add((place, e));
  }
  return out;
}
