/// Centrale toestand van de app: gekozen dag, dagboek, profiel, richtwaarden en alles rond de dag
/// (beweging, metingen, notities, vasten, terugkerende items).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/food.dart';
import '../i18n.dart';
import '../data/food_db.dart';
import '../data/models.dart';
import '../data/off_client.dart';
import '../data/fdc_client.dart';
import '../data/product_info.dart';
import '../data/user_db.dart';
import '../import/importer.dart';
import '../labs/lab_report.dart';
import '../labs/supplement_advice.dart';
import '../nutrition/estimate.dart';
import '../nutrition/allergens.dart';
import '../nutrition/badges.dart';
import '../nutrition/bioavailability.dart';
import '../nutrition/gap_plan.dart';
import '../nutrition/health.dart';
import '../nutrition/insights.dart';
import '../nutrition/quick_parse.dart';
import '../nutrition/report.dart';
import '../nutrition/levels.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/preferences.dart';
import '../nutrition/supplements.dart';
import '../nutrition/targets.dart';
import '../nutrition/values.dart';

/// Een product dat een tekort van vandaag flink aanvult (zie [AppState.suggestion]).
class Suggestion {
  const Suggestion({
    required this.food,
    required this.grams,
    required this.nutrient,
    required this.before,
    required this.after,
    this.portion,
    this.extra,
    this.mine = false,
  });

  final Food food;
  final double grams;
  final Portion? portion;
  final Nutrient nutrient;

  /// Deel van het doel vóór en na dit product.
  final double before;
  final double after;

  /// Een tweede tekort dat het mee aanvult, met de winst als deel van dat doel.
  final (Nutrient, double)? extra;

  /// Komt uit wat je onlangs at.
  final bool mine;
}

String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime parseDay(String day) => DateTime.parse(day);

class AppState extends ChangeNotifier {
  AppState({required this.foods, required this.user, OffClient? off, FdcClient? fdc}) : off = off ?? OffClient(), fdc = fdc ?? FdcClient() {
    _readSettings();
    _load();
  }

  void _readSettings() {
    final saved = user.setting('profile');
    _profile = saved == null ? const Profile() : Profile.fromJson(saved);
    _hasProfile = saved != null;
    final ts = user.setting('targets');
    _settings = ts == null ? const TargetSettings() : TargetSettings.fromJson(ts);
    _preferences = {for (final n in ((user.setting('preferences')?['list'] as List?) ?? const [])) ?DietPref.values.asNameMap()[n]};
  }

  /// Alles opnieuw inlezen, bv. nadat de synchronisatie wijzigingen van een ander toestel binnenhaalde.
  void reloadFromDisk() {
    _targetsVersion++;
    _readSettings();
    _refresh();
  }

  /// Na een update van de ingebouwde database: dagboekregels van ingebouwde producten bijwerken naar de nieuwe
  /// (gecorrigeerde en aangevulde) waarden. Eén keer per databaseversie.
  void refreshBuiltinSnapshots() {
    final v = foods.version;
    if (v.isEmpty || user.setting('_foodsdb')?['version'] == v) return;
    var changed = 0;
    for (final ref in user.diaryFoodRefs()) {
      if (!FoodDb.isDbRef(ref)) continue;
      final f = foods.byRef(ref);
      if (f != null) changed += user.replaceDiarySnapshots(ref, f.per100g);
    }
    user.setSetting('_foodsdb', {'version': v});
    if (changed > 0) _refresh();
  }

  /// Eerder bewaarde merkproducten alsnog aanvullen met hun basisproduct (op de achtergrond, één voor één).
  Future<void> upgradeSavedProducts() async {
    for (final f in user.offFoodsWithoutProxy()) {
      await completeOff(f);
    }
  }

  final FoodDb foods;
  final UserDb user;
  final OffClient off;
  final FdcClient fdc;

  DateTime _date = _dateOnly(DateTime.now());
  DateTime get date => _date;
  String get day => dayKey(_date);
  bool get isToday => _date == _dateOnly(DateTime.now());

  List<DiaryEntry> _entries = const [];
  List<DiaryEntry> get entries => _entries;

  List<Exercise> _exercise = const [];
  List<Exercise> get exercise => _exercise;
  double get burnedKcal => _exercise.fold(0, (a, e) => a + e.kcal);

  List<Biometric> _biometrics = const [];
  List<Biometric> get biometrics => _biometrics;

  String _note = '';
  String get note => _note;

  late Profile _profile;
  Profile get profile => _profile;

  late TargetSettings _settings;
  TargetSettings get settings => _settings;

  /// Heeft de gebruiker zijn profiel al ingevuld? Zo niet, dan gelden standaardwaarden.
  late bool _hasProfile;
  bool get hasProfile => _hasProfile;

  late Map<String, Target> _targets;
  Map<String, Target> get targets => _targets;

  /// Richtwaarden zonder eigen aanpassingen (EFSA), om te tonen wat de standaard is.
  late Map<String, Target> _defaultTargets;
  Map<String, Target> get defaultTargets => _defaultTargets;

  late NutrientTotals _totals;
  NutrientTotals get totals => _totals;

  void _load() {
    _estimated = false;
    _labs = null;
    _suggested = false;
    // Terugkerende items alleen tot en met vandaag invullen, niet voor dagen in de toekomst
    if (!_date.isAfter(_dateOnly(DateTime.now()))) user.applyRepeats(day, _date);
    // Automatische supplementen: alleen vandaag aanvinken, en nooit opnieuw als je ze zelf afvinkte
    if (_date == _dateOnly(DateTime.now())) {
      for (final sup in supplements) {
        if (sup.auto && day.compareTo(sup.since ?? day) >= 0 && !user.hasSupplementRow(day, sup)) user.setSupplementTaken(day, sup, true);
      }
    }
    _level = null;
    _entries = user.entriesFor(day);
    _totals = NutrientTotals.sumOf(_entries.map((e) => withDerived(e.amounts)));
    _exercise = user.exerciseFor(day);
    _biometrics = user.biometricsFor(day);
    _note = user.note(day);
    _targets = targetsForDate(_date, burned: burnedKcal);
    _defaultTargets = targetsFor(profileFor(_date), year: _date.year, extraKcal: _extraKcal(burnedKcal), tdee: adaptiveTdee);
  }

  /// Beweging bij het doel optellen, behalve bij een adaptief verbruik: daar zit je gemiddelde beweging al in.
  double _extraKcal(double burned) => _settings.addExercise && adaptiveTdee == null ? burned : 0;

  /// Profiel voor een dag, met de macroverdeling van het weekschema als die er is.
  Profile profileFor(DateTime d) {
    final s = _settings.schedule[d.weekday];
    return s == null ? _profile : _profile.copyWith(proteinPct: s.$1, carbsPct: s.$2, fatPct: s.$3);
  }

  /// Richtwaarden voor een dag: profiel, weekschema, beweging en eigen doelen.
  Map<String, Target> targetsForDate(DateTime d, {double burned = 0}) {
    final t = targetsFor(profileFor(d), year: d.year, extraKcal: _extraKcal(burned), tdee: adaptiveTdee);
    return {...t, ..._settings.overrides}..removeWhere((k, _) => hiddenNutrients.contains(k));
  }

