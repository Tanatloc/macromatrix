/// Weekmenu: stelt voor een paar dagen maaltijden voor die je energie- en eiwitdoel halen en je gewone tekorten
/// aanvullen, vertrekkend van wat je zelf eet.
///
/// Werkwijze per dag:
/// 1. Per maaltijd één "kern": een ontbijt dat je vaak eet, een bewaarde maaltijd, een recept of (zonder
///    geschiedenis) een eenvoudige standaardmaaltijd. Gewoonten wegen het zwaarst; wat deze week al vaak kwam, minder.
/// 2. Gulzig aanvullen: telkens het product (een eigen gewoonte, een gewoon bijgerecht of een adviesproduct) dat de
///    dagscore het meest verbetert, tot niets nog helpt.
/// 3. Kleine verbetering: porties groter of kleiner maken, iets weglaten of omwisselen zolang de score stijgt.
///
/// De dagscore weegt energie (zwaar), eiwit, koolhydraten, vet en vezels, de vitaminen en mineralen (stoffen die je
/// vaak te weinig hebt tellen dubbel), bovengrenzen, suiker (zwaarder met "Let op suiker"), dubbels en de verdeling
/// over de maaltijden. Alles is deterministisch voor dezelfde [seed].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/food.dart';
import '../data/user_db.dart' show Meal;
import 'insights.dart' show stripKeys;
import 'targets.dart';
import 'values.dart' show NutrientMap;

enum MenuSource { habit, saved, recipe, staple, advice }

/// Rol op het bord: één zetmeelproduct en één eiwitbron per maaltijd is genoeg (geen rijst én aardappelen).
enum MenuRole { starch, protein, veg, fruit, dairy, other }

final _starchName = RegExp(r'\b(rice|pasta|spaghetti|noodles?|potato(es)?|bread|oats|porridge|couscous|quinoa)\b', caseSensitive: false);

MenuRole menuRole(Food f) {
  if (f.source == FoodSource.recipe) return MenuRole.other;
  return switch (f.label?.group) {
    'rice' || 'pasta' || 'potato/tuber' || 'bread' || 'cereal' || 'breakfast cereal' => MenuRole.starch,
    'meat' || 'poultry' || 'fish' || 'shellfish' || 'legume' || 'soy product' || 'meat substitute' || 'egg' => MenuRole.protein,
    'vegetable' || 'mushroom' => MenuRole.veg,
    'fruit' => MenuRole.fruit,
    'dairy' => MenuRole.dairy,
    _ => _starchName.hasMatch(f.name) ? MenuRole.starch : MenuRole.other,
  };
}

/// Een product met zijn voedingswaarden per 100 g zoals ze in de totalen tellen (met afgeleide waarden en vrije
/// suikers).
class MenuFood {
  MenuFood(this.food, NutrientMap v) : v = Map.unmodifiable(v), _vec = _toVec(v), role = menuRole(food);
  final Food food;
  final MenuRole role;
  final NutrientMap v;
  final Float64List _vec;

  /// Wat als "hetzelfde" telt voor dubbels: rauwe en gekookte broccoli zijn allebei broccoli.
  String get key => food.label?.food ?? food.name.toLowerCase();
  double get kcal100 => v['energy'] ?? 0;
}

class MenuItem {
  const MenuItem({
    required this.food,
    required this.grams,
    required this.meal,
    required this.source,
    this.portion,
    this.block,
    this.blockId,
    this.reasons = const [],
    double? base,
  }) : base = base ?? grams;
  final MenuFood food;
  final double grams;

  /// De gewone hoeveelheid waarmee het voorgesteld werd; schalen blijft daar dichtbij.
  final double base;
  final Meal meal;
  final MenuSource source;

  /// Portie waarin de hoeveelheid getoond wordt, of null voor gram.
  final Portion? portion;

  /// Naam van de maaltijd waar het bij hoort (bewaarde maaltijd, recept, je gewone ontbijt), of null.
  final String? block;

  /// Id van de [MenuBlock] waaruit het als kern kwam (voor afwisseling over de week).
  final String? blockId;

  /// Stoffen die het vooral aanvult (bij adviesproducten).
  final List<String> reasons;

  double get kcal => food.kcal100 * grams / 100;
  double get quantity => portion == null || portion!.grams <= 0 ? grams : grams / portion!.grams;
  double amount(String key) => (food.v[key] ?? 0) * grams / 100;

