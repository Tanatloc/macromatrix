/// Centrale toestand van de app: gekozen dag, dagboek, profiel, richtwaarden en alles rond de dag
/// (beweging, metingen, notities, vasten, terugkerende items).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../day_clock.dart';
export '../day_clock.dart';
import '../data/food.dart';
import '../i18n.dart';
import '../data/food_db.dart';
import '../data/models.dart';
import '../data/plan.dart';
import '../data/off_client.dart';
import '../data/fdc_client.dart';
import '../data/product_info.dart';
import '../data/search_terms.dart';
import '../data/user_db.dart';
import '../import/importer.dart';
import '../labs/lab_report.dart';
import '../labs/supplement_advice.dart';
import '../nutrition/estimate.dart';
import '../nutrition/allergens.dart';
import '../nutrition/badges.dart';
import '../nutrition/bioavailability.dart';
import '../nutrition/food_groups.dart';
import '../nutrition/free_sugars.dart';
import '../nutrition/gap_plan.dart';
import '../nutrition/health.dart';
import '../nutrition/insights.dart';
import '../nutrition/quick_parse.dart';
import '../nutrition/report.dart';
import '../nutrition/levels.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/preferences.dart';
import '../nutrition/portions.dart' show EverydayPortion, everydayPortions, typicalPieceGrams;
import '../nutrition/processing.dart';
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

/// Rangschikking in het Orakel.
enum OracleRank {
  per100g('per 100 g', 'per 100 g'),
  per100kcal('per 100 kcal', 'per 100 kcal'),
  perPortion('per serving', 'per portie');

  const OracleRank(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

/// Wat [AppState.addFood] deed: een nieuwe regel, of de hoeveelheid erbij in een bestaande regel
/// (dan met de hoeveelheid van daarvoor, om het ongedaan te kunnen maken).
class AddedEntry {
  const AddedEntry(this.id, {this.prevGrams, this.prevQuantity});
  final String id;
  final double? prevGrams, prevQuantity;
  bool get merged => prevGrams != null;
}

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
    dayStartHour = ((user.setting('ui')?['dayStart'] as num?)?.toInt() ?? 3).clamp(0, 5);
    // De gekozen taal blijft na een herstart (werd wel bewaard maar nooit teruggelezen)
    if (AppLang.values.asNameMap()[user.setting('ui')?['lang']] case final lang? when lang != appLang.value) setAppLang(lang);
    _preferences = {for (final n in ((user.setting('preferences')?['list'] as List?) ?? const [])) ?DietPref.values.asNameMap()[n]};
  }

  /// Alles opnieuw inlezen, bv. nadat de synchronisatie wijzigingen van een ander toestel binnenhaalde.
  void reloadFromDisk() {
    _targetsVersion++;
    _frozenCache = null;
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

  DateTime _date = _dateOnly(logicalNow());
  DateTime get date => _date;
  String get day => dayKey(_date);
  bool get isToday => _date == _dateOnly(logicalNow());

  /// Maaltijd om iets aan toe te voegen: vandaag volgens de klok; op een andere dag de eerste maaltijd die nog leeg is,
  /// want wie 's avonds gisteren invult, begint niet bij het avondeten.
  Meal get suggestedMeal {
    if (isToday) return Meal.forHour(DateTime.now().hour);
    final used = {for (final e in _entries) e.meal};
    return Meal.values.firstWhere((m) => !used.contains(m), orElse: () => Meal.snacks);
  }

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
    if (!_date.isAfter(_dateOnly(logicalNow()))) user.applyRepeats(day, _date);
    // Automatische supplementen: alleen vandaag aanvinken, en nooit opnieuw als je ze zelf afvinkte
    if (_date == _dateOnly(logicalNow())) {
      for (final sup in supplements) {
        if (sup.auto && day.compareTo(sup.since ?? day) >= 0 && !user.hasSupplementRow(day, sup)) user.setSupplementTaken(day, sup, true);
      }
    }
    _level = null;
    _entries = user.entriesFor(day);
    _totals = NutrientTotals.sumOf(_entries.map(entryValues));
    _exercise = user.exerciseFor(day);
    _biometrics = user.biometricsFor(day);
    _note = user.note(day);
    _targets = targetsForDate(_date, burned: burnedKcal);
    _defaultTargets = targetsFor(
      profileFor(_date),
      year: _date.year,
      extraKcal: _extraKcal(burnedKcal, profileFor(_date), _date.year, _frozenFor(_date)?.$2),
      tdee: adaptiveTdee,
    );
  }

  /// Beweging bij het doel optellen. Je activiteitsniveau rekent al een deel beweging in (de factor boven zittend),
  /// dus we tellen alleen de verbranding daarboven erbij. Zo telt een training niet dubbel.
  double _extraKcal(double burned, Profile p, int year, [TargetSettings? settings]) {
    if (!(settings ?? _settings).addExercise || adaptiveTdee != null) return 0;
    final alreadyInFactor = bmr(p, p.ageIn(year)) * (p.activity.factor - Activity.sedentary.factor);
    return math.max(0, burned - alreadyInFactor);
  }

  /// Hoeveel kcal beweging vandaag echt bij je doel komt (de verbranding boven wat je activiteitsniveau al inrekent).
  double get exerciseKcalInGoal => _extraKcal(burnedKcal, profileFor(_date), _date.year, _frozenFor(_date)?.$2);

  /// Profiel voor een dag, met de macroverdeling van het weekschema als die er is. Een vroegere dag met bevroren
  /// doelen houdt het profiel van toen.
  Profile profileFor(DateTime d) {
    if (_frozenFor(d) case (final p, _)) return p;
    final s = _settings.schedule[d.weekday];
    return s == null ? _profile : _profile.copyWith(proteinPct: s.$1, carbsPct: s.$2, fatPct: s.$3);
  }

  /// Richtwaarden voor een dag: profiel, weekschema, beweging en eigen doelen. Dé berekening voor elk scherm.
  Map<String, Target> targetsForDate(DateTime d, {double burned = 0}) {
    final settings = _frozenFor(d)?.$2 ?? _settings;
    final p = profileFor(d);
    // Een eigen eiwitdoel telt ook in de verdeling: koolhydraten en vet delen wat daarna overblijft
    final t = targetsFor(
      p,
      year: d.year,
      extraKcal: _extraKcal(burned, p, d.year, settings),
      tdee: adaptiveTdee,
      proteinGoal: settings.overrides['protein']?.goal,
    );
    final out = {...t, ...settings.overrides}..removeWhere((k, _) => hiddenNutrients.contains(k));
    // Vrije suikers zijn een deel van alle suikers: hun grens ligt nooit hoger dan een eigen grens voor alle suikers
    final all = out['sugars']?.upper, free = out['free_sugars'];
    if (all != null && free?.upper != null && free!.upper! > all) out['free_sugars'] = Target(goal: free.goal, upper: all);
    return out;
  }

  DateTime get _today => _dateOnly(logicalNow());

  double _burnedOn(DateTime d) => d == _date ? burnedKcal : user.exerciseFor(dayKey(d)).fold(0.0, (a, e) => a + e.kcal);

  /// Doelen van vandaag, los van de dag die op Vandaag of het Dashboard openstaat: het Profiel toont altijd deze.
  Map<String, Target> get todayTargets => _date == _today ? _targets : targetsForDate(_today, burned: _burnedOn(_today));

  /// Hoeveel kcal beweging vandaag bij je doel komt (zoals [exerciseKcalInGoal], maar altijd voor vandaag).
  double get todayExerciseKcalInGoal => _extraKcal(_burnedOn(_today), profileFor(_today), _today.year);

  /// Onderhoudsenergie waarop het eiwitdoel van vandaag rust (zie maintenanceKcal).
  double get todayMaintenanceKcal => maintenanceKcal(profileFor(_today), _today.year, extraKcal: todayExerciseKcalInGoal, tdee: adaptiveTdee);

  /// Doelen per dag voor een overzicht (week, maand, laatste 7 dagen), met de beweging van die dag: een vroegere
  /// dag houdt het doel dat toen gold.
  Map<String, Map<String, Target>> targetsBetween(DateTime from, DateTime to) {
    final burned = user.exerciseKcalBetween(dayKey(from), dayKey(to));
    // In UTC rekenen: een dag met zomeruur heeft 23 uur
    final days = DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
    return {
      for (var i = 0; i <= days; i++)
        dayKey(DateTime(from.year, from.month, from.day + i)): targetsForDate(
          DateTime(from.year, from.month, from.day + i),
          burned: burned[dayKey(DateTime(from.year, from.month, from.day + i))] ?? 0,
        ),
    };
  }

  // ── Doelen van vroegere dagen bevriezen ──
  //
  // Wie zijn doel of macroschema wijzigt, wil niet dat vorige dagen opeens anders beoordeeld worden (keto-maandag
  // die een oude gewone maandag rood kleurt, XP die daalt). Vlak vóór elke wijziging van profiel of doelen bewaren we
  // daarom voor elke al gelogde vroegere dag zonder bevroren doelen het profiel (met weekschema) en de doelinstellingen
  // die toen golden. Identieke plannen worden één keer bewaard. Vandaag blijft altijd de huidige instellingen volgen.

  Map<String, (Profile, TargetSettings)>? _frozenCache;

