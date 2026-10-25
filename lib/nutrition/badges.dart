/// Badges en titels. Elke badge is een categorie (bv. "On fire" voor je reeks) met vijf niveaus: brons, zilver,
/// goud, platina en diamant. Het icoon blijft hetzelfde, de vormgeving groeit mee.
///
/// Alles wordt berekend uit wat je in de app logde (dezelfde regels als XP: op tijd, geen import) en uit je
/// battles. Badges en titels geven geen XP. Je kiest zelf welke titel vrienden bij je avatar zien en welke 3 badges je
/// vrienden zien (je showcase).
library;

import '../day_clock.dart';
import '../i18n.dart';
import 'insights.dart';
import 'levels.dart';

/// Wat de badges per dag nodig hebben (alleen dagen die meetellen voor XP).
class DayStat {
  const DayStat({
    required this.score,
    this.microScore,
    this.vitD = false,
    this.fiber = false,
    this.iron = false,
    this.omega = false,
    this.protein = false,
    this.foods = const {},
  });

  /// Voedingsscore van de dag, met de energiefactor ([dayScore]): wat je ziet en wat in een battle telt.
  final int score;

  /// De score zonder energiefactor ([completenessScore]): XP en badges steunen hierop, zodat een level of badge die
  /// je al had niet verdwijnt door de energieregel (SP-7).
  int get micro => microScore ?? score;
  final int? microScore;

  /// Vitamine D, vezels, ijzer en eiwit op doel; omega-6 : omega-3 hoogstens 4 : 1.
  final bool vitD, fiber, iron, omega, protein;

  /// Producten (verwijzingen) die die dag gelogd werden.
  final Set<String> foods;
}

/// Samenvatting van je afgelopen battles.
class BattleRecord {
  const BattleRecord({this.played = 0, this.wins = 0, this.bestWinStreak = 0, this.comebacks = 0});
  final int played, wins, bestWinStreak, comebacks;
}

/// [supporter]: badges die alleen met Pro tellen (zie supporter.dart).
enum BadgeGroup { logging, nutrition, level, battle, supporter }

/// Namen van de niveaus.
const tierNames = [('Bronze', 'Brons'), ('Silver', 'Zilver'), ('Gold', 'Goud'), ('Platinum', 'Platina'), ('Diamond', 'Diamant')];

String tierName(int tier) => tier < 1 ? tr('Locked', 'Nog niet verdiend') : tr(tierNames[tier - 1].$1, tierNames[tier - 1].$2);

class BadgeCategory {
  const BadgeCategory(this.id, this.group, this._name, this.thresholds, this._goal, [this.goalOne]);
  final String id;
  final BadgeGroup group;

  /// Supporterbadge: telt alleen met Pro (zie supporter.dart).
  bool get pro => group == BadgeGroup.supporter;
  final (String, String) _name;

  /// Waarde nodig voor niveau 1 tot 5.
  final List<int> thresholds;

  /// Doel als zin, met `#` voor het getal.
  final (String, String) _goal;

  /// Het doel in het enkelvoud, voor een drempel van 1 ("Finish 1 battle", niet "1 battles").
  final (String, String)? goalOne;

  String get name => tr(_name.$1, _name.$2);
  String goal(int n) {
    final g = n == 1 && goalOne != null ? goalOne! : _goal;
    return tr(g.$1, g.$2).replaceAll('#', '$n');
  }

  /// Niveau (0 = nog niet verdiend, 1 tot 5) voor een waarde.
  int tierFor(int value) => thresholds.where((t) => value >= t).length;
}