  MenuItem copyWith({double? grams, Meal? meal, List<String>? reasons, String? blockId}) => MenuItem(
    food: food,
    grams: grams ?? this.grams,
    meal: meal ?? this.meal,
    source: source,
    portion: portion,
    block: block,
    blockId: blockId ?? this.blockId,
    reasons: reasons ?? this.reasons,
    base: base,
  );
}

/// Een hele maaltijd om als kern te kiezen.
class MenuBlock {
  const MenuBlock({required this.id, required this.name, required this.meal, required this.items, required this.weight, required this.source});
  final String id;
  final String name;
  final Meal meal;
  final List<MenuItem> items;

  /// Hoe graag: hoe vaak je het eet (gewoonten), of een vaste waarde voor bewaarde maaltijden, recepten en
  /// standaardmaaltijden.
  final double weight;
  final MenuSource source;
  double get kcal => items.fold(0, (a, i) => a + i.kcal);
}

/// Alles waaruit het menu gekozen wordt.
class WeekMenuInput {
  const WeekMenuInput({
    required this.blocks,
    required this.extras,
    required this.advice,
    this.focus = const {},
    this.shares = defaultMealShares,
    this.sugarFocus = false,
  });

  /// Hele maaltijden (kern).
  final List<MenuBlock> blocks;

  /// Losse producten om bij een maaltijd te zetten, met hun maaltijd en gewone hoeveelheid.
  final List<MenuItem> extras;

  /// Gewone adviesproducten die tekorten aanvullen; maaltijd en hoeveelheid worden hier gekozen.
  final List<MenuFood> advice;

  /// Stoffen die je vaak te weinig hebt: sleutel → gewicht 0..1 (1 = flink tekort).
  final Map<String, double> focus;

  /// Deel van de dagenergie per maaltijd (jouw gewone verdeling).
  final Map<Meal, double> shares;
  final bool sugarFocus;
}

const defaultMealShares = {Meal.breakfast: 0.25, Meal.lunch: 0.32, Meal.dinner: 0.33, Meal.snacks: 0.10};

class MenuDay {
  MenuDay(this.date, this.targets, List<MenuItem> items) : items = List.unmodifiable(items), totals = _sum(items);
  final DateTime date;
  final Map<String, Target> targets;
  final List<MenuItem> items;
  final NutrientMap totals;

  double get kcal => totals['energy'] ?? 0;
  double get protein => totals['protein'] ?? 0;

  /// Deel van het doel (1 = gehaald), of null zonder doel.
  double? share(String key) {
    final g = targets[key]?.goal;
    return g == null || g <= 0 ? null : (totals[key] ?? 0) / g;
  }

  static NutrientMap _sum(List<MenuItem> items) {
    final t = <String, double>{};
    for (final i in items) {
      for (final e in i.food.v.entries) {
        t[e.key] = (t[e.key] ?? 0) + e.value * i.grams / 100;
      }
    }
    return t;
  }
}

/// Hoe dicht een dag bij de doelen komt, eerlijk gezegd.
class MenuCheck {
  const MenuCheck({required this.reached, required this.low, required this.hard, required this.energyOk, required this.proteinOk});

  /// Stoffen die (bijna) gehaald worden, de stoffen waar je vaak te weinig van hebt eerst.
  final List<String> reached;

  /// Stoffen onder 70% van het doel, het grootste tekort eerst.
  final List<String> low;

  /// Deel van [low] dat met een gewone portie van gewoon eten niet te halen is.
  final List<String> hard;

  /// Energie binnen 10% van het doel; eiwit minstens 85%.
  final bool energyOk, proteinOk;
}

class WeekMenu {
  const WeekMenu(this.days, this.meals, this.seed);
  final List<MenuDay> days;
  final Set<Meal> meals;
  final int seed;

  WeekMenu withDay(int i, MenuDay d) => WeekMenu([...days]..[i] = d, meals, seed);
}

// ── Vaste rij voedingsstoffen, zodat de dagscore snel rekent ──