  Map<String, (Profile, TargetSettings)> get _frozen {
    if (_frozenCache case final c?) return c;
    final raw = (user.setting('frozenTargets') ?? const {}) as Map;
    final plans = [
      for (final x in (raw['plans'] as List? ?? const []))
        (
          Profile.fromJson(((x as Map)['profile'] as Map).cast<String, Object?>()),
          TargetSettings.fromJson((x['settings'] as Map).cast<String, Object?>()),
        ),
    ];
    return _frozenCache = {
      for (final e in ((raw['days'] as Map?) ?? const {}).entries)
        if ((e.value as num).toInt() < plans.length) e.key as String: plans[(e.value as num).toInt()],
    };
  }

  (Profile, TargetSettings)? _frozenFor(DateTime d) {
    final key = dayKey(d);
    if (key.compareTo(dayKey(logicalNow())) >= 0) return null;
    return _frozen[key];
  }

  void _freezePastDays() {
    final today = dayKey(logicalNow());
    final raw = (user.setting('frozenTargets') ?? const {}) as Map;
    final plans = [for (final x in (raw['plans'] as List? ?? const [])) jsonEncode(x)];
    final days = {for (final e in ((raw['days'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()};
    var changed = false;
    for (final d in user.loggedDays()) {
      if (d.compareTo(today) >= 0 || days.containsKey(d)) continue;
      final day = parseDay(d);
      final s = _settings.schedule[day.weekday];
      final profile = s == null ? _profile : _profile.copyWith(proteinPct: s.$1, carbsPct: s.$2, fatPct: s.$3);
      // Het weekschema zit al in het profiel; bewaar de instellingen zonder schema
      final plan = jsonEncode({'profile': profile.toJson(), 'settings': _settings.copyWith(schedule: const {}).toJson()});
      var i = plans.indexOf(plan);
      if (i < 0) {
        plans.add(plan);
        i = plans.length - 1;
      }
      days[d] = i;
      changed = true;
    }
    if (!changed) return;
    user.setSetting('frozenTargets', {
      'plans': [for (final p in plans) jsonDecode(p)],
      'days': days,
    });
    _frozenCache = null;
  }

  /// Voedingsstoffen die je niet wilt zien (bv. water als je dat niet bijhoudt).
  Set<String> get hiddenNutrients => _settings.trackWater ? const {} : const {'water'};

  // ── Verbruik uit gewicht en logboek ──

  EnergyEstimate? _estimate;
  bool _estimated = false;

  /// Geschat verbruik over de laatste 28 volledige dagen (null = te weinig gegevens).
  EnergyEstimate? get energyEstimate {
    if (_estimated) return _estimate;
    final today = _dateOnly(logicalNow());
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

  /// Licht, donker of zoals het toestel (opgeslagen als "light", "dark" of "system"); standaard licht.
  String get themeMode => (user.setting('ui')?['theme'] as String?) ?? 'light';

  /// Taal van de app (alleen op dit toestel).
  void setLanguage(AppLang lang) {
    user.setSetting('ui', {...?user.setting('ui'), 'lang': lang.name});
    setAppLang(lang);
  }

  /// Uur waarop een nieuwe dag begint; wie op "vandaag" stond, blijft op de dag die nu vandaag is.
  void setDayStart(int hour) {
    final wasToday = isToday;
    user.setSetting('ui', {...?user.setting('ui'), 'dayStart': hour});
    dayStartHour = hour;
    if (wasToday) _date = _dateOnly(logicalNow());
    _refresh();
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
  List<(Food, double)> richestFor(String key, {bool perKcal = false, int limit = 40, bool advice = false}) {
    final candidates = foods.richestIn(key, perKcal: perKcal, limit: advice ? math.max(300, limit * 15) : limit * 3);
    final outlier = _outlierCheck(key, candidates.take(math.min(candidates.length, limit * 6)).map((r) => r.$1));
    return [
      for (final r in candidates)
        if (!outlier(r.$1) &&
            (!advice || isAdviceFood(r.$1)) &&
            fitsPreferences(r.$1, _preferences) &&
            !containsAllergen(r.$1, allergies) &&
            !(r.$1.category ?? '').toLowerCase().contains('supplement') &&
            (key == 'sodium' || key == 'chloride' || !_salt.hasMatch(r.$1.name)))
          r,
    ].take(limit).toList();
  }

  /// Uitschieters tussen databanken: een waarde die veel hoger ligt dan hetzelfde voedingsmiddel (zelfde soort, groep
  /// en bereiding) in minstens twee andere databanken is bijna altijd een fout of een uitzonderlijk product (gebraden
  /// gans met 3600 mg kalium, eend zonder vel met 46,7 g eiwit tegenover 23–27 g elders). Voor hoofdbestanddelen
  /// (eiwit, vet, koolhydraten…) kan hetzelfde product geen 1,6× verschillen; vitaminen en mineralen wel meer, daar
  /// geldt 3×. Alleen nagaan voor [head] (de kop van de lijst): dat is wat bovenaan zou komen.
  bool Function(Food) _outlierCheck(String key, Iterable<Food> head) {
    final list = head.toList();
    final siblings = foods.siblingValues(key, {for (final f in list) ?f.label?.food});
    // Eiwit, koolhydraten en vezels liggen voor hetzelfde product dicht bij elkaar; vet en energie verschillen meer
    // (mager tegenover doorregen), vitaminen en mineralen het meest
    final factor = const {'protein', 'carbs', 'fiber', 'sugars', 'starch'}.contains(key)
        ? 1.4
        : const {'fat', 'energy', 'water', 'sfa', 'mufa', 'pufa'}.contains(key)
        ? 1.6
        : 3.0;
    return (Food f) {
      final l = f.label;
      if (l == null) return false;
      final own = withDerived(f.per100g)[key];
      // Vergelijk met dezelfde soort: verrijkt met verrijkt, met vel met met vel
      bool same(List<String> flags) => const ['fortified', 'with skin', 'without skin'].every((x) => flags.contains(x) == l.flags.contains(x));
      final others = [
        for (final (ref, v, flags) in siblings['${l.food}|${l.group}|${l.state}'] ?? const <(String, double, List<String>)>[])
          if (ref != f.ref && same(flags)) v,
      ]..sort();
      if (own == null || others.length < 2) return false;
      final median = others[others.length ~/ 2];
      return median > 0 && own > factor * median;
    };
  }

  /// "Orakel": de [limit] rijkste voedingsmiddelen voor een stof, gerangschikt per 100 g, per 100 kcal of per
  /// portie, eventueel alleen uit bepaalde voedingsgroepen ([groups], leeg = alles) en alleen gewone producten
  /// ([everyday]). Hetzelfde voedingsmiddel uit verschillende databanken telt één keer.
  ///
  /// Laat [everyday] van een gekozen groep niets over (eiwit in groenten: alleen poeders en meel), dan komen voor
  /// die groep toch de rijkste producten erin, en staat de groep in [relaxed] zodat het scherm dat kan zeggen. Het
  /// Orakel toonde anders "Top 0" (N12). Bij alle groepen samen geldt hetzelfde, met '' in [relaxed].
  List<(Food, double)> oracle(
    String key, {
    OracleRank rank = OracleRank.per100g,
    int limit = 25,
    Set<String> groups = const {},
    bool everyday = false,
    Set<String>? relaxed,
  }) {
    final perKcal = rank == OracleRank.per100kcal;
    // Met een groep dieper zoeken: de rijkste 1500 voor eiwit zijn vlees, vis en poeders, de eerste groente staat pas
    // rond plaats 40 en erwten of spinazie veel verder. Zoeken tot elke groep genoeg heeft (of alles bekeken is).
    final depths = groups.isEmpty ? [math.max(1500, limit * 30)] : [math.max(1500, limit * 30), 8000, 40000];
    var candidates = const <(Food, double)>[];
    var byGroup = <String, List<(Food, double)>>{};
    for (final depth in depths) {
      // Eén keer opgehaald, en een diepere lijst dient ook voor een minder diepe
      final cacheKey = '$key|$perKcal';
      final cached = _oraclePool;
      if (cached == null || cached.$1 != cacheKey || (cached.$2.length < depth && !cached.$3)) {
        final list = foods.richestIn(key, perKcal: perKcal, limit: depth);
        _oraclePool = (cacheKey, list, list.length < depth);
      }
      candidates = _oraclePool!.$2.take(depth).toList();
      byGroup = {
        for (final g in groups)
          g: [
            for (final r in candidates)
              if (r.$1.label?.group == g) r,
          ],
      };
      // Ruim genoeg: dezelfde producten uit meerdere databanken tellen één keer, en uitschieters vallen nog weg
      final enough = byGroup.values.every((l) => l.where((r) => !everyday || isAdviceFood(r.$1)).length >= limit * 3);
      if (enough || candidates.length < depth) break;
    }
    final pool = groups.isEmpty
        ? candidates
        : [
            for (final r in candidates)
              if (groups.contains(r.$1.label?.group)) r,
          ];
    // Uitschieters tussen databanken overslaan (zie [_outlierCheck]), gekeken naar de kop van wat getoond kan worden
    final outlier = _outlierCheck(key, pool.take(math.min(pool.length, limit * 6)).map((r) => r.$1));
    // Gedroogd zeewier en spirulina zijn voor eiwit, vezels en energie poeders, geen groente (100 g nori eet niemand)
    final macro = const {'protein', 'carbs', 'fiber', 'sugars', 'starch', 'fat', 'energy'}.contains(key);
    bool driedAlgae(Food f) =>
        RegExp(r'spirulina', caseSensitive: false).hasMatch(f.name) ||
        (f.label?.kind == 'algae' && f.label?.state == 'dried') ||
        RegExp(
          r'\b(seaweed|laver|nori|kelp|wakame|agar)\b.*\bdried\b|\bdried\b.*\b(seaweed|laver|nori|kelp|wakame)\b',
          caseSensitive: false,
        ).hasMatch(f.name);

    Map<Food, double> keep(Iterable<(Food, double)> from, {required bool everydayOnly}) {
      final kept = <Food, double>{};
      for (final (f, v) in from) {
        if (outlier(f) || _regional.hasMatch(f.name)) continue;
        if (everydayOnly && !isAdviceFood(f)) continue;
        if (macro && driedAlgae(f)) continue;
        if (!fitsPreferences(f, _preferences) || containsAllergen(f, allergies)) continue;
        if ((f.category ?? '').toLowerCase().contains('supplement') || f.label?.group == 'supplement') continue;
        if (key != 'sodium' && key != 'chloride' && _salt.hasMatch(f.name)) continue;
        kept[f] = rank == OracleRank.perPortion ? v * oraclePortion(f) / 100 : v;
      }
      return kept;
    }

    final kept = <Food, double>{};
    if (groups.isEmpty) {
      kept.addAll(keep(pool, everydayOnly: everyday));
      if (everyday && kept.isEmpty) {
        kept.addAll(keep(pool, everydayOnly: false));
        if (kept.isNotEmpty) relaxed?.add('');
      }
    } else {
      for (final g in groups) {
        final part = keep(byGroup[g]!, everydayOnly: everyday);
        if (everyday && part.isEmpty) {
          part.addAll(keep(byGroup[g]!, everydayOnly: false));
          if (part.isNotEmpty) relaxed?.add(g);
        }
        kept.addAll(part);
      }
    }
    final one = [for (final g in groupFoods(kept.keys.toList())) g.main];
    final ranked = [for (final f in one) (f, kept[f]!)]..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked.take(limit).toList();
  }

  // Laatst opgevraagde kandidaten van het Orakel: het scherm vraagt bij elke herbouw opnieuw, en dieper zoeken in
  // een groep (tot alle producten) kost een halve seconde. (stof, kandidaten, of dat alle producten zijn).
  (String, List<(Food, double)>, bool)? _oraclePool;

  /// Portie voor de rangschikking "per portie": de eerste herkenbare portie (5–400 g), anders 100 g.
  static double oraclePortion(Food f) => f.portions.where((p) => p.grams >= 5 && p.grams <= 400).firstOrNull?.grams ?? 100;

  /// Producten van één bevolkingsgroep in de Amerikaanse tabel (gedroogde walrus, Navajo-pijnboompitten): hier niet te koop.
  static final _regional = RegExp(r'Alaska Native|Navajo|Shoshone|Hopi|Apache|Northern Plains|Oogruk', caseSensitive: false);

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
  Recap? recap(DateTime from, DateTime to, {required bool year, bool withPrevious = true}) {
    final today = _dateOnly(logicalNow());
    final end = to.isAfter(today) ? today : to;
    if (end.isBefore(from)) return null;
    final entries = [
      for (final e in user.entriesBetween(dayKey(from), dayKey(end)))
        if (!e.foodRef.startsWith('supp:')) e,
    ];
    if (entries.isEmpty) return null;
    final daily = dailyTotals(from, end);
    final scores = <String, int>{};
    final dayKcal = <String, double>{};
    final sums = <String, double>{};
    var kcal = 0.0, goalKcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
    for (final e in daily.entries) {
      final t = targetsForDate(DateTime.parse(e.key));
      scores[e.key] = completenessScore(e.value.values, t);
      dayKcal[e.key] = e.value.values['energy'] ?? 0;
      kcal += e.value.values['energy'] ?? 0;
      goalKcal += t['energy']?.goal ?? 0;
      protein += e.value.values['protein'] ?? 0;
      carbs += e.value.values['carbs'] ?? 0;
      fat += e.value.values['fat'] ?? 0;
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
    final weakNutrient = candidates.isEmpty ? null : candidates.reduce((a, b) => b.value < a.value ? b : a);
    final macroKcal = protein * 4 + carbs * 4 + fat * 9;
    // Vorige maand of vorig jaar, even lang, voor ▲/▼
    final prevFrom = year ? DateTime(from.year - 1) : DateTime(from.year, from.month - 1);
    final prevTo = year ? DateTime(from.year - 1, 12, 31) : DateTime(from.year, from.month, 0);
    final previous = withPrevious ? recap(prevFrom, prevTo, year: year, withPrevious: false) : null;
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
      weakNutrient: weakNutrient == null || weakNutrient.key == topNutrient?.key
          ? null
          : (nutrientByKey[weakNutrient.key]!, weakNutrient.value / daily.length),
      dayScores: scores,
      dayKcal: dayKcal,
      kcalGoal: daily.isEmpty ? 0 : (goalKcal / daily.length).round(),
      split: macroKcal <= 0 ? null : (protein * 4 / macroKcal, carbs * 4 / macroKcal, fat * 9 / macroKcal),
      avgProtein: daily.isEmpty ? 0 : (protein / daily.length).round(),
      previous: previous,
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

  void restoreLab(String id) {
    user.undelete('labs', id);
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
    final today = _dateOnly(logicalNow());
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

  /// Weekrapport voor de week die op [monday] begint (null als je die week geen enkele volledige dag logde).
  /// Score, gemiddelden en gezondheidscheck volgen één regel: alleen volledig gelogde dagen ([isFullDay]) en nooit
  /// vandaag, want die dag loopt nog.
  WeeklyReport? weeklyReport(DateTime monday) {
    final today = dayKey(logicalNow());
    final sunday = dayKey(DateTime(monday.year, monday.month, monday.day + 6));
    // Gewichtstrend over deze en de vorige week: bij een stabiel gewicht ligt een groot energietekort eerder aan je
    // doel of aan wat je niet logt dan aan te weinig eten
    final trend = WeightTrend.of([
      for (final b in user.biometricHistory('weight', from: dayKey(DateTime(monday.year, monday.month, monday.day - 7))))
        if (b.day.compareTo(sunday) <= 0) (DateTime.parse(b.day), b.value),
    ]);
    ({
      int score,
      int days,
      int partial,
      Map<String, double> avg,
      Map<String, double> goals,
      Set<String> overUpper,
      List<(NutrientTotals, Map<String, Target>)> full,
      double kcal,
      double kcalGoal,
      HealthCheck? health,
    })?
    week(DateTime m) {
      final end = DateTime(m.year, m.month, m.day + 6);
      final daily = dailyTotals(m, end);
      final scores = <int>[];
      final sums = <String, double>{}, goalSums = <String, double>{}, valueSums = <String, double>{}, upperSums = <String, double>{};
      final withTargets = <(NutrientTotals, Map<String, Target>)>[];
      var kcal = 0.0, kcalGoal = 0.0, partial = 0;
      for (final e in daily.entries) {
        final t = targetsForDate(DateTime.parse(e.key));
        if (e.key.compareTo(today) >= 0 || !isFullDay(e.value, t)) {
          partial++;
          continue;
        }
        withTargets.add((e.value, t));
        scores.add(completenessScore(e.value.values, t));
        kcal += e.value['energy'];
        kcalGoal += t['energy']?.goal ?? 0;
        for (final k in [...stripKeys, 'energy', 'protein']) {
          final g = t[k]?.goal;
          if (g != null && g > 0) {
            sums[k] = (sums[k] ?? 0) + (e.value.values[k] ?? 0) / g;
            goalSums[k] = (goalSums[k] ?? 0) + g;
          }
          if (t[k]?.upper case final u?) {
            valueSums[k] = (valueSums[k] ?? 0) + (e.value.values[k] ?? 0);
            upperSums[k] = (upperSums[k] ?? 0) + u;
          }
        }
      }
      if (scores.isEmpty) return null;
      final n = scores.length;
      return (
        score: (scores.reduce((a, b) => a + b) / n).round(),
        days: n,
        partial: partial,
        avg: {for (final e in sums.entries) e.key: e.value / n},
        goals: {for (final e in goalSums.entries) e.key: e.value / n},
        // Gemiddeld boven de veilige bovengrens: dat hoort niet bij "je sterkste"
        overUpper: {
          for (final e in valueSums.entries)
            if (e.value > upperSums[e.key]!) e.key,
        },
        full: withTargets,
        kcal: kcal / n,
        kcalGoal: kcalGoal / n,
        health: healthCheck(
          withTargets,
          weightKg: currentWeight,
          age: _profile.ageIn(m.year),
          heightCm: _profile.heightCm,
          trains: _trainsIn(m),
          labs: latestLabs(at: end),
          activity: _activityIn(m),
          // De trend hoort bij deze week; de vorige week (alleen voor de vergelijking) krijgt ze niet
          weightTrend: m == monday ? trend : null,
          plan: _profile.goal,
        ),
      );
    }

    final now = week(monday);
    if (now == null) return null;
    final prev = week(DateTime(monday.year, monday.month, monday.day - 7));
    final micros = [
      for (final e in now.avg.entries)
        if (stripKeys.contains(e.key)) e,
    ]..sort((a, b) => b.value.compareTo(a.value));
    // Eerst een duidelijk energie- of eiwitprobleem, dan de zwakste vitaminen en mineralen
    final worst = attentionOrder(now.avg, micros.reversed.toList());
    final energy = now.avg['energy'] ?? 1;
    final energyOff = energy < reportEnergyLow || energy > reportEnergyHigh;
    // Tip: een gewoon product dat je zwakste stof flink aanvult. Bij een duidelijk energieprobleem geen product-tip:
    // dan toont het rapport eerst dat (een wortel lost een tekort van 800 kcal niet op)
    WeeklyTip? tip;
    for (final w in energyOff ? const <MapEntry<String, double>>[] : worst) {
      final goal = _targets[w.key]?.goal;
      if (goal == null || w.key == 'energy' || w.key == 'sodium') continue;
      final upper = _targets[w.key]?.upper;
      for (final (f, per100) in richestFor(w.key, limit: 40, advice: true)) {
        if (!isAdviceFood(f)) continue;
        // Een gewone portie (of 100 g) die een flink deel van je doel geeft, zonder de bovengrens te halen
        final portion = f.portions.where((p) => p.grams >= 30 && p.grams <= 250).firstOrNull;
        final grams = portion?.grams ?? 100;
        final frac = per100 * grams / 100 / goal;
        if (frac < 0.25 || frac > 1.5 || (upper != null && per100 * grams / 100 > upper)) continue;
        // Nooit een zout product (gezouten makreel, ansjovis) aanraden, en zeker niet als je al genoeg zout eet
        if (tooSaltyForTip((withDerived(f.per100g)['sodium'] ?? 0) * grams / 100, now.avg['sodium'])) continue;
        // Een "cup" zegt een Europeaan weinig: dan gewoon de grammen
        final cup = portion != null && RegExp(r'\bcups?\b', caseSensitive: false).hasMatch(portion.label);
        tip = WeeklyTip(
          nutrientByKey[w.key]!,
          f,
          grams,
          portion == null || cup ? '${grams.round()} g' : '${portion.label} (${grams.round()} g)',
          frac,
        );
        break;
      }
      if (tip != null) break;
    }
    // "Let op suiker": koolhydraten, suiker en bloedsuiker bovenaan het rapport
    SugarWeek? sugar;
    if (sugarFocus) {
      final full = now.full;
      double mean(double Function((NutrientTotals, Map<String, Target>) d) f) => full.fold(0.0, (s, d) => s + f(d)) / full.length;
      final hasFree = full.any((d) => d.$1.values.containsKey('free_sugars'));
      final glucose = [
        for (final b in user.biometricHistory('glucose', from: dayKey(monday)))
          if (b.day.compareTo(sunday) <= 0 && b.value > 0) b.value,
      ];
      final carbGoals = [for (final d in full) ?d.$2['carbs']?.goal];
      final freeMax = [for (final d in full) ?d.$2['free_sugars']?.upper];
      sugar = SugarWeek(
        days: full.length,
        carbs: mean((d) => d.$1['carbs']),
        carbsGoal: carbGoals.isEmpty ? null : carbGoals.reduce((a, b) => a + b) / carbGoals.length,
        carbDaysOver: full.where((d) => d.$1['carbs'] > (d.$2['carbs']?.goal ?? double.infinity) * 1.1).length,
        sugars: mean((d) => d.$1['sugars']),
        freeSugars: hasFree ? mean((d) => d.$1['free_sugars']) : null,
        freeSugarsMax: hasFree && freeMax.isNotEmpty ? freeMax.reduce((a, b) => a + b) / freeMax.length : null,
        freeSugarDaysOver: hasFree ? full.where((d) => d.$1['free_sugars'] > (d.$2['free_sugars']?.upper ?? double.infinity)).length : 0,
        glucose: glucose.isEmpty ? null : glucose.reduce((a, b) => a + b) / glucose.length,
        glucoseCount: glucose.length,
      );
    }
    // Gewicht, beweging en notities van die week
    final weights = [
      for (final b in user.biometricHistory('weight', from: dayKey(monday)))
        if (b.day.compareTo(sunday) <= 0) b.value,
    ];
    var sessions = 0;
    var minutes = 0.0, burned = 0.0;
    final notes = <String, String>{};
    for (var i = 0; i < 7; i++) {
      final d = dayKey(DateTime(monday.year, monday.month, monday.day + i));
      for (final e in user.exerciseFor(d)) {
        sessions++;
        minutes += e.minutes ?? 0;
        burned += e.kcal;
      }
      final note = user.note(d).trim();
      if (note.isNotEmpty) notes[d] = note;
    }
    return WeeklyReport(
      monday: monday,
      score: now.score,
      days: now.days,
      partialDays: now.partial,
      prevScore: prev?.score,
      best: [for (final e in micros.where((e) => !now.overUpper.contains(e.key)).take(3)) (nutrientByKey[e.key]!, e.value)],
      worst: [for (final e in worst) (nutrientByKey[e.key]!, e.value)],
      tip: tip,
      health: now.health,
      prevHealthScore: prev?.health?.score,
      avg: now.avg,
      prevAvg: prev?.avg ?? const {},
      kcalAvg: now.kcal,
      kcalGoal: now.kcalGoal > 0 ? now.kcalGoal : null,
      prevKcalAvg: prev?.kcal,
      weightStart: weights.length >= 2 ? weights.first : null,
      weightEnd: weights.isEmpty ? null : weights.last,
      exercise: WeeklyExercise(sessions: sessions, minutes: minutes, kcal: burned),
      notes: notes,
      goals: now.goals,
      weightTrend: trend,
      plan: _profile.goal,
      sugar: sugar,
    );
  }

  /// Snel loggen: een stuk van een zin omzetten naar een product en een hoeveelheid.
  /// Geeft de beste treffers (de eerste is de keuze) en per treffer gram en portielabel.
  /// Wat je bij Snel loggen zelf koos in plaats van de eerste treffer, per zoekterm. Volgende keer staat dat bovenaan.
  Map<String, String> get _quickPicks => ((user.setting('quickPicks') ?? const {}) as Map).cast<String, String>();

  void rememberQuickPick(String query, String ref) {
    final picks = {..._quickPicks}..remove(query.toLowerCase());
    picks[query.toLowerCase()] = ref;
    // Alleen de laatste 300 keuzes bewaren
    final keep = picks.entries.toList().reversed.take(300).toList().reversed;
    user.setSetting('quickPicks', {for (final e in keep) e.key: e.value});
  }

  /// Gewone woorden die in de databank anders heten.
  static const _quickAliases = {
    'toast': 'bread toasted',
    'mince': 'minced beef',
    'jacket potato': 'potato baked',
    'oats': 'porridge oats',
    'cola zero': 'cola sweetener',
    'coke zero': 'cola sweetener',
    'coca cola zero': 'cola sweetener',
    'cola light': 'cola sweetener',
    'diet coke': 'cola sweetener',
    'pepsi max': 'cola sweetener',
    // Britse chips zijn een zakje chips, geen knäckebröd ("crispbread")
    'crisps': 'potato crisps',
    // Een boterham is een sneetje brood (het meest getypte woord bij het ontbijt)
    'boterham': 'bread',
    'boterhammen': 'bread',
    'boterhammetje': 'bread',
    'sneetje brood': 'bread',
    'sneetjes brood': 'bread',
    // Een merknaam voor gewone cola: de gewone cola uit de databank (merkproducten zoek je via 'Merken')
    'coca cola': 'cola',
    'coca-cola': 'cola',
    'coke': 'cola',
    'pepsi': 'cola',
    'griekse yoghurt': 'greek yogurt',
    'halfvolle melk': 'semi-skimmed milk',
    'magere melk': 'skimmed milk',
    'volle melk': 'whole milk',
    'turkse yoghurt': 'greek yogurt',
  };

  /// Losse woorden die de vertaling (search_terms.dart) niet kent.
  static const _wordAliases = {'griekse': 'greek', 'grieks': 'greek'};

  /// Wat je typte of zei, klaar om te zoeken: aliassen en Nederlandse buigings-e ("gekookte" = "gekookt").
  static String _normalQuery(String query) {
    final q = query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final alias = _quickAliases[q];
    if (alias != null) return alias;
    return [
      for (final w in q.split(' '))
        if (_wordAliases[w] case final a?)
          a
        else if (w.length > 4 &&
            w.endsWith('e') &&
            searchTokens(w).join() == w &&
            searchTokens(w.substring(0, w.length - 1)).join() != w.substring(0, w.length - 1))
          w.substring(0, w.length - 1)
        else
          w,
    ].join(' ');
  }

  /// Kandidaten voor een zoekterm, in de volgorde van de databank: bij een meervoud ("breads", "eieren") eerst het
  /// enkelvoud. Een energiedrank alleen als je die vraagt (P151).
  List<Food> _candidates(String query, {Food? first}) {
    final singular = query.replaceAll(RegExp(r'(es|s|en)$'), '');
    final seen = <String>{};
    return [
      for (final f in [
        ?first,
        if (singular != query && singular.length > 2) ...[...user.searchSaved(singular), ...foods.search(singular, limit: 150)],
        ...user.searchSaved(query),
        ...foods.search(query, limit: 200),
      ])
        if (!unaskedEnergyDrink(f, query) && seen.add(f.ref)) f,
    ];
  }

  List<(Food, double, Portion?)> resolveQuick(QuickItem q) {
    final typed = q.query.toLowerCase().trim();
    var norm = _normalQuery(q.query);
    // Gewone woorden met een vaste bedoeling: een kroket is een aardappelkroket (geen falafel), melk halfvolle melk,
    // thee gezette thee (geen ijsthee), whey eiwitpoeder
    for (final (pattern, alias) in const [
      (r'^(croquettes?|kroket(ten|je|jes)?|aardappelkroket(ten|je|jes)?)$', 'potato croquettes'),
      (r'^(milk|melk)$', 'semi-skimmed milk'),
      (r'^(tea|thee|black tea|zwarte thee)$', 'tea black infusion'),
      (r'^(whey|whey protein|wei-eiwit)$', 'whey protein powder'),
    ]) {
      if (RegExp(pattern).hasMatch(norm)) norm = alias;
    }
    if (norm != q.query.toLowerCase().trim()) q = q.withQuery(norm);
    // Wat iemand zegt, is meestal bereid en heel: "rijst" is gekookte rijst, "eieren" zijn hele eieren
    final picked = _quickPicks[typed] ?? _quickPicks[q.query.toLowerCase()];
    final pickedFood = picked == null ? null : (FoodDb.isDbRef(picked) ? foods.byRef(picked) : user.food(picked));
    // Wat je eerder at, is bijna altijd wat je bedoelt
    final mine = {for (final e in user.recent(limit: 300)) e.foodRef};
    var all = _candidates(q.query, first: pickedFood);
    // Niets gevonden: probeer de woorden aan elkaar ("volkorenbrood") en dan het laatste woord ("brood")
    final words = q.query.split(RegExp(r'\s+'));
    if (all.isEmpty && words.length > 1) all = searchLocal(words.join()).take(25).toList();
    if (all.isEmpty && words.length > 1) all = searchLocal(words.last).take(25).toList();
    // Hetzelfde basisproduct als bovenaan in het zoekvak, zodat Snel loggen en zoeken geen twee eierregels geven (N10)
    final boxTop = all.isEmpty ? null : groupFoods(searchLocal(q.query)).firstOrNull?.main;
    if (boxTop != null && !all.any((f) => f.ref == boxTop.ref)) all = [...all, boxTop];
    // Dezelfde score als het zoekvak (P152), plus je eigen keuzes en wat je eerder at
    double rank(int i, Food f) {
      var s = 20.0 - i * 0.15 + foodQueryScore(f, q.query);
      if (f.ref == picked) s += 200;
      if (f.ref == boxTop?.ref) s += 20;
      if (mine.contains(f.ref)) s += 25;
      return s;
    }

    final hits = [for (final (i, f) in all.indexed) (rank(i, f), f)]..sort((a, b) => b.$1.compareTo(a.$1));
    // Bronnen die afwijken van de andere bronnen van hetzelfde product (gebraden eend met 46,7 g eiwit tegenover
    // 23–27 g elders) komen nooit als eerste, en tellen niet mee voor de mediane energie hieronder
    final off = disagreeingSources(hits.take(80).map((h) => h.$2));
    // P157: staan er bovenaan meerdere bronnen van hetzelfde product (banaan 51-97 kcal, rijst 113-171),
    // dan is er geen "juiste" — kies de mediane energie i.p.v. toevallig een extreme. Een eerder gekozen of
    // eerder gegeten product (+200/+25 in rank) staat buiten deze band en blijft dus vooraan.
    if (hits.length >= 3) {
      String stem(String w) => w.replaceAll(RegExp(r'(es|s)$'), '');
      String headOf(Food f) {
        for (final w in f.name.toLowerCase().split(',').first.split(RegExp(r'\s+'))) {
          if (w.length >= 3) return stem(w);
        }
        return '';
      }

      final topHead = headOf(hits.first.$2);
      final best = hits.first.$1;
      final cluster = [
        for (final h in hits)
          if (best - h.$1 <= 3 && topHead.isNotEmpty && headOf(h.$2) == topHead && (h.$2.per100g['energy'] ?? 0) > 0 && !off.contains(h.$2.ref)) h,
      ];
      if (cluster.length >= 3) {
        final energies = [for (final h in cluster) h.$2.per100g['energy']!]..sort();
        final medE = energies[energies.length ~/ 2];
        final lead = (cluster..sort((a, b) => (a.$2.per100g['energy']! - medE).abs().compareTo((b.$2.per100g['energy']! - medE).abs()))).first.$2;
        hits.sort(
          (a, b) => a.$2.ref == lead.ref
              ? -1
              : b.$2.ref == lead.ref
              ? 1
              : b.$1.compareTo(a.$1),
        );
      }
    }
    // Staat er toch een afwijkende bron vooraan, dan een bron van hetzelfde product die wel overeenkomt — behalve
    // als je die zelf koos of eerder at
    final top = hits.isEmpty ? null : hits.first.$2;
    if (top != null && off.contains(top.ref) && top.ref != picked && !mine.contains(top.ref)) {
      final key = sameProductKey(top);
      final alt = hits.indexWhere((h) => !off.contains(h.$2.ref) && sameProductKey(h.$2) == key);
      if (alt > 0) hits.insert(0, hits.removeAt(alt));
    }
    (Food, double, Portion?) amount(Food f) {
      if (q.grams != null) return (f, q.grams!, null);
      final n = q.count ?? 1;
      final name = f.name.toLowerCase();
      final unit = q.unit;
      // Pizza: een punt ≈ 100 g, een hele ≈ 400 g ("een halve pizza" = 200 g, niet 60 g)
      if (RegExp(r'\bpizzas?\b(?! ?(sauce|dough|base|topping|cheese|seasoning))').hasMatch(name) &&
          (unit == null || unit == 'slice' || unit == 'thin slice' || unit == 'piece')) {
        final whole = unit == null;
        final short = whole ? tr('1 pizza', '1 pizza') : tr('1 slice', '1 punt');
        final g = whole ? 400.0 : 100.0;
        return (f, n * g, EverydayPortion(short, '$short (≈${g.round()} g)', g));
      }
      // Beleg en kaas: een plakje is ≈ 20 g, ook op een boterham zonder hoeveelheid ("2 sneetjes brood met ham")
      final coldCut = RegExp(
        r'\b(ham|salami|chorizo|prosciutto|pastrami|mortadella|turkey|chicken breast|luncheon|cheese|cheddar|gouda|edam|emmental)\b',
      ).hasMatch(name);
      final onBread =
          q.after != null && RegExp(r'\b(bread|toast|brood|boterham|sandwich|roll|broodje|bagel|cracker|beschuit|wrap)').hasMatch(q.after!);
      if (coldCut && (unit == 'slice' || unit == 'thin slice')) return (f, n * 20, null);
      if (coldCut && unit == null && q.count == null && onBread) return (f, (q.afterCount ?? 1) * 20, null);
      // In de koffie of thee: een scheutje melk (30 ml) of een klontje suiker, geen glas
      final inHotDrink = q.after != null && RegExp(r'\b(coffee|tea|koffie|thee|espresso|cappuccino|latte)\b').hasMatch(q.after!);
      if (inHotDrink && unit == null && q.count == null) {
        if (RegExp(r'\b(milk|cream|melk|room)\b').hasMatch(name)) return (f, 30, null);
        if (RegExp(r'\bsugar\b').hasMatch(name)) return (f, 5, null);
      }
      // Een glas wijn is kleiner dan een glas water
      if (unit == 'glass' && q.unitGrams == 200 && RegExp(r'\b(wine|champagne|prosecco|cava|port|sherry)\b').hasMatch(name)) {
        return (f, n * 150, null);
      }
      if (q.unitGrams != null) return (f, n * q.unitGrams!, null);
      // Beleg zonder hoeveelheid ("toast with butter") is een lepel, geen pakje
      if (q.count == null && RegExp(_spreads).hasMatch(q.query.toLowerCase())) return (f, 15, null);
      // Eén stuk: de kleinste portie die met "1 " begint (bv. "1 large" eerder dan een vreemde 101 g)
      final ones = f.portions.where((p) => p.grams >= 15 && p.grams <= 400 && p.label.startsWith('1 ')).toList()
        ..sort((a, b) => a.grams.compareTo(b.grams));
      final portion = ones.firstOrNull ?? f.portions.where((p) => p.grams >= 15 && p.grams <= 400).firstOrNull;
      if (portion != null) return (f, n * portion.grams, portion);
      // Geen portie in de databank: dezelfde gewone portie als op het productscherm (een glas, een mok, een kom)
      final everyday = everydayPortions(f).firstOrNull;
      if (everyday != null) return (f, n * everyday.grams, everyday);
      // Anders een gewoon stukgewicht in plaats van 100 g per stuk
      final typical = _typicalPieceGrams(name);
      return (f, n * (typical ?? 100), null);
    }

    // Dezelfde naam uit dezelfde bron is geen echte keuze (P177)
    final shown = <String>{};
    return [
      for (final h in hits)
        if (shown.add('${h.$2.name.toLowerCase()}|${h.$2.source.name}')) h.$2,
    ].take(6).map(amount).toList();
  }

  /// "Wat moet ik nog eten?": 2 à 3 producten die je grootste tekorten van vandaag samen aanvullen.
  GapPlan? gapPlan() => gapPlanFor(_totals.values, _targets);

  /// Zelfde voor andere totalen, bv. een plan voor morgen.
  GapPlan? gapPlanFor(NutrientMap totals, Map<String, Target> targets) {
    final gaps = [
      for (final k in stripKeys)
        if (targets[k]?.goal != null && (totals[k] ?? 0) < targets[k]!.goal! * 0.85) k,
    ]..sort((a, b) => ((totals[a] ?? 0) / targets[a]!.goal!).compareTo((totals[b] ?? 0) / targets[b]!.goal!));
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
    final kcalLeft = (targets['energy']?.goal ?? 2000) - (totals['energy'] ?? 0);
    return planGaps(totals: totals, targets: targets, kcalLeft: kcalLeft, candidates: candidates, mine: {for (final f in mine) f.ref});
  }

  // ── Planner ──

  /// Geplande maaltijden per dag ("jjjj-mm-dd"), bewaard in de instellingen (en dus gesynchroniseerd).
  Map<String, List<PlannedItem>> get _plans {
    final raw = user.setting('plan') ?? const {};
    return {
      for (final e in raw.entries)
        if (e.value is List) e.key: [for (final x in e.value as List) PlannedItem.fromJson((x as Map).cast<String, Object?>())],
    };
  }

  void _savePlans(Map<String, List<PlannedItem>> plans) {
    // Oude plannen (meer dan een week geleden) opruimen
    final oldest = dayKey(_dateOnly(logicalNow()).subtract(const Duration(days: 7)));
    user.setSetting('plan', {
      for (final e in plans.entries)
        if (e.value.isNotEmpty && e.key.compareTo(oldest) >= 0) e.key: [for (final i in e.value) i.toJson()],
    });
    notifyListeners();
  }

  List<PlannedItem> planFor(String day) => _plans[day] ?? const [];

  /// Dagen met een plan, vanaf vandaag.
  List<String> get plannedDays {
    final today = dayKey(_dateOnly(logicalNow()));
    return [
      for (final e in _plans.entries)
        if (e.value.isNotEmpty && e.key.compareTo(today) >= 0) e.key,
    ]..sort();
  }

  void addToPlan(String day, Meal meal, ItemTemplate item) {
    final plans = _plans;
    plans[day] = [...?plans[day], PlannedItem(meal, item)];
    _savePlans(plans);
  }

  void removeFromPlan(String day, int index) {
    final plans = _plans;
    final list = [...?plans[day]]..removeAt(index);
    plans[day] = list;
    _savePlans(plans);
  }

  /// Het plan van een dag vervangen (ongedaan maken van een verwijdering).
  void setPlan(String day, List<PlannedItem> items) {
    final plans = _plans;
    plans[day] = items;
    _savePlans(plans);
  }

  void clearPlan(String day) {
    final plans = _plans..remove(day);
    _savePlans(plans);
  }

  /// Alles van een plan in het dagboek van die dag zetten; het plan is daarna leeg. Geeft het aantal regels terug.
  int logPlan(String day) {
    final items = planFor(day);
    for (final i in items) {
      user.addTemplate(day, i.meal, i.item);
    }
    final plans = _plans..remove(day);
    _savePlans(plans);
    _targetsVersion++;
    _refresh();
    return items.length;
  }

  /// Totalen van een plan, met de doelen van die dag.
  NutrientTotals planTotals(String day) =>
      NutrientTotals.sumOf([for (final i in planFor(day)) _withSugars(i.item.per100g, i.item.foodRef, i.item.name, i.item.grams)]);

  // ── Boodschappenlijst ──

  List<ShoppingItem> get shopping => [
    for (final x in (user.setting('shopping')?['items'] as List?) ?? const []) ShoppingItem.fromJson((x as Map).cast<String, Object?>()),
  ];

  void saveShopping(List<ShoppingItem> items) {
    user.setSetting('shopping', {
      'items': [for (final i in items) i.toJson()],
    });
    notifyListeners();
  }

  /// Iets op de lijst zetten; staat het er al (zelfde naam, nog niet afgevinkt), dan telt de hoeveelheid erbij.
  void addShopping(String name, {double? grams, String? reason}) {
    final items = shopping;
    final i = items.indexWhere((x) => !x.done && x.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      final old = items[i];
      items[i] = ShoppingItem(name: old.name, grams: grams == null ? old.grams : (old.grams ?? 0) + grams, reason: old.reason ?? reason);
    } else {
      items.add(ShoppingItem(name: name, grams: grams, reason: reason));
    }
    saveShopping(items);
  }

  /// Alles uit de plannen van [days] op de lijst, per product opgeteld. Geeft het aantal producten terug.
  int shoppingFromPlans(Iterable<String> days) {
    final grams = <String, double>{};
    for (final d in days) {
      for (final i in planFor(d)) {
        grams[i.item.name] = (grams[i.item.name] ?? 0) + i.item.grams;
      }
    }
    for (final e in grams.entries) {
      addShopping(e.key, grams: e.value);
    }
    return grams.length;
  }

  /// Stoffen die je de laatste 14 dagen vaak te weinig binnenkreeg (gemiddeld onder 70% van je doel), het
  /// grootste tekort eerst, met voor elk een paar gewone producten die er rijk aan zijn.
  List<(Nutrient, double, List<Food>)> shoppingTips({int limit = 4}) {
    final today = _dateOnly(logicalNow());
    final daily = dailyTotals(today.subtract(const Duration(days: 14)), today.subtract(const Duration(days: 1)));
    if (daily.length < 3) return const [];
    final avg = <String, double>{};
    for (final e in daily.entries) {
      final t = targetsForDate(parseDay(e.key));
      for (final k in stripKeys) {
        final g = t[k]?.goal;
        if (g != null && g > 0) avg[k] = (avg[k] ?? 0) + (e.value.values[k] ?? 0) / g / daily.length;
      }
    }
    final low = avg.entries.where((e) => e.value < 0.7).toList()..sort((a, b) => a.value.compareTo(b.value));
    return [
      for (final e in low.take(limit))
        if (nutrientByKey[e.key] case final n?) (n, e.value, [for (final r in richestFor(e.key, perKcal: true, limit: 3, advice: true)) r.$1]),
    ];
  }

  void _refresh() {
    _novaCache.clear();
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
    _saveSupplements([...list, sup.copyWith(id: id, since: dayKey(_dateOnly(logicalNow())))]);
    _refresh();
  }

  void updateSupplement(Supplement sup) {
    _saveSupplements([for (final x in supplements) x.id == sup.id ? sup : x]);
    _refresh();
  }

  /// Uit je lijst halen; wat je eerder innam, blijft in je dagboek.
  /// Een net verwijderd supplement terugzetten, op zijn oude plaats.
  void restoreSupplement(Supplement sup, int index) {
    final list = [...supplements];
    if (list.any((x) => x.id == sup.id)) return;
    list.insert(index.clamp(0, list.length), sup);
    _saveSupplements(list);
    _refresh();
  }

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

  NutrientTotals totalsFor(Meal meal) => NutrientTotals.sumOf(entriesFor(meal).map(entryValues));

  /// Terug naar de dag van vandaag (bv. via het tabblad Vandaag).
  void goToToday() => setDate(logicalNow());

  void setDate(DateTime d) {
    _date = _dateOnly(d);
    _refresh();
  }

  void shiftDay(int days) => setDate(_date.add(Duration(days: days)));

  void saveProfile(Profile p) {
    _freezePastDays();
    _targetsVersion++;
    _profile = p;
    _hasProfile = true;
    user.setSetting('profile', p.toJson());
    _refresh();
  }

  void saveSettings(TargetSettings s) {
    _freezePastDays();
    _targetsVersion++;
    _settings = s;
    user.setSetting('targets', s.toJson());
    _refresh();
  }

  /// Eigen richtwaarde instellen (null = terug naar de standaard). Een eigen doel dat je zo wist, onthoudt de app
  /// (zie [lastOverride]), zodat "Eigen doel" het terugzet.
  void setOverride(String key, Target? t) {
    final o = Map.of(_settings.overrides);
    if (t == null) {
      if (o.remove(key) case final old?) {
        user.setSetting('lastOverrides', {
          ...?user.setting('lastOverrides'),
          key: {'goal': old.goal, 'upper': old.upper},
        });
      }
    } else {
      o[key] = t;
    }
    saveSettings(_settings.copyWith(overrides: o));
  }

  /// Het laatste eigen doel voor [key] dat je weer op de standaard zette (null = geen).
  Target? lastOverride(String key) {
    final raw = user.setting('lastOverrides')?[key];
    if (raw is! Map) return null;
    final t = Target(goal: (raw['goal'] as num?)?.toDouble(), upper: (raw['upper'] as num?)?.toDouble());
    return t.goal == null && t.upper == null ? null : t;
  }

  // ── Dagboek ──

  /// Voegt een product toe aan de dag. Staat hetzelfde product met dezelfde portie al in die maaltijd (zonder
  /// eigen tijd), dan komt de hoeveelheid bij die regel in plaats van een tweede regel. Geef het resultaat aan
  /// [undoAdds] om het ongedaan te maken.
  AddedEntry addFood(Food food, {required Meal meal, required double grams, required double quantity, String? portionLabel, String? time}) {
    // Opgezochte en eigen producten lokaal bewaren, zodat ze bij "recent" en offline beschikbaar blijven
    if (!FoodDb.isDbRef(food.ref) && food.source != FoodSource.recipe) user.saveFood(food);
    final AddedEntry added;
    final into = user.mergeTarget(day: day, meal: meal, food: food, portionLabel: portionLabel, time: time);
    if (into != null) {
      user.updateEntryAmount(into.id, into.grams + grams, into.quantity + quantity);
      added = AddedEntry(into.id, prevGrams: into.grams, prevQuantity: into.quantity);
    } else {
      added = AddedEntry(user.addEntry(day: day, meal: meal, food: food, grams: grams, quantity: quantity, portionLabel: portionLabel, time: time));
    }
    _rememberAmount(food.ref, grams, quantity, portionLabel);
    _refresh();
    return added;
  }

  // Wat je de laatste keer per product toevoegde (alleen op dit toestel). Een samengevoegde regel bevat het totaal
  // (150 g + 150 g = 300 g); "dezelfde hoeveelheid" opnieuw is de laatste toevoeging, niet dat totaal (N02).
  Map<String, Object?> get _lastAmounts => ((user.setting('_lastAmounts') ?? const {}) as Map).cast<String, Object?>();

  void _rememberAmount(String ref, double grams, double quantity, String? portion) {
    final m = {..._lastAmounts}..remove(ref);
    m[ref] = [grams, quantity, portion];
    // Hooguit 400 producten; de oudste vallen weg
    while (m.length > 400) {
      m.remove(m.keys.first);
    }
    user.setSetting('_lastAmounts', m);
  }

  /// [e] met de hoeveelheid van de laatste keer dat je dit product toevoegde (als die gekend is).
  DiaryEntry asLastAdded(DiaryEntry e) {
    final a = _lastAmounts[e.foodRef];
    if (a is! List || a.length < 3) return e;
    return DiaryEntry(
      id: e.id,
      day: e.day,
      meal: e.meal,
      foodRef: e.foodRef,
      name: e.name,
      grams: (a[0] as num).toDouble(),
      quantity: (a[1] as num).toDouble(),
      per100g: e.per100g,
      brand: e.brand,
      portionLabel: a[2] as String?,
      time: e.time,
    );
  }

  /// Toevoegingen ongedaan maken: nieuwe regels weg, samengevoegde regels terug naar hun vorige hoeveelheid.
  /// Achterstevoren, zodat twee toevoegingen aan dezelfde regel netjes teruggedraaid worden.
  void undoAdds(Iterable<AddedEntry> added) {
    for (final a in added.toList().reversed) {
      if (a.merged) {
        user.updateEntryAmount(a.id, a.prevGrams!, a.prevQuantity!);
      } else {
        user.deleteEntry(a.id);
      }
    }
    _refresh();
  }

  /// Net toegevoegde regels weer weghalen (ongedaan maken na Snel loggen).
  void removeEntriesById(Set<String> ids) {
    deleteEntries([
      for (final e in _entries)
        if (ids.contains(e.id)) e,
    ]);
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

  /// Je hele dag van gisteren kopiëren (alle maaltijden, zonder supplementen). Hetzelfde product dat er al staat,
  /// wordt samengevoegd tot één regel. Geef het resultaat aan [undoAdds] om het ongedaan te maken (N57).
  List<AddedEntry> copyDayFromYesterday() {
    final from = dayKey(_date.subtract(const Duration(days: 1)));
    final added = [
      for (final m in Meal.values)
        for (final c in user.copyMealMerged(fromDay: from, meal: m, toDay: day))
          AddedEntry(c.id, prevGrams: c.prevGrams, prevQuantity: c.prevQuantity),
    ];
    _refresh();
    return added;
  }

  /// Wat je meestal eet bij [meal]: producten die je de afgelopen 30 dagen op minstens 3 dagen bij die maaltijd
  /// logde, met de hoeveelheid van de laatste keer. Zonder wat vandaag al in die maaltijd staat.
  List<DiaryEntry> usualFor(Meal meal, {int limit = 3}) {
    final today = _dateOnly(logicalNow());
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
    return [for (final e in ranked.take(limit)) asLastAdded(last[e.key]!)];
  }

  /// Een eerder gelogde regel opnieuw toevoegen (zelfde hoeveelheid) aan [meal] op de gekozen dag.
  AddedEntry addAgain(DiaryEntry e, Meal meal) {
    final last = asLastAdded(e);
    return addFood(foodFor(e), meal: meal, grams: last.grams, quantity: last.quantity, portionLabel: last.portionLabel);
  }

  /// [meal] van gisteren kopiëren, met samenvoegen zoals [copyDayFromYesterday]. Geef het resultaat aan [undoAdds].
  List<AddedEntry> copyMealFromYesterday(Meal meal) {
    final added = [
      for (final c in user.copyMealMerged(fromDay: dayKey(_date.subtract(const Duration(days: 1))), meal: meal, toDay: day))
        AddedEntry(c.id, prevGrams: c.prevGrams, prevQuantity: c.prevQuantity),
    ];
    _refresh();
    return added;
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

  // ── Meerdere regels tegelijk (selectie in het dagboek) ──

  /// Regels naar een andere maaltijd verplaatsen (zelfde dag).
  void moveEntries(Iterable<DiaryEntry> entries, Meal meal) {
    for (final e in entries) {
      user.updateEntry(e.id, meal: meal, grams: e.grams, quantity: e.quantity, portionLabel: e.portionLabel, time: e.time);
    }
    _refresh();
  }

  /// Regels kopiëren naar een dag, bij dezelfde maaltijd of bij [meal]. Geeft het aantal terug.
  int copyEntriesTo(Iterable<DiaryEntry> entries, DateTime day, {Meal? meal}) {
    var n = 0;
    for (final e in entries) {
      user.addTemplate(dayKey(day), meal ?? e.meal, templateOf(e));
      n++;
    }
    _refresh();
    return n;
  }

  void deleteEntries(Iterable<DiaryEntry> entries) {
    for (final e in entries) {
      user.deleteEntry(e.id);
    }
    _refresh();
  }

  void restoreEntries(Iterable<DiaryEntry> entries) {
    for (final e in entries) {
      user.restoreEntry(e.id);
    }
    _refresh();
  }

  void saveMealFromEntries(String name, Iterable<DiaryEntry> entries) {
    user.saveMeal(name, [for (final e in entries) templateOf(e)], meal: entries.map((e) => e.meal).toSet().singleOrNull);
    notifyListeners();
  }

  /// Totalen van een selectie regels.
  NutrientTotals totalsOf(Iterable<DiaryEntry> entries) => NutrientTotals.sumOf(entries.map(entryValues));

  // ── Uitgelichte voedingsstoffen (bovenaan het dagboek, zelf te kiezen) ──

  static const defaultHighlighted = ['vit_d', 'b12', 'iron', 'magnesium', 'calcium', 'zinc', 'potassium', 'epa_dha'];

  List<String> get highlighted {
    final saved = (user.setting('ui')?['highlighted'] as List?)?.cast<String>();
    return [
      for (final k in saved ?? defaultHighlighted)
        if (nutrientByKey.containsKey(k)) k,
    ];
  }

  void setHighlighted(List<String> keys) {
    user.setSetting('ui', {...?user.setting('ui'), 'highlighted': keys.take(8).toList()});
    notifyListeners();
  }

  /// Bovenaan het dagboek: welke pagina van de samenvatting je laatst bekeek en of macro's als "nog te gaan" staan.
  int get summaryPage => (user.setting('ui')?['summaryTab'] as num?)?.toInt() ?? 0;
  bool get macrosRemaining => user.setting('ui')?['macrosRemaining'] == true;

  void setSummaryPage(int i) {
    user.setSetting('ui', {...?user.setting('ui'), 'summaryTab': i});
    notifyListeners();
  }

  void setMacrosRemaining(bool v) {
    user.setSetting('ui', {...?user.setting('ui'), 'macrosRemaining': v});
    notifyListeners();
  }

  void saveMealFromDiary(String name, Meal meal) {
    user.saveMeal(name, [for (final e in entriesFor(meal)) templateOf(e)], meal: meal);
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

  /// Activiteiten die je onlangs deed, om ze met één tik te herhalen.
  List<Exercise> get recentExercises => user.recentExercises();

  void updateExercise(Exercise e, {required String name, required double kcal, double? minutes}) {
    user.updateExercise(e.id, name: name, kcal: kcal, minutes: minutes);
    _refresh();
  }

  void deleteExercise(Exercise e) {
    user.deleteExercise(e.id);
    _refresh();
  }

  void restoreExercise(Exercise e) {
    user.undelete('exercise', e.id);
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
    if (type == 'weight' && _syncProfileWeight()) return;
    _refresh();
  }

  /// Je doelen rekenen altijd met je laatste gewicht: na een nieuwe of gewiste meting neemt het profiel dat over.
  /// Zo draait het wissen van een foute meting (645 in plaats van 64,5 kg) ook de doelen terug.
  /// Geeft true als het profiel (en dus alles) opnieuw berekend werd.
  bool _syncProfileWeight() {
    final w = currentWeight;
    if ((w - _profile.weightKg).abs() < 0.05) return false;
    saveProfile(_profile.copyWith(weightKg: w));
    return true;
  }

  /// Na het overnemen uit Health Connect: alles opnieuw tonen; een nieuw gewicht van vandaag geldt meteen voor je doelen.
  void healthImported({String? latestWeightDay}) {
    if (latestWeightDay != null && latestWeightDay == dayKey(logicalNow())) {
      saveProfile(_profile.copyWith(weightKg: currentWeight));
      return;
    }
    _targetsVersion++;
    _refresh();
  }

  void deleteBiometric(Biometric b) {
    user.deleteBiometric(b.id);
    if (b.type == 'weight' && _syncProfileWeight()) return;
    _refresh();
  }

  void restoreBiometric(Biometric b) {
    user.undelete('biometrics', b.id);
    if (b.type == 'weight' && _syncProfileWeight()) return;
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
    return {for (final e in byDay.entries) e.key: NutrientTotals.sumOf(e.value.map(entryValues))};
  }

  // ── Level en avatar ──

  LevelInfo? _level;

  /// Je level en XP, uit wat je in de app logde (zie levels.dart voor de regels).
  LevelInfo get level => _level ??= _computeLevel();

  LevelInfo _computeLevel() {
    final today = dayKey(logicalNow());
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
      final v = NutrientTotals.sumOf(entries.map(entryValues)).values;
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
    final now = logicalNow();
    final key = dayKey(now);
    final burned = user.exerciseKcalBetween(key, key)[key] ?? 0;
    final goal = targetsForDate(now, burned: burned)['energy']?.goal ?? 0;
    final eaten = dailyTotals(now, now)[key]?.values['energy'] ?? 0;
    return (left: (goal - eaten).round(), goal: goal.round(), loggedToday: user.loggedDays().contains(key));
  }

  ({int current, int longest}) get streak => loggingStreak(user.loggedDays(), logicalNow());

  /// Gemiddelde volledigheidsscore van de week die op [monday] begint, over de dagen waarop iets gelogd is
  /// (tot en met vandaag). Null als er die week nog niets gelogd is.
  ({int score, int days})? weekScore(DateTime monday) {
    final today = logicalNow();
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

  final _novaCache = <String, Nova?>{};

  /// NOVA-groep van een voedingsmiddel; een recept volgt uit zijn ingrediënten.
  Nova? novaFor(String ref, {Food? food}) {
    if (_novaCache.containsKey(ref)) return _novaCache[ref];
    _novaCache[ref] = null; // tegen recepten die zichzelf bevatten
    Nova? n;
    final recipe = ref.startsWith('recipe:') ? user.recipe(ref) : null;
    if (recipe != null) {
      n = novaOfRecipe([for (final i in recipe.ingredients) (novaFor(i.foodRef, food: i.toFood()), i.kcal)]);
    } else {
      final f = FoodDb.isDbRef(ref) ? foods.byRef(ref) : user.food(ref);
      n = novaOf(f ?? food ?? Food(ref: ref, name: '', source: FoodSource.custom, per100g: const {}));
    }
    return _novaCache[ref] = n;
  }

  /// Hoeveel van je energie uit onbewerkt tot ultrabewerkt eten komt, voor een reeks dagboekregels.
  ProcessingShare processingOf(Iterable<DiaryEntry> entries) => ProcessingShare.of([
    for (final e in entries)
      if (!e.foodRef.startsWith('supp:'))
        (
          novaFor(
            e.foodRef,
            food: Food(ref: e.foodRef, name: e.name, source: FoodSource.custom, per100g: e.per100g),
          ),
          e.kcal,
        ),
  ]);

  /// Bewerkingsgraad over een periode (bv. de grafiekperiode in Trends).
  ProcessingShare processingBetween(DateTime from, DateTime to) => processingOf(user.entriesBetween(dayKey(from), dayKey(to)));

  List<Food> recentFoods() => [for (final e in user.recent()) foodFor(e)];

  /// Lokaal zoeken: eigen producten, recepten en de ingebouwde database, gerangschikt zoals Snel loggen (P152):
  /// het gewone, bereide product boven rauwe rijst, kipgehakt of melkpoeder. Favorieten eerst, dan wat je al eens
  /// at, dan de rest. Met [personal] uit alleen de gewone volgorde, die niet verschuift na het loggen (N82).
  List<Food> searchLocal(String q, {bool personal = true}) {
    final norm = _normalQuery(q);
    final seen = <String>{};
    // Met een alias ("oats") ook wat je letterlijk typte, erachter
    final all = [
      for (final f in [..._candidates(norm), if (norm != q.toLowerCase().trim()) ..._candidates(q.toLowerCase().trim())])
        if (seen.add(f.ref)) f,
    ];
    // Niets gevonden: de woorden aan elkaar ("volkoren brood") of alleen het laatste woord
    final words = norm.split(' ');
    if (all.isEmpty && words.length > 1) all.addAll(_candidates(words.join()));
    if (all.isEmpty && words.length > 1) all.addAll(_candidates(words.last));
    double score(int i, Food f) =>
        20.0 -
        i * 0.15 +
        foodQueryScore(f, norm) +
        // Eigen producten en recepten zijn geen "gewoon eten" voor de score, maar wel precies wat je zoekt
        (FoodDb.isDbRef(f.ref) ? 0 : (f.source == FoodSource.recipe ? 40 : 10));
    final ranked = [for (final (i, f) in all.indexed) (score(i, f), f)]..sort((a, b) => b.$1.compareTo(a.$1));
    final top = [for (final (_, f) in ranked.take(80)) f];
    if (!personal) return top;
    final fav = favoriteRefs.toSet();
    final mine = {for (final e in user.recent(limit: 300)) e.foodRef};
    int group(Food f) => fav.contains(f.ref) ? 0 : (mine.contains(f.ref) ? 1 : 2);
    return [
      for (final g in [0, 1, 2]) ...top.where((f) => group(f) == g),
    ];
  }

  // ── Favorieten (gesynchroniseerd) ──

  /// Producten die je koos: favorieten en wat je de laatste tijd at (de voorrang in [searchLocal]).
  Set<String> personalRefs() => {...favoriteRefs, for (final e in user.recent(limit: 300)) e.foodRef};

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

  // ── Suiker (P41, P183) ──

  /// Label per voedingsmiddel, voor de vrije suikers: uit de ingebouwde databank, of bij een merkproduct dat van
  /// zijn basisproduct. Eigen producten en recepten hebben er geen (dan beslist de naam).
  final _labelCache = <String, FoodLabel?>{};

  FoodLabel? _labelFor(String ref) => _labelCache.putIfAbsent(ref, () {
    if (FoodDb.isDbRef(ref)) return foods.byRef(ref)?.label;
    if (!ref.startsWith('off:')) return null;
    final proxy = user.food(ref)?.proxyRef;
    return proxy != null && FoodDb.isDbRef(proxy) ? foods.byRef(proxy)?.label : null;
  });

  /// Per 100 g met de vrije suikers erbij. Bij een recept komen ze uit de ingrediënten (een appel in een cake telt
  /// niet mee, de suiker en de honing wel); anders uit het label, of uit de naam. Een zelf ingevulde waarde bij een
  /// eigen product gaat altijd voor.
  NutrientMap _freeSugars(NutrientMap per100g, String ref, String name, [int depth = 0]) {
    if (!per100g.containsKey('free_sugars') && ref.startsWith('recipe:')) {
      final sugars = per100g['sugars'];
      if (sugars != null && sugars <= 0) return {...per100g, 'free_sugars': 0};
      final share = sugars == null ? null : _recipeShare(ref, per100g, depth);
      if (share != null) return {...per100g, 'free_sugars': sugars! * share};
    }
    return withFreeSugars(per100g, label: _labelFor(ref), name: name);
  }

  /// Welk deel (0–1) van de suikers in een recept vrij is, uit de ingrediënten met elk hun eigen label. Een deel en
  /// geen gram per 100 g: zo klopt het ook met een gewicht na bereiding en bij een oudere momentopname in het dagboek.
  /// Bewaard per recept en suikergehalte; een gewijzigd recept geeft (bijna altijd) andere waarden en dus een nieuwe sleutel.
  final _recipeShareCache = <String, double?>{};

  double? _recipeShare(String ref, NutrientMap per100g, int depth) {
    if (depth > 3) return null; // recept in recept in recept: genoeg
    return _recipeShareCache.putIfAbsent('$ref|${per100g['sugars']}|${per100g['energy']}', () {
      final recipe = user.recipe(ref);
      if (recipe == null) return null;
      var sugars = 0.0, free = 0.0;
      for (final i in recipe.ingredients) {
        final s = (i.per100g['sugars'] ?? 0) * i.grams / 100;
        if (s <= 0) continue;
        sugars += s;
        // Zonder schatting (kan niet bij suikers > 0) telt het ingrediënt volledig mee
        free += (_freeSugars(i.per100g, i.foodRef, i.name, depth + 1)['free_sugars'] ?? i.per100g['sugars']!) * i.grams / 100;
      }
      return sugars <= 0 ? null : (free / sugars).clamp(0.0, 1.0);
    });
  }

  NutrientMap _withSugars(NutrientMap per100g, String ref, String name, double grams) =>
      withDerived(scale(_freeSugars(per100g, ref, name), grams));

  /// Voedingswaarden per 100 g van een product zoals ze in de totalen tellen: met afgeleide waarden en vrije suikers.
  NutrientMap per100gWithSugars(Food f) => withDerived(_freeSugars(f.per100g, f.ref, f.name));

  /// Voedingswaarden van een dagboekregel zoals ze in de totalen tellen: met afgeleide waarden en vrije suikers.
  NutrientMap entryValues(DiaryEntry e) => _withSugars(e.per100g, e.foodRef, e.name, e.grams);

  /// "Let op suiker": koolhydraten en (vrije) suikers vooraan bij Vandaag, en suiker per dag in de week.
  bool get sugarFocus => user.setting('ui')?['sugarFocus'] == true;

  void setSugarFocus(bool v) {
    user.setSetting('ui', {...?user.setting('ui'), 'sugarFocus': v});
    notifyListeners();
  }
}

/// Gewoon gewicht van één stuk, als de databank geen portie heeft (gedeeld met de porties bij een product).
double? _typicalPieceGrams(String name) => typicalPieceGrams(name);

/// Beleg en sauzen: zonder hoeveelheid genoemd is dat een lepel.
const _spreads =
    r'\b(mayo|mayonnaise|ketchup|mustard|butter|margarine|jam|marmalade|honey|syrup|dressing|spread|sugar|oil|cream cheese|'
    r'peanut butter|nutella|pesto|hummus|houmous|gravy|brown sauce|bbq sauce|salsa)\b';