const badgeCategories = [
  BadgeCategory(
    'days',
    BadgeGroup.logging,
    ('Logbook', 'Logboek'),
    [1, 30, 100, 250, 500],
    ('Log your food on time on # days.', 'Log op # dagen op tijd je eten.'),
    ('Log your food on time on # day.', 'Log op # dag op tijd je eten.'),
  ),
  BadgeCategory('streak', BadgeGroup.logging, ('On fire', 'In vuur en vlam'), [7, 30, 100, 200, 365], (
    'Log # days in a row.',
    'Log # dagen op rij.',
  )),
  BadgeCategory(
    'perfect',
    BadgeGroup.nutrition,
    ('Perfect days', 'Perfecte dagen'),
    [1, 10, 25, 50, 100],
    ('Reach a Nutrient score of 95+ on # days.', 'Haal op # dagen een Voedingsscore van 95+.'),
    ('Reach a Nutrient score of 95+ on # day.', 'Haal op # dag een Voedingsscore van 95+.'),
  ),
  BadgeCategory('vitd', BadgeGroup.nutrition, ('Sunshine', 'Zonnetje'), [7, 30, 90, 180, 365], (
    'Get vitamin D on target on # days.',
    'Haal op # dagen je doel voor vitamine D.',
  )),
  BadgeCategory('fiber', BadgeGroup.nutrition, ('Fiber king', 'Vezelkoning'), [7, 30, 90, 180, 365], (
    'Reach your fiber goal on # days.',
    'Haal op # dagen je vezeldoel.',
  )),
  BadgeCategory('iron', BadgeGroup.nutrition, ('Iron strong', 'IJzersterk'), [7, 30, 90, 180, 365], (
    'Get iron on target on # days.',
    'Haal op # dagen je doel voor ijzer.',
  )),
  BadgeCategory('omega', BadgeGroup.nutrition, ('Omega balance', 'Omega-balans'), [3, 7, 14, 30, 60], (
    'Keep omega-6 : omega-3 at 4:1 or better for # days in a row.',
    'Houd omega-6 : omega-3 # dagen op rij op 4:1 of beter.',
  )),
  BadgeCategory('protein', BadgeGroup.nutrition, ('Protein power', 'Eiwitkracht'), [7, 30, 90, 180, 365], (
    'Reach your protein goal on # days.',
    'Haal op # dagen je eiwitdoel.',
  )),
  BadgeCategory('variety', BadgeGroup.nutrition, ('Variety', 'Variatie'), [25, 50, 100, 200, 400], (
    'Log # different foods.',
    'Log # verschillende producten.',
  )),
  BadgeCategory(
    'perfectweek',
    BadgeGroup.nutrition,
    ('Perfect weeks', 'Perfecte weken'),
    [1, 4, 12, 26, 52],
    (
      'Have # weeks with an average Nutrient score of 90+ (at least 5 days logged).',
      'Haal # weken een gemiddelde Voedingsscore van 90+ (minstens 5 dagen gelogd).',
    ),
    (
      'Have # week with an average Nutrient score of 90+ (at least 5 days logged).',
      'Haal # week een gemiddelde Voedingsscore van 90+ (minstens 5 dagen gelogd).',
    ),
  ),
  BadgeCategory(
    'scanner',
    BadgeGroup.logging,
    ('Scanner', 'Scanner'),
    [1, 10, 50, 100, 250],
    ('Scan # products in the Scan tab.', 'Scan # producten in de Scan-tab.'),
    ('Scan # product in the Scan tab.', 'Scan # product in de Scan-tab.'),
  ),
  BadgeCategory(
    'social',
    BadgeGroup.battle,
    ('Social', 'Sociaal'),
    [1, 3, 5, 10, 20],
    ('Have # friends.', 'Heb # vrienden.'),
    ('Have # friend.', 'Heb # vriend.'),
  ),
  BadgeCategory('level', BadgeGroup.level, ('Level up', 'Level up'), [10, 25, 50, 75, 100], ('Reach level #.', 'Haal level #.')),
  BadgeCategory(
    'battles',
    BadgeGroup.battle,
    ('Challenger', 'Uitdager'),
    [1, 5, 10, 25, 50],
    ('Finish # battles.', 'Speel # battles uit.'),
    ('Finish # battle.', 'Speel # battle uit.'),
  ),
  BadgeCategory(
    'wins',
    BadgeGroup.battle,
    ('Victories', 'Overwinningen'),
    [1, 5, 10, 25, 50],
    ('Win # battles.', 'Win # battles.'),
    ('Win # battle.', 'Win # battle.'),
  ),
  BadgeCategory('winstreak', BadgeGroup.battle, ('Unbeatable', 'Onverslaanbaar'), [2, 3, 5, 8, 12], (
    'Win # battles in a row.',
    'Win # battles op rij.',
  )),
  BadgeCategory(
    'comeback',
    BadgeGroup.battle,
    ('Comeback', 'Comeback'),
    [1, 3, 5, 10, 20],
    ('Win # battles you were losing after Wednesday.', 'Win # battles waarin je na woensdag achterstond.'),
    ('Win # battle you were losing after Wednesday.', 'Win # battle waarin je na woensdag achterstond.'),
  ),
  // Supporterbadges (alleen met Pro). Het badgesysteem heeft vijf niveaus; het vijfde (diamant) is er telkens bij
  // gekomen bovenop de vier afgesproken drempels.
  BadgeCategory('labels', BadgeGroup.supporter, ('Label hunter', 'Etiketjager'), [10, 50, 100, 250, 500], (
    'Add # products of your own.',
    'Voeg # eigen producten toe.',
  )),
  BadgeCategory(
    'offshare',
    BadgeGroup.supporter,
    ('World improver', 'Wereldverbeteraar'),
    [1, 10, 25, 50, 100],
    ('Share # products with Open Food Facts.', 'Deel # producten met Open Food Facts.'),
    ('Share # product with Open Food Facts.', 'Deel # product met Open Food Facts.'),
  ),
  BadgeCategory('chef', BadgeGroup.supporter, ('Chef', 'Chef'), [5, 10, 25, 50, 100], (
    'Create or import # recipes.',
    'Maak of importeer # recepten.',
  )),
  // Diamant na een jaar Pro: wie een jaar steunt, krijgt het hoogste niveau
  BadgeCategory(
    'loyal',
    BadgeGroup.supporter,
    ('Loyal supporter', 'Trouwe supporter'),
    [1, 3, 6, 9, 12],
    ('Be a supporter for # months.', 'Wees # maanden supporter.'),
    ('Be a supporter for # month.', 'Wees # maand supporter.'),
  ),
];