const _macroKeys = ['energy', 'protein', 'carbs', 'fat', 'fiber', 'sugars', 'free_sugars', 'sfa', 'sodium'];
final List<String> _keys = [
  ..._macroKeys,
  for (final k in stripKeys)
    if (!_macroKeys.contains(k)) k,
];
final Map<String, int> _index = {for (final (i, k) in _keys.indexed) k: i};
const _iE = 0, _iP = 1, _iC = 2, _iF = 3, _iFib = 4, _iSug = 5, _iFree = 6;

Float64List _toVec(NutrientMap v) {
  final out = Float64List(_keys.length);
  for (final (i, k) in _keys.indexed) {
    out[i] = v[k] ?? 0;
  }
  return out;
}

/// Hoeveelheden om te proberen voor een los product: een gewone portie, of 100 g (30 g bij iets heel energierijks).
List<(double, Portion?)> menuAmounts(Food f) {
  final kcal = f.per100g['energy'] ?? 0;
  final portion = f.portions
      .where((p) => p.grams >= 25 && p.grams <= 250 && !RegExp(r'\b(cup|cups|tbsp|tsp|oz|fl|quart|pint)\b', caseSensitive: false).hasMatch(p.label))
      .firstOrNull;
  if (kcal > 350) {
    // Noten, kaas, brood: een handje, een paar plakjes
    return [if (portion != null && portion.grams <= 60) (portion.grams, portion), (30, null)];
  }
  return [if (portion != null) (portion.grams, portion), (100, null), if (kcal < 120) (150, null)];
}

/// Maaltijden waar een product logisch bij hoort, de beste eerst.
List<Meal> _mealsFor(Food f) {
  final g = f.label?.group ?? '';
  final n = f.name.toLowerCase();
  if (g == 'fruit' || g == 'nut/seed' || RegExp(r'\b(nuts?|almonds?|walnuts?|fruit)\b').hasMatch(n)) {
    return const [Meal.snacks, Meal.breakfast, Meal.lunch];
  }
  if (g == 'dairy' || g == 'egg' || g == 'bread' || g == 'breakfast cereal' || RegExp(r'\b(yog(h)?urt|milk|egg|bread|oats)\b').hasMatch(n)) {
    return const [Meal.breakfast, Meal.lunch, Meal.snacks];
  }
  return const [Meal.dinner, Meal.lunch, Meal.breakfast, Meal.snacks];
}

class WeekMenuPlanner {
  WeekMenuPlanner(this.input) {
    // Stoffen met een doel of grens, met hun gewicht
    for (final k in stripKeys) {
      _focusW[_index[k]!] = 1 + 2 * (input.focus[k] ?? 0).clamp(0, 1);
    }
  }
  final WeekMenuInput input;
  final _focusW = Float64List(_keys.length);

  /// Voorstel voor [days] (datum en doelen van die dag) met de maaltijden [meals].
  WeekMenu propose({required List<(DateTime, Map<String, Target>)> days, required Set<Meal> meals, int seed = 0}) {
    final rnd = math.Random(seed);
    final weekUse = <String, int>{};
    final out = <MenuDay>[];
    var lastDay = <String>{};
    for (final (date, targets) in days) {
      final items = _planDay(targets, meals, rnd, weekUse, lastDay);
      lastDay = {};
      for (final i in items) {
        weekUse[i.food.key] = (weekUse[i.food.key] ?? 0) + 1;
        lastDay.add(i.food.key);
        if (i.blockId != null && lastDay.add('block:${i.blockId}')) weekUse['block:${i.blockId}'] = (weekUse['block:${i.blockId}'] ?? 0) + 1;
      }
      out.add(MenuDay(date, targets, items));
    }
    return WeekMenu(out, meals, seed);
  }

  /// Een regel weglaten.
  MenuDay remove(MenuDay d, int index) => MenuDay(d.date, d.targets, [...d.items]..removeAt(index));

  /// Een regel vervangen.
  MenuDay replace(MenuDay d, int index, MenuItem item) => MenuDay(d.date, d.targets, [...d.items]..[index] = item);