  /// Voedingsstoffen die je niet wilt zien (bv. water als je dat niet bijhoudt).
  Set<String> get hiddenNutrients => _settings.trackWater ? const {} : const {'water'};

  // ── Verbruik uit gewicht en logboek ──

  EnergyEstimate? _estimate;
  bool _estimated = false;

  /// Geschat verbruik over de laatste 28 volledige dagen (null = te weinig gegevens).
  EnergyEstimate? get energyEstimate {
    if (_estimated) return _estimate;
    final today = _dateOnly(DateTime.now());
    final to = today.subtract(const Duration(days: 1));
    final from = to.subtract(const Duration(days: 27));
    final days = [for (var i = 0; i < 28; i++) dayKey(from.add(Duration(days: i)))];
    final kcal = {for (final e in dailyTotals(from, to).entries) e.key: e.value['energy']};
    final weights = {for (final b in user.biometricHistory('weight', from: dayKey(from))) b.day: b.value};
    _estimate = estimateEnergy(kcal, weights, days);
    _estimated = true;
    return _estimate;
  }

  /// Verbruik dat voor de doelen geldt als "adaptief" aanstaat en er genoeg gegevens zijn, anders null.
  /// Verbruik uit gewicht en logboek gebruiken we niet meer voor je doel: de formule is de standaard.
  double? get adaptiveTdee => null;

  // ── Weergave ──

  /// Licht, donker of zoals het toestel (opgeslagen als "light", "dark" of "system").
  String get themeMode => (user.setting('ui')?['theme'] as String?) ?? 'system';

  /// Taal van de app (alleen op dit toestel).
  void setLanguage(AppLang lang) {
    user.setSetting('ui', {...?user.setting('ui'), 'lang': lang.name});
    setAppLang(lang);
  }

  void setThemeMode(String mode) {
    user.setSetting('ui', {...?user.setting('ui'), 'theme': mode});
    notifyListeners();
  }

  // ── Voorkeuren en suggesties ──

  late Set<DietPref> _preferences;
  Set<DietPref> get preferences => _preferences;

  void setPreferences(Set<DietPref> p) {
    _preferences = p;
    user.setSetting('preferences', {
      'list': [for (final x in p) x.name],
    });
    _suggested = false;
    notifyListeners();
  }

  /// Rijkste bronnen van een voedingsstof die bij je voorkeuren passen.
  /// Supplementen en (mineraal)zout horen niet thuis tussen de rijkste bronnen, behalve zout voor natrium en chloride.
  /// [advice]: alleen gewone voedingsmiddelen die je kunt aanraden (zie [isAdviceFood]); dan wordt dieper gezocht.
  List<(Food, double)> richestFor(String key, {bool perKcal = false, int limit = 40, bool advice = false}) => [
    for (final r in foods.richestIn(key, perKcal: perKcal, limit: advice ? math.max(300, limit * 15) : limit * 3))
      if ((!advice || isAdviceFood(r.$1)) &&
          fitsPreferences(r.$1, _preferences) &&
          !containsAllergen(r.$1, allergies) &&
          !(r.$1.category ?? '').toLowerCase().contains('supplement') &&
          (key == 'sodium' || key == 'chloride' || !_salt.hasMatch(r.$1.name)))
        r,
  ].take(limit).toList();

  static final _salt = RegExp(r'^(mineral salt|salt, (mineral|table|iodized|sea))|\btable salt\b', caseSensitive: false);

  Suggestion? _suggestion;
  bool _suggested = false;

  /// "Grootste winst vandaag": één product dat je grootste tekort flink aanvult, liefst iets wat je al eet.
  Suggestion? get suggestion {
    if (_suggested) return _suggestion;
    _suggestion = _findSuggestion();
    _suggested = true;
    return _suggestion;
  }

  static final _measure = RegExp(r'\b(cup|cups|tbsp|tsp|oz|fl|ml|dl|l|quart|pint)\b', caseSensitive: false);

  static final _notAFood = RegExp(r'\b(oil|supplement|powder|extract|fortified|infant|babyfood|yeast extract|spice|spices)\b', caseSensitive: false);

  Suggestion? _findSuggestion() {
    if (_entries.isEmpty) return null;
    final lows = [
      for (final a in attentionList(_totals.values, _targets, limit: 4))
        if (a.$3 == Level.low) a,
    ];
    final mine = recentFoods();
    for (final (n, before, _) in lows) {
      final t = _targets[n.key]!;
      final candidates = [...mine, for (final r in richestFor(n.key, perKcal: true, limit: 40, advice: true)) r.$1];
      for (final f in candidates) {
        if (f.source == FoodSource.recipe ||
            !isAdviceFood(f) ||
            _notAFood.hasMatch(f.name) ||
            !fitsPreferences(f, _preferences) ||
            containsAllergen(f, allergies)) {
          continue;
        }
        final v = withDerived(f.per100g);
        final per100 = v[n.key] ?? 0;
        if (per100 <= 0) continue;
        // Een herkenbare portie (1 ei, 1 filet, 1 snee) eerder dan een maatbeker of eetlepel; anders 100 g
        final portion = f.portions.where((p) => p.grams >= 30 && p.grams <= 250 && !_measure.hasMatch(p.label)).firstOrNull;
        final grams = portion?.grams ?? 100;
        final added = per100 * grams / 100;
        final after = (_totals[n.key] + added) / t.goal!;
        final kcal = (v['energy'] ?? 0) * grams / 100;
        // Genoeg winst, niet boven de bovengrens en geen halve maaltijd aan calorieën
        if (added / t.goal! < 0.25 || (t.upper != null && _totals[n.key] + added > t.upper!) || kcal > 450) continue;
        // Wat het daarnaast nog bijbrengt voor je andere tekorten
        (Nutrient, double)? extra;
        for (final (m, _, _) in lows) {
          if (m.key == n.key) continue;
          final gain = (v[m.key] ?? 0) * grams / 100 / _targets[m.key]!.goal!;
          if (gain >= 0.1 && (extra == null || gain > extra.$2)) extra = (m, gain);
        }
        return Suggestion(food: f, grams: grams, portion: portion, nutrient: n, before: before, after: after, extra: extra, mine: mine.contains(f));
      }
    }
    return null;
  }

  /// Tips over opname (biobeschikbaarheid) voor de gekozen dag.
  List<BioTip> get bioTipsToday => bioTips(_entries, _targets);