final categoryById = {for (final c in badgeCategories) c.id: c};

/// Titels bij je avatar (voor vrienden), vrijgespeeld door een niveau in een categorie.
class ProfileTitle {
  const ProfileTitle(this.id, this._name, [this.category, this.tier = 0, this.need = TitleNeed.none]);
  final String id;
  final (String, String) _name;
  final String? category;
  final int tier;

  /// Extra voorwaarde buiten de badges (supportertitels).
  final TitleNeed need;
  String get name => tr(_name.$1, _name.$2);

  /// Supportertitel: alleen te verdienen met Pro. Zonder ooit Pro staat ze nergens (ook niet als slot).
  bool get pro => need != TitleNeed.none || (category != null && categoryById[category]?.pro == true);
}

/// [supporter]: ooit Pro gehad; [founder]: Pro geworden in het eerste jaar (zie supporter.dart).
enum TitleNeed { none, supporter, founder }

const titles = [
  ProfileTitle('rookie', ('Rookie', 'Beginner')),
  // Een titel die je in de eerste dagen al haalt: je eerste vriend
  ProfileTitle('team_player', ('Team player', 'Teamspeler'), 'social', 1),
  ProfileTitle('streak_keeper', ('Streak keeper', 'Reekshouder'), 'streak', 2),
  ProfileTitle('perfectionist', ('Perfectionist', 'Perfectionist'), 'perfect', 2),
  ProfileTitle('sun_seeker', ('Sun seeker', 'Zonaanbidder'), 'vitd', 3),
  ProfileTitle('micro_hunter', ('Micro hunter', 'Microjager'), 'level', 2),
  ProfileTitle('nutrition_nerd', ('Nutrition nerd', 'Voedingsfanaat'), 'level', 3),
  ProfileTitle('matrix_master', ('Matrix master', 'Matrixmeester'), 'level', 5),
  ProfileTitle('challenger', ('Challenger', 'Uitdager'), 'battles', 1),
  ProfileTitle('champion', ('Champion', 'Kampioen'), 'wins', 3),
  ProfileTitle('comeback_kid', ('Comeback kid', 'Comebackkoning'), 'comeback', 1),
  ProfileTitle('unbeatable', ('Unbeatable', 'Onverslaanbaar'), 'winstreak', 3),
  ProfileTitle('explorer', ('Food explorer', 'Ontdekkingsreiziger'), 'variety', 3),
  ProfileTitle('protein_pro', ('Protein pro', 'Eiwitprof'), 'protein', 3),
  ProfileTitle('label_reader', ('Label reader', 'Etiketlezer'), 'scanner', 3),
  // Supportertitels. Eenmaal verdiend blijven ze, ook als Pro stopt (zie supporter.dart).
  ProfileTitle('supporter', ('Supporter', 'Supporter'), null, 0, TitleNeed.supporter),
  ProfileTitle('patron', ('Patron', 'Mecenas'), 'loyal', 3),
  ProfileTitle('founder', ('Founder', 'Stichter'), null, 0, TitleNeed.founder),
];