  /// Andere producten voor regel [index], de beste eerst: zelfde maaltijd, niet al op die dag.
  List<MenuItem> alternatives(MenuDay d, int index, {Set<Meal>? meals, int limit = 6}) {
    final planned = meals ?? {for (final i in d.items) i.meal};
    final w = _Work(d.targets, planned, d.items);
    final old = d.items[index];
    w.removeAt(index);
    final scored = <(double, MenuItem)>[];
    final seen = <String>{old.food.key};
    // Ook producten uit je gewone maaltijden, en zelf kiezen mag meer dan drie adviesproducten geven
    final pool = [
      ..._candidates(planned),
      for (final b in input.blocks)
        if (b.meal == old.meal) ...b.items,
    ];
    for (final c in pool) {
      if (c.meal != old.meal || !w.fits(c, cap: false) || seen.contains(c.food.key)) continue;
      w.add(c);
      final s = _score(w) + _bonus(c);
      w.removeLast();
      scored.add((s, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final out = <MenuItem>[];
    for (final (_, c) in scored) {
      if (seen.add(c.food.key)) out.add(_withReasons(c, d.targets));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Hoe dicht de dag bij de doelen komt.
  MenuCheck check(MenuDay d) {
    final t = d.targets;
    final reached = <String>[], low = <(String, double)>[], hard = <String>[];
    for (final k in stripKeys) {
      final s = d.share(k);
      if (s == null) continue;
      if (s >= 0.9) reached.add(k);
      if (s < 0.7) low.add((k, s));
    }
    reached.sort((a, b) => (input.focus[b] ?? 0).compareTo(input.focus[a] ?? 0));
    low.sort((a, b) => a.$2.compareTo(b.$2));
    // Niet te halen met gewoon eten: geen enkel product haalt met een gewone portie (hoogstens 30% van je energie,
    // onder de bovengrenzen) 60% van wat er nog ontbreekt.
    final goalKcal = t['energy']?.goal ?? 2000;
    final pool = [
      for (final b in input.blocks) ...b.items.map((i) => (i.food, i.grams)),
      for (final e in input.extras) (e.food, e.grams),
      for (final a in input.advice)
        for (final (g, _) in menuAmounts(a.food)) (a, g),
    ];
    for (final (k, s) in low) {
      final goal = t[k]!.goal!;
      final missing = goal * (1 - s);
      final upper = t[k]?.upper;
      final can = pool.any((p) {
        final (f, g0) = p;
        if (f.kcal100 <= 0) return false;
        final g = math.min(g0 * 1.5, math.min(250.0, goalKcal * 0.3 / f.kcal100 * 100));
        final add = (f.v[k] ?? 0) * g / 100;
        return add >= missing * 0.6 && (upper == null || (d.totals[k] ?? 0) + add <= upper);
      });
      if (!can) hard.add(k);
    }
    final e = d.share('energy') ?? 1, p = d.share('protein') ?? 1;
    return MenuCheck(reached: reached, low: [for (final x in low) x.$1], hard: hard, energyOk: (e - 1).abs() <= 0.1, proteinOk: p >= 0.85);
  }

  // ── Eén dag ──

  List<MenuItem> _planDay(Map<String, Target> targets, Set<Meal> meals, math.Random rnd, Map<String, int> weekUse, Set<String> lastDay) {
    final w = _Work(targets, meals, const []);
    final goal = targets['energy']?.goal ?? 2000;
    // 1. Een kern per maaltijd
    for (final meal in Meal.values) {
      if (!meals.contains(meal)) continue;
      final budget = goal * (input.shares[meal] ?? 0.25) / _shareSum(meals);
      MenuBlock? best;
      var bestScore = 0.0;
      for (final b in input.blocks) {
        if (b.meal != meal || b.items.isEmpty) continue;
        // Een snack hoeft geen standaardmaaltijd te zijn: die vult de gulzige stap zelf
        if (meal == Meal.snacks && b.source == MenuSource.staple) continue;
        if (b.items.any((i) => w.dayCount(i.food.key) >= 2)) continue;
        final fit = 1 / (1 + 1.5 * (b.kcal / budget - 1).abs());
        final used = weekUse['block:${b.id}'] ?? 0;
        final yesterday = lastDay.contains('block:${b.id}') ? 0.4 : 1.0;
        final s = b.weight * (0.7 + 0.6 * rnd.nextDouble()) / (1 + 1.5 * used) * yesterday * fit;
        if (s > bestScore) {
          bestScore = s;
          best = b;
        }
      }
      if (best != null) {
        for (final i in best.items) {
          w.add(i.copyWith(blockId: best.id));
        }
      }
    }

    // 2. Gulzig: telkens de beste stap, een product erbij of een portie groter of kleiner
    final cands = _candidates(meals);
    // Een beetje toeval per product, zodat "Opnieuw" iets anders geeft bij bijna gelijke keuzes
    final jitter = {for (final c in cands) c: 1 + 0.06 * (rnd.nextDouble() - 0.5)};
    var current = _score(w);
    for (var round = 0; round < 24; round++) {
      MenuItem? bestAdd;
      (int, double)? bestScale;
      var bestGain = 0.004;
      for (final c in cands) {
        if (!w.fits(c)) continue;
        // Wat deze week al vaak voorkwam, iets minder graag
        final used = (weekUse[c.food.key] ?? 0) + (lastDay.contains(c.food.key) ? 1 : 0);
        w.add(c);
        final gain = (_score(w) - current + _bonus(c)) * jitter[c]! - (c.source == MenuSource.advice ? 0.1 : 0.06) * used;
        w.removeLast();
        if (gain > bestGain) {
          bestGain = gain;
          bestAdd = c;
          bestScale = null;
        }
      }
      for (var i = 0; i < w.items.length; i++) {
        final it = w.items[i];
        for (final g in _scaled(it)) {
          w.setAt(i, it.copyWith(grams: g));
          final gain = _score(w) - current;
          w.setAt(i, it);
          if (gain > bestGain) {
            bestGain = gain;
            bestScale = (i, g);
            bestAdd = null;
          }
        }
      }
      if (bestAdd != null) {
        w.add(bestAdd);
      } else if (bestScale case (final i, final g)?) {
        w.setAt(i, w.items[i].copyWith(grams: g));
      } else {
        break;
      }
      current = _score(w);
    }

    // 3. Kleine verbetering: weglaten en omwisselen
    for (var pass = 0; pass < 2; pass++) {
      var improved = false;
      // Weglaten wat niets bijdraagt (maar niet de laatste regel van een maaltijd)
      for (var i = w.items.length - 1; i >= 0; i--) {
        final it = w.items[i];
        if (w.mealCount[it.meal.index] <= 1) continue;
        w.removeAt(i);
        final s = _score(w);
        // De kern van een maaltijd (je gewone ontbijt, een recept) alleen weglaten als het echt beter is
        if (s > current + (it.blockId != null ? 0.08 : 0.002)) {
          current = s;
          improved = true;
        } else {
          w.insertAt(i, it);
        }
      }
      // Omwisselen: een bijgezet product voor een beter, in dezelfde hoeveelheid energie ongeveer
      for (var i = 0; i < w.items.length; i++) {
        final it = w.items[i];
        if (it.blockId != null) continue;
        w.removeAt(i);
        MenuItem? best;
        var bestS = current + 0.01;
        for (final c in cands) {
          if (c.meal != it.meal || c.food.key == it.food.key || !w.fits(c)) continue;
          w.add(c);
          final s = _score(w) + _bonus(c) - _bonus(it);
          w.removeLast();
          if (s > bestS) {
            bestS = s;
            best = c;
          }
        }
        w.insertAt(i, best ?? it);
        if (best != null) {
          current = _score(w);
          improved = true;
        }
      }
      if (!improved) break;
    }

    // Volgorde: per maaltijd, zoals in het dagboek; adviesproducten met de stoffen die ze aanvullen
    final items = [...w.items]..sort((a, b) => a.meal.index.compareTo(b.meal.index));
    return [for (final i in items) i.source == MenuSource.advice ? _withReasons(i, targets) : i];
  }

  /// Andere hoeveelheden voor een regel: tussen de helft en anderhalf keer (zetmeel: twee keer) de gewone portie.
  static Iterable<double> _scaled(MenuItem it) sync* {
    final most = it.food.role == MenuRole.starch ? 2.0 : 1.5;
    final seen = <double>{it.grams};
    for (final f in const [0.75, 1.25, 1.5]) {
      final g = _round(it, it.grams * f);
      if (g < 10 || g > 600 || g < it.base * 0.5 - 0.1 || g > it.base * most + 0.1 || !seen.add(g)) continue;
      yield g;
    }
  }

  double _shareSum(Set<Meal> meals) {
    final s = meals.fold(0.0, (a, m) => a + (input.shares[m] ?? 0.25));
    return s <= 0 ? 1 : s;
  }

  /// Alle losse producten die bij een geplande maaltijd kunnen.
  List<MenuItem> _candidates(Set<Meal> meals) {
    final out = <MenuItem>[];
    final seen = <String>{};
    for (final e in input.extras) {
      if (meals.contains(e.meal) && seen.add('${e.food.key}|${e.meal.index}')) out.add(e);
    }
    // Een adviesproduct kan bij de twee maaltijden waar het het best past
    for (final a in input.advice) {
      final options = _mealsFor(a.food).where(meals.contains).take(2).toList();
      for (final meal in options.isEmpty ? meals.take(1) : options) {
        if (!seen.add('${a.key}|${meal.index}')) continue;
        for (final (g, portion) in menuAmounts(a.food)) {
          out.add(MenuItem(food: a, grams: g, meal: meal, source: MenuSource.advice, portion: portion));
        }
      }
    }
    return out;
  }

  /// Een kleine voorkeur voor wat je zelf eet.
  static double _bonus(MenuItem c) => switch (c.source) {
    MenuSource.habit || MenuSource.saved || MenuSource.recipe => 0.06,
    MenuSource.staple => 0.02,
    MenuSource.advice => 0,
  };

  /// Een portie in halve stappen, anders op 5 g.
  static double _round(MenuItem it, double g) {
    final p = it.portion;
    if (p != null && p.grams > 0) return math.max(0.5, (g / p.grams * 2).round() / 2) * p.grams;
    return (g / 5).round() * 5.0;
  }

  /// Stoffen waar [c] een flink deel (minstens 15%) van het doel aanbrengt, het grootste deel eerst.
  MenuItem _withReasons(MenuItem c, Map<String, Target> targets) {
    final r = <(String, double)>[];
    for (final k in stripKeys) {
      final g = targets[k]?.goal;
      if (g == null || g <= 0) continue;
      final part = c.amount(k) / g;
      if (part >= 0.15) r.add((k, part * (1 + (input.focus[k] ?? 0))));
    }
    r.sort((a, b) => b.$2.compareTo(a.$2));
    return c.copyWith(reasons: [for (final x in r.take(3)) x.$1]);
  }

  /// Dagscore: hoger is beter.
  double _score(_Work w) {
    final t = w.tot;
    final g = w.goals;
    var s = 0.0;
    // Energie: zwaar, en nog zwaarder buiten ±10%
    final e = g[_iE] > 0 ? t[_iE] / g[_iE] : 1.0;
    final de = (e - 1).abs();
    s -= 10 * de + (de > 0.05 ? 25 * (de - 0.05) : 0);
    // Eiwit: tekort weegt, en ver boven je doel ook (anders vult vlees en zuivel de kcal op)
    if (g[_iP] > 0) {
      final p = t[_iP] / g[_iP];
      s -= 3.5 * math.max(0, 1 - p) + (p < 0.9 ? 6 * (0.9 - p) : 0) + 2.5 * math.max(0, p - 1.15) + 6 * math.max(0, p - 1.35);
    }
    // Koolhydraten en vet: binnen een ruime marge
    for (final i in const [_iC, _iF]) {
      if (g[i] > 0) s -= 1.0 * math.max(0, (t[i] / g[i] - 1).abs() - 0.25);
    }
    if (g[_iFib] > 0) s -= 1.0 * math.max(0, 1 - t[_iFib] / g[_iFib]);
    // Vitaminen en mineralen (zoals de Voedingsscore, met je gewone tekorten zwaarder)
    var sum = 0.0, n = 0.0;
    for (var i = 0; i < _keys.length; i++) {
      final wt = _focusW[i];
      if (wt == 0 || g[i] <= 0) continue;
      sum += wt * math.min(1, t[i] / g[i]);
      n += wt;
    }
    if (n > 0) s += 4 * sum / n;
    // Bovengrenzen
    for (var i = 0; i < _keys.length; i++) {
      final u = w.uppers[i];
      if (u > 0 && t[i] > u) s -= 0.3 + 1.5 * (t[i] / u - 1);
    }
    // Suiker: met "Let op suiker" al vanaf de helft van de grens, en koolhydraten boven je doel
    if (input.sugarFocus) {
      final u = w.uppers[_iFree] > 0 ? w.uppers[_iFree] : (g[_iE] > 0 ? g[_iE] * 0.1 / 4 : 50);
      final free = t[_iFree] > 0 ? t[_iFree] : t[_iSug] * 0.5;
      s -= 2 * math.max(0, free / u - 0.5);
      if (g[_iC] > 0) s -= 1.5 * math.max(0, t[_iC] / g[_iC] - 1);
    }
    // Dubbels op één dag en te veel adviesproducten
    s -= 0.15 * w.dups;
    if (w.adviceCount > 3) s -= 0.5 * (w.adviceCount - 3);
    // Verdeling over de maaltijden en niet te veel regels per maaltijd
    for (final m in w.meals) {
      final want = g[_iE] * (input.shares[m] ?? 0.25) / _shareSum(w.meals);
      final have = w.mealKcal[m.index];
      if (want > 0) s -= 1.2 * math.min(1, (have / want - 1).abs());
      if (w.mealCount[m.index] > 4) s -= 0.4 * (w.mealCount[m.index] - 4);
      final roles = w.roles[m.index];
      if (roles[MenuRole.starch.index] > 1) s -= 0.6 * (roles[MenuRole.starch.index] - 1);
      if (roles[MenuRole.protein.index] > 1) s -= 0.7 * (roles[MenuRole.protein.index] - 1);
      if (roles[MenuRole.dairy.index] > 2) s -= 0.4 * (roles[MenuRole.dairy.index] - 2);
    }
    // Liever een paar dingen dan veel kleine
    s -= 0.02 * w.items.length;
    return s;
  }
}

/// Werkdag: regels met lopende totalen, zodat toevoegen en terugnemen snel gaat.
class _Work {
  _Work(Map<String, Target> targets, this.meals, List<MenuItem> start) : goals = Float64List(_keys.length), uppers = Float64List(_keys.length) {
    for (final (i, k) in _keys.indexed) {
      goals[i] = targets[k]?.goal ?? 0;
      uppers[i] = targets[k]?.upper ?? 0;
    }
    for (final i in start) {
      add(i);
    }
  }
  final Set<Meal> meals;
  final Float64List goals, uppers;
  final tot = Float64List(_keys.length);
  final items = <MenuItem>[];
  final mealKcal = Float64List(Meal.values.length);
  final mealCount = List.filled(Meal.values.length, 0);
  final roles = [for (final _ in Meal.values) List.filled(MenuRole.values.length, 0)];
  final _counts = <String, int>{};
  int dups = 0, adviceCount = 0;

  int dayCount(String key) => _counts[key] ?? 0;

  /// Mag [c] er nog bij? Niet twee keer hetzelfde in één maaltijd, hoogstens twee keer per dag (brood 's ochtends
  /// en 's middags), een adviesproduct maar één keer en hoogstens drie, en één zetmeelproduct per maaltijd.
  bool fits(MenuItem c, {bool cap = true}) {
    final k = c.food.key;
    if ((_counts[k] ?? 0) >= 2) return false;
    if (items.any((i) => i.meal == c.meal && i.food.key == k)) return false;
    if (c.source == MenuSource.advice && ((_counts[k] ?? 0) > 0 || (cap && adviceCount >= 3))) return false;
    if (c.food.role == MenuRole.starch && roles[c.meal.index][MenuRole.starch.index] > 0) return false;
    return true;
  }

  void _apply(MenuItem it, double sign) {
    final v = it.food._vec;
    final f = it.grams / 100 * sign;
    for (var i = 0; i < v.length; i++) {
      tot[i] += v[i] * f;
    }
    mealKcal[it.meal.index] += it.kcal * sign;
    mealCount[it.meal.index] += sign.round();
    roles[it.meal.index][it.food.role.index] += sign.round();
    final k = it.food.key;
    final c = (_counts[k] ?? 0) + sign.round();
    if (sign > 0 && c > 1) dups++;
    if (sign < 0 && c >= 1) dups--;
    _counts[k] = c;
    if (it.source == MenuSource.advice) adviceCount += sign.round();
  }

  void add(MenuItem it) {
    items.add(it);
    _apply(it, 1);
  }

  void removeLast() => _apply(items.removeLast(), -1);
  void removeAt(int i) => _apply(items.removeAt(i), -1);
  void insertAt(int i, MenuItem it) {
    items.insert(i, it);
    _apply(it, 1);
  }

  void setAt(int i, MenuItem it) {
    _apply(items[i], -1);
    items[i] = it;
    _apply(it, 1);
  }
}