  /// Maand- of jaaroverzicht van [from] tot en met [to] (niet later dan vandaag). Null als je niets logde.
  Recap? recap(DateTime from, DateTime to, {required bool year}) {
    final today = _dateOnly(DateTime.now());
    final end = to.isAfter(today) ? today : to;
    if (end.isBefore(from)) return null;
    final entries = [
      for (final e in user.entriesBetween(dayKey(from), dayKey(end)))
        if (!e.foodRef.startsWith('supp:')) e,
    ];
    if (entries.isEmpty) return null;
    final daily = dailyTotals(from, end);
    final scores = <String, int>{};
    final sums = <String, double>{};
    var kcal = 0.0;
    for (final e in daily.entries) {
      final t = targetsForDate(DateTime.parse(e.key));
      scores[e.key] = completenessScore(e.value.values, t);
      kcal += e.value.values['energy'] ?? 0;
      for (final k in stripKeys) {
        final g = t[k]?.goal;
        if (g != null && g > 0) sums[k] = (sums[k] ?? 0) + math.min(1.5, (e.value.values[k] ?? 0) / g);
      }
    }
    final counts = <String, int>{};
    final names = <String, String>{};
    final breakfasts = <String, int>{};
    for (final e in entries) {
      counts[e.foodRef] = (counts[e.foodRef] ?? 0) + 1;
      names[e.foodRef] = e.name;
      if (e.meal == Meal.breakfast) breakfasts[e.name] = (breakfasts[e.name] ?? 0) + 1;
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = scores.entries.isEmpty ? null : scores.entries.reduce((a, b) => b.value > a.value ? b : a);
    (DateTime, int)? bestMonth;
    if (year) {
      final byMonth = <int, List<int>>{};
      for (final e in scores.entries) {
        byMonth.putIfAbsent(DateTime.parse(e.key).month, () => []).add(e.value);
      }
      for (final e in byMonth.entries) {
        final avg = (e.value.reduce((a, b) => a + b) / e.value.length).round();
        if (bestMonth == null || avg > bestMonth.$2) bestMonth = (DateTime(from.year, e.key), avg);
      }
    }
    // Superkracht: niet fosfor, natrium of chloride (die haalt bijna iedereen ruim)
    final candidates = sums.entries.where((e) => !const {'phosphorus', 'sodium', 'chloride'}.contains(e.key)).toList();
    final topNutrient = candidates.isEmpty ? null : candidates.reduce((a, b) => b.value > a.value ? b : a);
    final fav = breakfasts.entries.isEmpty ? null : breakfasts.entries.reduce((a, b) => b.value > a.value ? b : a);
    final xp = level.days.where((d) => d.day.compareTo(dayKey(from)) >= 0 && d.day.compareTo(dayKey(end)) <= 0).fold(0, (a, d) => a + d.xp);
    return Recap(
      from: from,
      to: end,
      year: year,
      daysLogged: daily.length,
      daysInPeriod: DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays + 1,
      distinctFoods: counts.length,
      entries: entries.length,
      topFoods: [for (final e in top.take(5)) (names[e.key]!, e.value)],
      avgScore: scores.isEmpty ? 0 : (scores.values.reduce((a, b) => a + b) / scores.length).round(),
      bestDay: best == null ? null : (DateTime.parse(best.key), best.value),
      bestMonth: bestMonth,
      longestStreak: loggingStreak(daily.keys.toSet(), end).longest,
      xp: xp,
      avgKcal: daily.isEmpty ? 0 : (kcal / daily.length).round(),
      topNutrient: topNutrient == null ? null : (nutrientByKey[topNutrient.key]!, topNutrient.value / daily.length),
      favouriteBreakfast: fav != null && fav.value >= 3 ? fav.key : null,
    );
  }

  /// Maand- of jaaroverzicht gezien (alleen op dit toestel).
  void markRecapSeen(String key) {
    user.setSetting('_recap_seen', {'key': key});
    notifyListeners();
  }

  // ── Bloedwaarden (alleen op dit toestel) ──

  List<LabResult>? _labs;

  /// Alle uitslagen, nieuwste afname eerst.
  List<LabResult> get labResults => _labs ??= user.labs();

  /// De laatste uitslag per stof die de app kent, van de afgelopen [months] maanden.
  Map<String, LabResult> latestLabs({int months = 18, DateTime? at}) {
    final now = at ?? DateTime.now();
    final from = dayKey(DateTime(now.year, now.month - months, now.day));
    final out = <String, LabResult>{};
    for (final r in labResults) {
      final k = r.value.marker?.key;
      if (k != null && r.day.compareTo(from) >= 0 && r.day.compareTo(dayKey(now)) <= 0) out.putIfAbsent(k, () => r);
    }
    return out;
  }

  void saveLabs(DateTime day, List<LabValue> values) {
    user.saveLabs(dayKey(day), values);
    _labs = null;
    notifyListeners();
  }

  void deleteLab(String id) {
    user.deleteLab(id);
    _labs = null;
    notifyListeners();
  }

  void deleteLabDay(String day) {
    user.deleteLabDay(day);
    _labs = null;
    notifyListeners();
  }

  /// Weekrapport gezien of weggeklikt (alleen op dit toestel).
  void markReportSeen(String week) {
    user.setSetting('_report_seen', {'week': week});
    notifyListeners();
  }

  static final _strength = RegExp(r'kracht|gewicht|fitness|strength|weight|crossfit', caseSensitive: false);

  /// Train je in de week van [monday]: veel sport in je profiel, of krachttraining gelogd.
  bool _trainsIn(DateTime monday) {
    if (_profile.activity.index >= Activity.moderate.index) return true;
    for (var i = 0; i < 7; i++) {
      final day = dayKey(DateTime(monday.year, monday.month, monday.day + i));
      if (user.exerciseFor(day).any((e) => _strength.hasMatch(e.name))) return true;
    }
    return false;
  }

  /// Stappen en activiteiten in de week van [monday], tot en met vandaag.
  ActivityWeek _activityIn(DateTime monday) {
    final today = _dateOnly(DateTime.now());
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final last = sunday.isAfter(today) ? today : sunday;
    final days = last.difference(monday).inDays + 1;
    if (days <= 0) return const ActivityWeek();
    final exercises = [
      for (var i = 0; i < days; i++)
        for (final e in user.exerciseFor(dayKey(DateTime(monday.year, monday.month, monday.day + i))))
          (day: e.day, minutes: e.minutes, kcal: e.kcal, strength: _strength.hasMatch(e.name)),
    ];
    // Houdt je activiteiten bij? Dan telt een week zonder ook mee (anders weet de app niet of je bewoog)
    var tracks = exercises.isNotEmpty || user.setting('_health')?['on'] == true;
    for (var i = 1; !tracks && i <= 28; i++) {
      tracks = user.exerciseFor(dayKey(DateTime(monday.year, monday.month, monday.day - i))).isNotEmpty;
    }
    return ActivityWeek(
      steps: [
        for (final b in user.biometricHistory('steps', from: dayKey(monday)))
          if (b.day.compareTo(dayKey(last)) <= 0 && b.value > 0) b.value,
      ],
      exercises: exercises,
      days: days,
      tracksExercise: tracks,
    );
  }

  /// Weekrapport voor de week die op [monday] begint (null als je die week niets logde).
  WeeklyReport? weeklyReport(DateTime monday) {
    ({int score, int days, Map<String, double> avg, HealthCheck? health})? week(DateTime m) {
      final end = DateTime(m.year, m.month, m.day + 6);
      final daily = dailyTotals(m, end);
      if (daily.isEmpty) return null;
      final scores = <int>[];
      final sums = <String, double>{};
      final withTargets = <(NutrientTotals, Map<String, Target>)>[];
      for (final e in daily.entries) {
        final t = targetsForDate(DateTime.parse(e.key));
        withTargets.add((e.value, t));
        scores.add(completenessScore(e.value.values, t));
        for (final k in stripKeys) {
          final g = t[k]?.goal;
          if (g != null && g > 0) sums[k] = (sums[k] ?? 0) + (e.value.values[k] ?? 0) / g;
        }
      }
      return (
        score: (scores.reduce((a, b) => a + b) / scores.length).round(),
        days: scores.length,
        avg: {for (final e in sums.entries) e.key: e.value / daily.length},
        health: healthCheck(
          withTargets,
          weightKg: currentWeight,
          age: _profile.ageIn(m.year),
          heightCm: _profile.heightCm,
          trains: _trainsIn(m),
          labs: latestLabs(at: end),
          activity: _activityIn(m),
        ),
      );
    }

    final now = week(monday);
    if (now == null) return null;
    final prev = week(DateTime(monday.year, monday.month, monday.day - 7));
    final ranked = now.avg.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final worst = ranked.reversed.take(3).toList();
    // Tip: een gewoon product dat je zwakste stof flink aanvult
    WeeklyTip? tip;
    for (final w in worst) {
      final goal = _targets[w.key]?.goal;
      if (goal == null) continue;
      final upper = _targets[w.key]?.upper;
      for (final (f, per100) in richestFor(w.key, limit: 40, advice: true)) {
        if (!isAdviceFood(f)) continue;
        // Een gewone portie (of 100 g) die een flink deel van je doel geeft, zonder de bovengrens te halen
        final portion = f.portions.where((p) => p.grams >= 30 && p.grams <= 250).firstOrNull;
        final grams = portion?.grams ?? 100;
        final frac = per100 * grams / 100 / goal;
        if (frac < 0.25 || frac > 1.5 || (upper != null && per100 * grams / 100 > upper)) continue;
        tip = WeeklyTip(nutrientByKey[w.key]!, f, grams, portion == null ? '100 g' : '${portion.label} (${grams.round()} g)', frac);
        break;
      }
      if (tip != null) break;
    }
    return WeeklyReport(
      monday: monday,
      score: now.score,
      days: now.days,
      prevScore: prev?.score,
      best: [for (final e in ranked.take(3)) (nutrientByKey[e.key]!, e.value)],
      worst: [for (final e in worst) (nutrientByKey[e.key]!, e.value)],
      tip: tip,
      health: now.health,
      prevHealthScore: prev?.health?.score,
    );
  }

  /// Snel loggen: een stuk van een zin omzetten naar een product en een hoeveelheid.
  /// Geeft de beste treffers (de eerste is de keuze) en per treffer gram en portielabel.
  List<(Food, double, Portion?)> resolveQuick(QuickItem q) {
    // Wat iemand zegt, is meestal bereid en heel: "rijst" is gekookte rijst, "eieren" zijn hele eieren
    // Meervoud ("breads", "apples", "eieren"): ook het enkelvoud zoeken, en dat eerst
    final singular = q.query.replaceAll(RegExp(r'(es|s|en)$'), '');
    final seen = <String>{};
    var all = [
      for (final f in [
        if (singular != q.query && singular.length > 2) ...[...user.searchSaved(singular), ...foods.search(singular, limit: 150)],
        ...user.searchSaved(q.query),
        ...foods.search(q.query, limit: 200),
      ])
        if (seen.add(f.ref)) f,
    ];
    // Niets gevonden: probeer de woorden aan elkaar ("volkorenbrood") en dan het laatste woord ("brood")
    final words = q.query.split(RegExp(r'\s+'));
    if (all.isEmpty && words.length > 1) all = searchLocal(words.join()).take(25).toList();
    if (all.isEmpty && words.length > 1) all = searchLocal(words.last).take(25).toList();
    double rank(int i, Food f) {
      final n = f.name.toLowerCase();
      var s = 20.0 - i * 0.15;
      final query = q.query.toLowerCase();
      // Bereid krijgt voorrang bij vlees, vis, granen, eieren en aardappelen; fruit en zuivel liefst zoals ze zijn
      final cookable = RegExp(
        r'\b(chicken|beef|pork|turkey|lamb|fish|salmon|cod|tuna|rice|pasta|spaghetti|noodles?|quinoa|potato(es)?|lentils?|beans?|egg|eggs|kip|rijst|vis|aardappel(en)?)\b',
      );
      if (cookable.hasMatch(n) && RegExp(r'\b(cooked|boiled|baked|grilled|roasted|steamed|whole)\b').hasMatch(n)) s += 12;
      if (RegExp(r'\b(fried|deep fried|candied|canned|syrup|chips|sweetened)\b').hasMatch(n) &&
          !RegExp(r'fried|candied|canned|syrup|chips|sweet').hasMatch(query)) {
        s -= 15;
      }
      if (!isEverydayFood(f)) s -= 30;
      if (RegExp(r'\b(rice|pasta|spaghetti|noodles?|quinoa|lentils?|beans?|oats?|barley|couscous|bulgur)\b').hasMatch(n) &&
          RegExp(r'\b(raw|dry|uncooked)\b').hasMatch(n)) {
        s -= 30;
      }
      if (RegExp(r'\b(yolk|white|powder|dried|flour|substitute|frozen)\b').hasMatch(n) &&
          !query.contains(RegExp(r'yolk|white|powder|dried|flour|frozen'))) {
        s -= 15;
      }
      // Bijproducten en merkproducten van ketens zijn zelden wat iemand bedoelt
      if (RegExp(r'\b(rendered|fat|grease|drippings|skin only|by-products?)\b').hasMatch(n) && !RegExp(r'fat|vet').hasMatch(query)) s -= 20;
      if (RegExp(r"^[A-Z0-9 &'.-]{4,},").hasMatch(f.name)) s -= 12;
      // Orgaanvlees en dieetvarianten alleen als je ze zelf noemt
      if (RegExp(r'\b(liver|kidney|heart|gizzard|giblets|tongue|lever)\b').hasMatch(n) &&
          !RegExp(r'liver|kidney|heart|gizzard|tongue|lever').hasMatch(query)) {
        s -= 25;
      }
      if (RegExp(r'\b(gluten free|low fat|reduced|diet|light|sugar free|unsalted|low sodium)\b').hasMatch(n) &&
          !RegExp(r'gluten|low|reduced|diet|light|free|unsalted').hasMatch(query)) {
        s -= 10;
      }
      return s - n.length / 15;
    }

    final hits = [for (final (i, f) in all.indexed) (rank(i, f), f)]..sort((a, b) => b.$1.compareTo(a.$1));
    (Food, double, Portion?) amount(Food f) {
      if (q.grams != null) return (f, q.grams!, null);
      final n = q.count ?? 1;
      if (q.unitGrams != null) return (f, n * q.unitGrams!, null);
      // Eén stuk: de kleinste portie die met "1 " begint (bv. "1 large" eerder dan een vreemde 101 g)
      final ones = f.portions.where((p) => p.grams >= 15 && p.grams <= 400 && p.label.startsWith('1 ')).toList()
        ..sort((a, b) => a.grams.compareTo(b.grams));
      final portion = ones.firstOrNull ?? f.portions.where((p) => p.grams >= 15 && p.grams <= 400).firstOrNull;
      if (portion != null) return (f, n * portion.grams, portion);
      return (f, n * 100, null);
    }

    return [for (final h in hits.take(6)) amount(h.$2)];
  }

  /// "Wat moet ik nog eten?": 2 à 3 producten die je grootste tekorten van vandaag samen aanvullen.
  GapPlan? gapPlan() {
    final gaps = [
      for (final k in stripKeys)
        if (_targets[k]?.goal != null && (_totals.values[k] ?? 0) < _targets[k]!.goal! * 0.85) k,
    ]..sort((a, b) => ((_totals.values[a] ?? 0) / _targets[a]!.goal!).compareTo((_totals.values[b] ?? 0) / _targets[b]!.goal!));
    if (gaps.isEmpty) return null;
    final mine = [
      for (final f in recentFoods())
        if (fitsPreferences(f, _preferences) && !containsAllergen(f, allergies)) f,
    ];
    final seen = <String>{};
    final candidates = [
      for (final f in [
        ...mine,
        for (final k in gaps.take(6))
          for (final r in richestFor(k, perKcal: true, limit: 25, advice: true)) r.$1,
      ])
        if (seen.add(f.ref)) f,
    ];
    final kcalLeft = (_targets['energy']?.goal ?? 2000) - (_totals.values['energy'] ?? 0);
    return planGaps(totals: _totals.values, targets: _targets, kcalLeft: kcalLeft, candidates: candidates, mine: {for (final f in mine) f.ref});
  }

  void _refresh() {
    _load();
    notifyListeners();
  }

  List<DiaryEntry> entriesFor(Meal meal) => [
    for (final e in _entries)
      if (e.meal == meal && !e.foodRef.startsWith('supp:')) e,
  ];

  // ── Supplementen ──

  /// Supplementen afgestemd op je laatste bloedwaarden, en of ze samen onder de bovengrenzen blijven.
  List<SupplementAdvice> get supplementAdviceList => supplementAdvice(labs: latestLabs(), supplements: supplements);

  /// Je eigen supplementen (bewaard bij je account).
  List<Supplement> get supplements => [
    for (final j in (user.setting('supplements')?['items'] as List?) ?? const []) Supplement.fromJson((j as Map).cast<String, Object?>()),
  ];

  void _saveSupplements(List<Supplement> list) => user.setSetting('supplements', {
    'items': [for (final x in list) x.toJson()],
  });

  void addSupplement(Supplement sup) {
    final list = supplements;
    final taken = {for (final x in list) x.id};
    var id = sup.baseId;
    for (var n = 2; taken.contains(id); n++) {
      id = '${sup.baseId}~$n';
    }
    _saveSupplements([...list, sup.copyWith(id: id, since: dayKey(_dateOnly(DateTime.now())))]);
    _refresh();
  }

  void updateSupplement(Supplement sup) {
    _saveSupplements([for (final x in supplements) x.id == sup.id ? sup : x]);
    _refresh();
  }

  /// Uit je lijst halen; wat je eerder innam, blijft in je dagboek.
  void removeSupplement(Supplement sup) {
    _saveSupplements([
      for (final x in supplements)
        if (x.id != sup.id) x,
    ]);
    _refresh();
  }

  bool supplementTaken(Supplement sup) => _entries.any((e) => e.id == sup.entryId(day));

  void setSupplementTaken(Supplement sup, bool taken) {
    user.setSupplementTaken(day, sup, taken);
    _refresh();
  }

  NutrientTotals totalsFor(Meal meal) => NutrientTotals.sumOf(entriesFor(meal).map((e) => withDerived(e.amounts)));

  void setDate(DateTime d) {
    _date = _dateOnly(d);
    _refresh();
  }

  void shiftDay(int days) => setDate(_date.add(Duration(days: days)));

  void saveProfile(Profile p) {
    _targetsVersion++;
    _profile = p;
    _hasProfile = true;
    user.setSetting('profile', p.toJson());
    _refresh();
  }

  void saveSettings(TargetSettings s) {
    _targetsVersion++;
    _settings = s;
    user.setSetting('targets', s.toJson());
    _refresh();
  }

  /// Eigen richtwaarde instellen (null = terug naar de standaard).
  void setOverride(String key, Target? t) {
    final o = Map.of(_settings.overrides);
    if (t == null) {
      o.remove(key);
    } else {
      o[key] = t;
    }
    saveSettings(_settings.copyWith(overrides: o));
  }

  // ── Dagboek ──

  void addFood(Food food, {required Meal meal, required double grams, required double quantity, String? portionLabel, String? time}) {
    // Opgezochte en eigen producten lokaal bewaren, zodat ze bij "recent" en offline beschikbaar blijven
    if (!FoodDb.isDbRef(food.ref) && food.source != FoodSource.recipe) user.saveFood(food);
    user.addEntry(day: day, meal: meal, food: food, grams: grams, quantity: quantity, portionLabel: portionLabel, time: time);
    _refresh();
  }

  void updateEntry(DiaryEntry e, {required Meal meal, required double grams, required double quantity, String? portionLabel, String? time}) {
    user.updateEntry(e.id, meal: meal, grams: grams, quantity: quantity, portionLabel: portionLabel, time: time);
    _refresh();
  }

  void deleteEntry(DiaryEntry e) {
    user.deleteEntry(e.id);
    _refresh();
  }

  void restoreEntry(DiaryEntry e) {
    user.restoreEntry(e.id);
    _refresh();
  }

  /// Je hele dag van gisteren kopiëren (alle maaltijden, zonder supplementen). Geeft het aantal regels terug.
  int copyDayFromYesterday() {
    final from = dayKey(_date.subtract(const Duration(days: 1)));
    var n = 0;
    for (final m in Meal.values) {
      n += user.copyMeal(fromDay: from, meal: m, toDay: day);
    }
    _refresh();
    return n;
  }

  /// Wat je meestal eet bij [meal]: producten die je de afgelopen 30 dagen op minstens 3 dagen bij die maaltijd
  /// logde, met de hoeveelheid van de laatste keer. Zonder wat vandaag al in die maaltijd staat.
  List<DiaryEntry> usualFor(Meal meal, {int limit = 3}) {
    final today = _dateOnly(DateTime.now());
    final history = user.entriesBetween(dayKey(today.subtract(const Duration(days: 30))), dayKey(today.subtract(const Duration(days: 1))));
    final days = <String, Set<String>>{};
    final last = <String, DiaryEntry>{};
    for (final e in history) {
      if (e.meal != meal || e.foodRef.startsWith('supp:')) continue;
      days.putIfAbsent(e.foodRef, () => {}).add(e.day);
      final prev = last[e.foodRef];
      if (prev == null || e.day.compareTo(prev.day) >= 0) last[e.foodRef] = e;
    }
    final already = {for (final e in entriesFor(meal)) e.foodRef};
    final ranked = days.entries.where((e) => e.value.length >= 3 && !already.contains(e.key)).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return [for (final e in ranked.take(limit)) last[e.key]!];
  }

  /// Een eerder gelogde regel opnieuw toevoegen (zelfde hoeveelheid) aan [meal] op de gekozen dag.
  void addAgain(DiaryEntry e, Meal meal) => addFood(foodFor(e), meal: meal, grams: e.grams, quantity: e.quantity, portionLabel: e.portionLabel);

  int copyMealFromYesterday(Meal meal) {
    final n = user.copyMeal(fromDay: dayKey(_date.subtract(const Duration(days: 1))), meal: meal, toDay: day);
    _refresh();
    return n;
  }

  static ItemTemplate templateOf(DiaryEntry e) => ItemTemplate(
    foodRef: e.foodRef,
    name: e.name,
    brand: e.brand,
    grams: e.grams,
    quantity: e.quantity,
    portionLabel: e.portionLabel,
    per100g: e.per100g,
  );

  // ── Opgeslagen maaltijden ──

  List<SavedMeal> savedMeals() => user.savedMeals();

  void saveMealFromDiary(String name, Meal meal) {
    user.saveMeal(name, [for (final e in entriesFor(meal)) templateOf(e)]);
    notifyListeners();
  }

  void addSavedMeal(SavedMeal m, Meal meal) {
    for (final i in m.items) {
      user.addTemplate(day, meal, i);
    }
    _refresh();
  }

  void deleteSavedMeal(SavedMeal m) {
    user.deleteMeal(m.id);
    notifyListeners();
  }

  // ── Terugkerende items ──

  List<RepeatItem> repeats() => user.repeats();

  void addRepeat(DiaryEntry e, int weekdays) {
    user.saveRepeat(mealIndex: e.meal.index, item: templateOf(e), weekdays: weekdays, startDay: dayKey(_date.add(const Duration(days: 1))));
    notifyListeners();
  }

  void deleteRepeat(RepeatItem r) {
    user.deleteRepeat(r.id);
    notifyListeners();
  }

  // ── Recepten ──

  List<Recipe> recipes() => user.recipes();

  void saveRecipe(Recipe r) {
    user.saveRecipe(r);
    notifyListeners();
  }

  // ── Beweging ──

  void addExercise(String name, double kcal, {double? minutes}) {
    user.addExercise(day: day, name: name, kcal: kcal, minutes: minutes);
    _refresh();
  }

  void updateExercise(Exercise e, {required String name, required double kcal, double? minutes}) {
    user.updateExercise(e.id, name: name, kcal: kcal, minutes: minutes);
    _refresh();
  }

  void deleteExercise(Exercise e) {
    user.deleteExercise(e.id);
    _refresh();
  }

  // ── Lichaamsmetingen ──

  /// Laatste gewicht (uit de metingen), of het gewicht uit het profiel.
  double get currentWeight {
    final h = user.biometricHistory('weight');
    return h.isEmpty ? _profile.weightKg : h.last.value;
  }

  void addBiometric(String type, double value, {double? value2}) {
    user.addBiometric(day: day, type: type, value: value, value2: value2);
    // Een nieuw gewicht vandaag of later geldt meteen voor de berekening van de doelen
    if (type == 'weight' && !_date.isBefore(_dateOnly(DateTime.now()))) {
      saveProfile(_profile.copyWith(weightKg: value));
      return;
    }
    _refresh();
  }

  /// Na het overnemen uit Health Connect: alles opnieuw tonen; een nieuw gewicht van vandaag geldt meteen voor je doelen.
  void healthImported({String? latestWeightDay}) {
    if (latestWeightDay != null && latestWeightDay == dayKey(DateTime.now())) {
      saveProfile(_profile.copyWith(weightKg: currentWeight));
      return;
    }
    _targetsVersion++;
    _refresh();
  }

  void deleteBiometric(Biometric b) {
    user.deleteBiometric(b.id);
    _refresh();
  }

  List<BiometricType> biometricTypes() {
    final custom = ((user.setting('customBiometrics')?['types'] as List?) ?? const []).map(
      (t) => BiometricType.custom((t as Map)['name'] as String, t['unit'] as String),
    );
    return [...BiometricType.builtIn, ...custom];
  }

  /// Gegevens uit Cronometer of MyFitnessPal bewaren (zie lib/import). Eigen metingen die nog niet bestaan,
  /// worden aangemaakt. Geeft (toegevoegd, al aanwezig) terug.
  (int, int) importBatch(ImportBatch batch) {
    final known = {for (final t in biometricTypes()) t.key};
    for (final b in batch.biometrics) {
      if (b.type.startsWith('custom:') && known.add(b.type)) {
        final list = [...((user.setting('customBiometrics')?['types'] as List?) ?? const [])];
        list.add({'name': b.type.substring(7), 'unit': b.unit ?? ''});
        user.setSetting('customBiometrics', {'types': list});
      }
    }
    final result = user.importBatch(batch);
    _refresh();
    return result;
  }

  void addCustomBiometricType(String name, String unit) {
    final list = [...((user.setting('customBiometrics')?['types'] as List?) ?? const [])];
    list.add({'name': name, 'unit': unit});
    user.setSetting('customBiometrics', {'types': list});
    notifyListeners();
  }

  // ── Notities ──

  void setNote(String text) {
    user.setNote(day, text);
    _note = text;
    notifyListeners();
  }

  // ── Vasten ──

  Fast? get currentFast => user.currentFast();

  void startFast(double goalHours, {DateTime? start}) {
    user.startFast(start ?? DateTime.now(), goalHours);
    notifyListeners();
  }

  void endFast(Fast f) {
    user.endFast(f.id, DateTime.now());
    notifyListeners();
  }

  void cancelFast(Fast f) {
    user.deleteFast(f.id);
    notifyListeners();
  }

  // ── Trends ──

  /// Totalen per dag tussen twee dagen (alleen dagen waarop iets gegeten is).
  Map<String, NutrientTotals> dailyTotals(DateTime from, DateTime to) {
    final byDay = <String, List<DiaryEntry>>{};
    for (final e in user.entriesBetween(dayKey(from), dayKey(to))) {
      byDay.putIfAbsent(e.day, () => []).add(e);
    }
    return {for (final e in byDay.entries) e.key: NutrientTotals.sumOf(e.value.map((x) => withDerived(x.amounts)))};
  }

  // ── Level en avatar ──

  LevelInfo? _level;

  /// Je level en XP, uit wat je in de app logde (zie levels.dart voor de regels).
  LevelInfo get level => _level ??= _computeLevel();

  LevelInfo _computeLevel() {
    final today = dayKey(DateTime.now());
    final byDay = <String, List<DiaryEntry>>{};
    final withFood = <String>{};
    for (final (e, created) in user.entriesWithCreatedAt()) {
      if (e.day.compareTo(today) > 0 || !countsForXp(id: e.id, day: e.day, createdAtMs: created)) continue;
      byDay.putIfAbsent(e.day, () => []).add(e);
      if (!e.foodRef.startsWith('supp:')) withFood.add(e.day);
    }
    // Per dag de score en de badge-gegevens onthouden zolang de regels van die dag en je doelen niet veranderen
    DayStat stat(String d) {
      final entries = byDay[d]!;
      final sig = '$_targetsVersion|${entries.map((e) => '${e.id}:${e.grams}').join(',')}';
      final hit = _dayScores[d];
      if (hit != null && hit.$1 == sig) return hit.$2;
      final v = NutrientTotals.sumOf(entries.map((x) => withDerived(x.amounts))).values;
      final t = targetsForDate(parseDay(d));
      bool ok(String k) => t[k] != null && levelOf(v[k] ?? 0, t[k]) == Level.ok;
      final o6 = v['omega6'], o3 = v['omega3'];
      final s = DayStat(
        score: completenessScore(v, t),
        vitD: ok('vit_d'),
        fiber: (v['fiber'] ?? 0) >= (t['fiber']?.goal ?? 25),
        iron: ok('iron'),
        omega: o6 != null && o3 != null && o3 > 0 && o6 / o3 <= 4,
        protein: t['protein']?.goal != null && (v['protein'] ?? 0) >= t['protein']!.goal! * 0.95,
        foods: {
          for (final e in entries)
            if (!e.foodRef.startsWith('supp:')) e.foodRef,
        },
      );
      _dayScores[d] = (sig, s);
      return s;
    }

    _dayStats = {for (final d in withFood) d: stat(d)};
    final bonus = (user.setting('xp_bonus')?['xp'] as num?)?.toInt() ?? 0;
    return levelFromScores({for (final e in _dayStats.entries) e.key: e.value.score}, bonus: bonus);
  }

  final _dayScores = <String, (String, DayStat)>{};
  Map<String, DayStat> _dayStats = const {};

  /// Badge-gegevens per dag (dagen die meetellen voor XP).
  Map<String, DayStat> get dayStats {
    level;
    return _dayStats;
  }

  /// Battlepunten van de week die op [monday] begint: som van de dagscores (op tijd gelogd), en het deel van
  /// maandag tot en met woensdag.
  ({int points, int mid}) battlePoints(DateTime monday) {
    var points = 0, mid = 0;
    for (var i = 0; i < 7; i++) {
      final s = dayStats[dayKey(DateTime(monday.year, monday.month, monday.day + i))]?.score ?? 0;
      points += s;
      if (i < 3) mid += s;
    }
    return (points: points, mid: mid);
  }

  /// Gekozen titel (sleutel uit badges.dart), bewaard bij je account.
  String get title => (user.setting('title')?['id'] as String?) ?? 'rookie';

  /// Gescande producten (Scan-tab), nieuwste eerst: (barcode, naam, moment). Bewaard bij je account.
  List<(String, String, DateTime)> get scans => [
    for (final x in (user.setting('scans')?['items'] as List?) ?? const [])
      ((x as Map)['code'] as String, x['name'] as String? ?? '', DateTime.fromMillisecondsSinceEpoch((x['at'] as num).toInt())),
  ];

  /// Aantal verschillende producten ooit gescand (voor de badge).
  int get scannedCount => (user.setting('scans')?['count'] as num?)?.toInt() ?? 0;

  void addScan(String code, String name) {
    final items = [
      for (final x in (user.setting('scans')?['items'] as List?) ?? const [])
        if ((x as Map)['code'] != code) x,
    ];
    final isNew = !(((user.setting('scans')?['seen'] as List?) ?? const []).contains(code));
    final seen = [...((user.setting('scans')?['seen'] as List?) ?? const []), if (isNew) code];
    user.setSetting('scans', {
      'items': [
        {'code': code, 'name': name, 'at': DateTime.now().millisecondsSinceEpoch},
        ...items.take(99),
      ],
      'count': scannedCount + (isNew ? 1 : 0),
      // Alleen de laatste 1000 barcodes onthouden om dubbels te herkennen
      'seen': seen.length > 1000 ? seen.sublist(seen.length - 1000) : seen,
    });
    notifyListeners();
  }

  /// Je allergieën (bewaard bij je account). Leeg = geen meldingen.
  Set<Allergen> get allergies => {
    for (final n in (user.setting('allergies')?['list'] as List?) ?? const [])
      if (Allergen.values.any((a) => a.name == n)) Allergen.values.byName(n as String),
  };

  /// Al gevraagd bij het aanmaken van je profiel (of later aangepast)?
  bool get allergiesAsked => user.setting('allergies') != null;

  void setAllergies(Set<Allergen> list) {
    user.setSetting('allergies', {
      'list': [for (final a in list) a.name],
    });
    _suggested = false;
    notifyListeners();
  }

  /// Gekozen showcase-badges (categorieën), bewaard bij je account.
  List<String> get showcase => [for (final x in (user.setting('showcase')?['ids'] as List?) ?? const []) x as String];

  void setShowcase(List<String> ids) {
    user.setSetting('showcase', {'ids': ids.take(3).toList()});
    notifyListeners();
  }

  void setTitle(String id) {
    user.setSetting('title', {'id': id});
    notifyListeners();
  }

  int _targetsVersion = 0;

  /// Je profielfoto of standaardavatar: `preset:3` of `jpg:` met base64 erachter (null = nog niets gekozen).
  String? get avatar => user.setting('avatar')?['value'] as String?;

  void setAvatar(String? value) {
    user.setSetting('avatar', {'value': value});
    notifyListeners();
  }

  /// Dagen op rij gelogd (tot vandaag of gisteren) en de langste reeks ooit.
  /// Voor het widget op het startscherm: kcal over vandaag (doel min gegeten), het doel en of je vandaag al logde.
  ({int left, int goal, bool loggedToday}) get todaySummary {
    final now = DateTime.now();
    final key = dayKey(now);
    final burned = user.exerciseKcalBetween(key, key)[key] ?? 0;
    final goal = targetsForDate(now, burned: burned)['energy']?.goal ?? 0;
    final eaten = dailyTotals(now, now)[key]?.values['energy'] ?? 0;
    return (left: (goal - eaten).round(), goal: goal.round(), loggedToday: user.loggedDays().contains(key));
  }

  ({int current, int longest}) get streak => loggingStreak(user.loggedDays(), DateTime.now());

  /// Gemiddelde volledigheidsscore van de week die op [monday] begint, over de dagen waarop iets gelogd is
  /// (tot en met vandaag). Null als er die week nog niets gelogd is.
  ({int score, int days})? weekScore(DateTime monday) {
    final today = DateTime.now();
    var end = monday.add(const Duration(days: 6));
    if (end.isAfter(today)) end = today;
    if (end.isBefore(monday)) return null;
    final daily = dailyTotals(monday, end);
    if (daily.isEmpty) return null;
    final scores = [for (final e in daily.entries) completenessScore(e.value.values, targetsForDate(DateTime.parse(e.key)))];
    return (score: (scores.reduce((a, b) => a + b) / scores.length).round(), days: scores.length);
  }

  // ── Voedingsmiddelen ──

  /// Het volledige voedingsmiddel achter een dagboekregel (met porties), of een reconstructie uit de regel zelf.
  Food foodFor(DiaryEntry e) {
    final ref = e.foodRef;
    final found = FoodDb.isDbRef(ref) ? foods.byRef(ref) : user.food(ref);
    // Niet (meer) gevonden: reconstrueren uit de dagboekregel zelf (bv. "usda:<nummer>" uit de eerste versie)
    final source = ref.startsWith('usda') || ref.startsWith('fdc:') ? FoodSource.usda : (ref.startsWith('off:') ? FoodSource.off : FoodSource.custom);
    return found ?? Food(ref: ref, name: e.name, brand: e.brand, source: source, per100g: e.per100g);
  }

  List<Food> recentFoods() => [for (final e in user.recent()) foodFor(e)];

  /// Lokaal zoeken: eigen producten en recepten eerst, dan de ingebouwde database.
  List<Food> searchLocal(String q) {
    final all = [...user.searchSaved(q), ...foods.search(q)];
    // Favorieten eerst
    final fav = favoriteRefs.toSet();
    return [...all.where((f) => fav.contains(f.ref)), ...all.where((f) => !fav.contains(f.ref))];
  }

  // ── Favorieten (gesynchroniseerd) ──

  List<String> get favoriteRefs => [for (final r in (user.setting('favorites')?['list'] as List?) ?? const []) r as String];

  bool isFavorite(String ref) => favoriteRefs.contains(ref);

  void toggleFavorite(Food f) {
    final list = favoriteRefs;
    if (list.remove(f.ref)) {
      user.setSetting('favorites', {'list': list});
    } else {
      // Merk- en eigen producten lokaal bewaren, zodat ze ook offline en op andere toestellen terug te vinden zijn
      if (!FoodDb.isDbRef(f.ref) && f.source != FoodSource.recipe) user.saveFood(f);
      user.setSetting('favorites', {
        'list': [f.ref, ...list],
      });
    }
    notifyListeners();
  }

  /// Je favoriete producten, laatst toegevoegd eerst.
  List<Food> favorites() => [for (final r in favoriteRefs) ?(FoodDb.isDbRef(r) ? foods.byRef(r) : user.food(r))];

  /// Product op barcode: eerst lokaal (eigen of eerder opgezocht), anders Open Food Facts.
  Future<Food?> lookupBarcode(String code) async {
    final local = user.foodByBarcode(code);
    if (local != null) return local.source == FoodSource.off ? completeOff(local) : local;
    final Food? found;
    try {
      found = await off.product(code);
    } on OffException {
      // Geen internet: dan uit een eerdere scan
      final cached = cachedProduct(code)?.food;
      if (cached != null) return cached;
      rethrow;
    }
    if (found != null) return completeOff(found);
    // Niet in Open Food Facts: dan USDA Branded Foods (vooral Amerikaanse producten)
    return (await fdc.product(code))?.food;
  }

  /// Alles over een gescand product voor de Scan-tab: eerst Open Food Facts, anders USDA.
  ///
  /// Gescande producten blijven op dit toestel bewaard (de laatste [_scanCacheMax]), zodat scannen in de winkel
  /// ook zonder internet werkt.
  Future<ProductInfo?> productInfo(String code) async {
    try {
      final p = await off.productInfoRaw(code);
      if (p != null) {
        _cacheScan(code, {'src': 'off', 'data': p});
        return ProductInfo.fromOff(p, foodFromOff(p));
      }
    } on OffException {
      final cached = cachedProduct(code);
      if (cached != null) return cached.asOffline();
      rethrow;
    }
    final j = await fdc.raw(code);
    if (j == null) return null;
    _cacheScan(code, {'src': 'usda', 'data': j});
    return productFromFdc(j);
  }

  /// Betere keuzes voor een product: tot 3 gelijkaardige producten met een duidelijk hogere productscore.
  Future<List<(ProductInfo, int)>> betterAlternatives(ProductInfo p, AdditiveCatalog catalog) async {
    final mine = p.score(catalog) ?? 0;
    final codes = await off.betterCandidates(p);
    final infos = await Future.wait([for (final c in codes) off.productInfo(c).then<ProductInfo?>((v) => v).catchError((Object _) => null)]);
    final out = <(ProductInfo, int)>[];
    for (final i in infos.nonNulls) {
      final s = i.score(catalog);
      if (s != null && s >= mine + 10 && s >= 50 && hitsForAllergies(i).isEmpty) out.add((i, s));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out.take(3).toList();
  }

  /// Bevat dit product iets waarvoor je allergisch bent (volgens etiket of naam)?
  List<AllergenHit> hitsForAllergies(ProductInfo i) => allergenHits(
    allergies,
    name: '${i.name} ${i.brand ?? ''}',
    label: LabelInfo(allergens: i.allergenTags, traces: i.traceTags, ingredients: i.ingredients),
  );

  static const _scanCacheMax = 200;

  void _cacheScan(String code, Map<String, Object?> value) {
    user.setSetting('_scan:$code', value);
    final index = [
      for (final c in (user.setting('_scan_index')?['codes'] as List?) ?? const [])
        if (c != code) c as String,
      code,
    ];
    while (index.length > _scanCacheMax) {
      user.deleteSetting('_scan:${index.removeAt(0)}');
    }
    user.setSetting('_scan_index', {'codes': index});
  }

  /// Bewaarde productgegevens van een eerdere scan, of null.
  ProductInfo? cachedProduct(String code) {
    final c = user.setting('_scan:$code');
    final data = (c?['data'] as Map?)?.cast<String, Object?>();
    if (data == null) return null;
    return c!['src'] == 'usda' ? productFromFdc(data) : ProductInfo.fromOff(data, foodFromOff(data));
  }

  /// Ontbrekende waarden van een merkproduct schatten uit het gekoppelde basisproduct (zie estimate.dart).
  Food enrich(Food f) {
    final proxy = f.proxyRef;
    if (proxy == null || proxy.isEmpty || f.estimated.isNotEmpty) return f;
    final donor = foods.byRef(proxy);
    if (donor == null) return f;
    final (values, estimated) = estimateMissing(f.per100g, donor.per100g, donor.ref);
    return f.copyWith(per100g: values, estimated: estimated);
  }

  /// Merkproduct volledig maken: zo nodig de volledige productgegevens ophalen (zoekresultaten bevatten de
  /// koppeling met het basisproduct niet), aanvullen, lokaal bewaren en bestaande dagboekregels bijwerken.
  Future<Food> completeOff(Food f) async {
    if (f.source != FoodSource.off) return f;
    var full = f;
    if (f.proxyRef == null && f.barcode != null) {
      try {
        final fetched = await off.product(f.barcode!);
        // Lege koppeling = gecontroleerd, maar OFF kent geen basisproduct: niet elke keer opnieuw vragen
        full = (fetched ?? f).copyWith(proxyRef: fetched?.proxyRef ?? '');
      } on OffException {
        return enrich(f);
      }
    }
    final enriched = enrich(full);
    user.saveFood(enriched);
    if (enriched.estimated.isNotEmpty && user.fillDiarySnapshots(enriched.ref, enriched.per100g) > 0) _refresh();
    return enriched;
  }

  void saveCustomFood(Food f) {
    user.saveFood(f);
    notifyListeners();
  }

  void deleteCustomFood(Food f) {
    user.deleteFood(f.ref);
    notifyListeners();
  }
}