final titleById = {for (final t in titles) t.id: t};

/// Langste reeks opeenvolgende dagen waarvoor [ok] waar is.
int _longestRun(Map<String, DayStat> stats, bool Function(DayStat) ok) {
  final days = stats.keys.toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final k in days) {
    final d = DateTime.parse(k);
    final next = prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d;
    run = ok(stats[k]!) ? (next ? run + 1 : 1) : 0;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

/// Je waarde per categorie (bv. langste reeks = 34).
Map<String, int> badgeValues({
  required Map<String, DayStat> days,
  required LevelInfo level,
  required BattleRecord battles,
  int friends = 0,
  int scanned = 0,
  DateTime? today,
}) {
  int count(bool Function(DayStat) f) => days.values.where(f).length;
  // Perfecte weken: per ISO-week (maandag) minstens 5 gelogde dagen met een gemiddelde van 90+
  final weeks = <String, List<int>>{};
  for (final e in days.entries) {
    final d = DateTime.parse(e.key);
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    weeks.putIfAbsent('$monday', () => []).add(e.value.micro);
  }
  final perfectWeeks = weeks.values.where((s) => s.length >= 5 && s.reduce((a, b) => a + b) / s.length >= 90).length;
  return {
    'protein': count((d) => d.protein),
    'variety': {for (final d in days.values) ...d.foods}.length,
    'perfectweek': perfectWeeks,
    'scanner': scanned,
    'social': friends,
    'days': days.length,
    'streak': loggingStreak(days.keys.toSet(), today ?? logicalNow()).longest,
    'perfect': count((d) => d.micro >= 95),
    'vitd': count((d) => d.vitD),
    'fiber': count((d) => d.fiber),
    'iron': count((d) => d.iron),
    'omega': _longestRun(days, (d) => d.omega),
    'level': level.level,
    'battles': battles.played,
    'wins': battles.wins,
    'winstreak': battles.bestWinStreak,
    'comeback': battles.comebacks,
  };
}

/// Niveau per categorie (0 = nog niet verdiend).
Map<String, int> badgeTiers(Map<String, int> values) => {for (final c in badgeCategories) c.id: c.tierFor(values[c.id] ?? 0)};

/// Titels die je mag kiezen. [supporter]: je had ooit Pro (of nu); [founder]: je werd Pro in het eerste jaar.
List<ProfileTitle> availableTitles(Map<String, int> tiers, {bool supporter = false, bool founder = false}) => [
  for (final t in titles)
    if (switch (t.need) {
          TitleNeed.none => true,
          TitleNeed.supporter => supporter,
          TitleNeed.founder => supporter && founder,
        } &&
        (t.category == null || (tiers[t.category] ?? 0) >= t.tier))
      t,
];

/// Showcase: de gekozen categorieën die je verdiend hebt. Met [fill] (nog nooit zelf gekozen) aangevuld met je
/// hoogste niveaus tot 3; een eigen keuze van minder dan 3 blijft zoals ze is.
List<String> showcaseOf(List<String> chosen, Map<String, int> tiers, {bool fill = true}) {
  final earned = [
    for (final c in badgeCategories)
      if ((tiers[c.id] ?? 0) > 0) c.id,
  ];
  final out = [
    for (final id in chosen)
      if (earned.contains(id)) id,
  ];
  if (!fill) return out.take(3).toList();
  final rest = earned.where((id) => !out.contains(id)).toList()..sort((a, b) => tiers[b]!.compareTo(tiers[a]!));
  return [...out, ...rest].take(3).toList();
}

/// Showcase als tekst voor de server ("streak:3,level:5") en terug.
String encodeShowcase(List<String> ids, Map<String, int> tiers) => [for (final id in ids) '$id:${tiers[id]}'].join(',');

List<(String, int)> decodeShowcase(String? s) => [
  for (final part in (s ?? '').split(','))
    if (part.contains(':') && categoryById.containsKey(part.split(':').first)) (part.split(':').first, int.tryParse(part.split(':').last) ?? 1),
];
