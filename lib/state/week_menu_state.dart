/// Weekmenu in de planner: verzamelt wat je zelf eet (gewone maaltijden, bewaarde maaltijden, recepten, vaste
/// producten), gewone adviesproducten voor je tekorten en eenvoudige standaardmaaltijden, en zet een voorstel in de
/// planner en op de boodschappenlijst. Het rekenwerk zelf staat in nutrition/week_menu.dart.
library;

import 'dart:math' as math;

import '../data/food.dart';
import '../data/food_db.dart';
import '../data/models.dart';
import '../data/plan.dart';
import '../data/user_db.dart';
import '../i18n.dart';
import '../nutrition/allergens.dart';
import '../nutrition/insights.dart' show stripKeys;
import '../nutrition/nutrients.dart';
import '../nutrition/preferences.dart';
import '../nutrition/gap_plan.dart' show isAdviceFood, isEverydayFood;
import '../nutrition/portions.dart' show everydayPortions, typicalPieceGrams;
import '../nutrition/week_menu.dart';
import 'app_state.dart';

export '../nutrition/week_menu.dart';

/// Je gewone maaltijden: welke je meestal eet en welk deel van je energie elk krijgt.
class MealPattern {
  const MealPattern(this.usual, this.shares);
  final Set<Meal> usual;
  final Map<Meal, double> shares;
}

/// Eenvoudige standaardmaaltijden voor wie nog weinig gelogd heeft: (maaltijd, Engels, Nederlands, producten).
/// Een product is `<gram> g <zoekterm>`, `<aantal> slices <zoekterm>` of `<aantal> <zoekterm>`.
const _stapleMeals = <(Meal, String, String, List<String>)>[
  (Meal.breakfast, 'Oats with milk and banana', 'Havermout met melk en banaan', ['50 g rolled oats', '250 g semi-skimmed milk', '1 banana']),
  (Meal.breakfast, 'Bread with eggs', 'Brood met eieren', ['2 slices wholemeal bread', '2 egg boiled', '1 orange']),
  (Meal.breakfast, 'Yogurt with fruit and nuts', 'Yoghurt met fruit en noten', ['200 g yogurt plain', '1 apple', '20 g walnuts']),
  (Meal.lunch, 'Cheese sandwiches', 'Boterhammen met kaas', ['3 slices wholemeal bread', '2 slices gouda', '1 tomato']),
  (Meal.lunch, 'Tuna sandwiches', 'Boterhammen met tonijn', ['3 slices wholemeal bread', '80 g tuna', '100 g cucumber']),
  (Meal.lunch, 'Lentil soup with bread', 'Linzensoep met brood', ['300 g lentil soup', '2 slices wholemeal bread']),
  (
    Meal.dinner,
    'Chicken, potatoes and broccoli',
    'Kip, aardappelen en broccoli',
    ['150 g chicken breast grilled', '300 g potato boiled', '200 g broccoli'],
  ),
  (
    Meal.dinner,
    'Salmon, rice and green beans',
    'Zalm, rijst en sperziebonen',
    ['125 g salmon steamed', '180 g brown rice cooked', '150 g green beans boiled'],
  ),
  (Meal.dinner, 'Pasta with minced beef', 'Pasta met gehakt', ['220 g pasta boiled', '100 g minced beef cooked', '2 tomato']),
  (Meal.dinner, 'Lentils with sweet potato', 'Linzen met zoete aardappel', ['220 g lentils cooked', '250 g sweet potato', '1 carrot']),
  (Meal.dinner, 'Tofu, rice and broccoli', 'Tofu, rijst en broccoli', ['200 g tofu', '180 g brown rice cooked', '200 g broccoli']),
  (Meal.dinner, 'Cod, potatoes and spinach', 'Kabeljauw, aardappelen en spinazie', ['150 g cod steamed', '300 g potato boiled', '150 g spinach']),
];

/// Gewone losse producten om bij te zetten.
const _stapleExtras = <(Meal, String)>[
  (Meal.breakfast, '200 g semi-skimmed milk'),
  (Meal.breakfast, '1 egg boiled'),
  (Meal.breakfast, '1 slices wholemeal bread'),
  (Meal.lunch, '1 slices wholemeal bread'),
  (Meal.lunch, '1 slices gouda'),
  (Meal.lunch, '1 carrot'),
  (Meal.lunch, '150 g cottage cheese'),
  (Meal.lunch, '120 g chickpeas'),
  (Meal.lunch, '2 egg boiled'),
  (Meal.dinner, '150 g brown rice cooked'),
  (Meal.dinner, '200 g potato boiled'),
  (Meal.dinner, '150 g broccoli'),
  (Meal.dinner, '150 g green beans boiled'),
  (Meal.dinner, '100 g chicken breast grilled'),
  (Meal.dinner, '150 g chickpeas'),
  (Meal.dinner, '150 g tofu'),
  (Meal.snacks, '1 apple'),
  (Meal.snacks, '1 pear'),
  (Meal.snacks, '1 banana'),
  (Meal.snacks, '25 g almonds'),
  (Meal.snacks, '150 g yogurt plain'),
];

/// Vaak lage stoffen om adviesproducten voor te zoeken als je eigen tekorten nog niet bekend zijn.
const _commonGaps = ['vit_d', 'b9', 'magnesium', 'potassium', 'calcium', 'iron', 'iodine', 'vit_e', 'zinc'];

/// Opgezochte standaardproducten per databank (de databank verandert niet tijdens het gebruik).
final _resolved = Expando<Map<String, (Food, double, Portion?)?>>();

extension WeekMenuPlanning on AppState {
  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Welke maaltijden je meestal logt (op minstens 40% van de dagen) en hun deel van je energie, over 28 dagen.
  /// Met weinig geschiedenis: ontbijt, lunch, avondeten en een snack.
  MealPattern mealPattern() {
    final today = _dayOnly(logicalNow());
    final history = user.entriesBetween(dayKey(today.plusDays(-28)), dayKey(today.plusDays(-1)));
    final perDay = <String, List<double>>{};
    for (final e in history) {
      if (e.foodRef.startsWith('supp:')) continue;
      final kcal = (e.per100g['energy'] ?? 0) * e.grams / 100;
      (perDay[e.day] ??= List.filled(Meal.values.length, 0))[e.meal.index] += kcal;
    }
    if (perDay.length < 3) return const MealPattern({...Meal.values}, defaultMealShares);
    final days = <Meal, int>{};
    final share = <Meal, double>{};
    for (final d in perDay.values) {
      final total = d.fold(0.0, (a, b) => a + b);
      if (total <= 0) continue;
      for (final m in Meal.values) {
        if (d[m.index] > 0) days[m] = (days[m] ?? 0) + 1;
        share[m] = (share[m] ?? 0) + d[m.index] / total / perDay.length;
      }
    }
    final usual = {
      for (final m in Meal.values)
        if ((days[m] ?? 0) >= perDay.length * 0.4) m,
    };
    if (usual.isEmpty) return const MealPattern({...Meal.values}, defaultMealShares);
    // Een maaltijd die je zelden eet, krijgt bij het plannen toch een gewoon deel
    return MealPattern(usual, {for (final m in Meal.values) m: math.max(share[m] ?? 0, (defaultMealShares[m] ?? 0.2) * 0.5)});
  }

  /// Stoffen die je de laatste 14 dagen vaak te weinig had: sleutel → gewicht (0..1), 1 = gemiddeld onder 30%.
  Map<String, double> usualShortfalls() {
    final today = _dayOnly(logicalNow());
    final daily = dailyTotals(today.plusDays(-14), today.plusDays(-1));
    if (daily.length < 3) return const {};
    final avg = <String, double>{};
    for (final e in daily.entries) {
      final t = targetsForDate(parseDay(e.key));
      for (final k in stripKeys) {
        final g = t[k]?.goal;
        if (g != null && g > 0) avg[k] = (avg[k] ?? 0) + math.min(1.5, (e.value.values[k] ?? 0) / g) / daily.length;
      }
    }
    return {
      for (final e in avg.entries)
        if (e.value < 0.8) e.key: ((0.8 - e.value) / 0.5).clamp(0.2, 1.0),
    };
  }

  bool _allowed(Food f) => fitsPreferences(f, preferences) && !containsAllergen(f, allergies);

  /// Het volledige product achter een opgeslagen regel, of een reconstructie.
  Food _foodOf(String ref, ItemTemplate t) => (FoodDb.isDbRef(ref) ? foods.byRef(ref) : user.food(ref)) ?? t.toFood();

  /// Een standaardproduct opzoeken: het eerste gewone (advies)product voor de zoekterm, met een herkenbare portie
  /// bij een aantal stuks of sneetjes. Bewust eenvoudig en snel (geen volledige Snel loggen-ontleding).
  (Food, double, Portion?)? _resolve(String phrase) {
    final cache = _resolved[foods] ??= {};
    if (cache.containsKey(phrase)) return cache[phrase];
    final m = RegExp(r'^(\d+)\s+(?:(g|slices)\s+)?(.+)$').firstMatch(phrase)!;
    final n = double.parse(m[1]!);
    final unit = m[2];
    final hits = foods.search(m[3]!, limit: 60);
    final f = hits.where(isAdviceFood).firstOrNull ?? hits.where(isEverydayFood).firstOrNull;
    if (f == null) return cache[phrase] = null;
    if (unit == 'g') return cache[phrase] = (f, n, null);
    final slice = unit == 'slices';
    final options = [
      for (final p in [...f.portions, ...everydayPortions(f)])
        if (p.label.startsWith('1 ') && p.grams >= 8 && p.grams <= 250) p,
    ];
    final portion =
        options.where((p) => slice ? p.label.contains(RegExp('slice|sneetje')) : p.label.contains(RegExp(r'pcs|piece|stuk|medium'))).firstOrNull ??
        options.firstOrNull ??
        switch (typicalPieceGrams(f.name.toLowerCase())) {
          final g? => Portion(tr('1 piece', '1 stuk'), g),
          null => null,
        };
    return cache[phrase] = portion == null ? (f, n * 100, null) : (f, n * portion.grams, portion);
  }

  /// Alles waaruit een weekmenu gekozen wordt. Eén keer opbouwen per scherm; daarna is voorstellen snel.
  WeekMenuPlanner weekMenuPlanner() {
    final menuFoods = <String, MenuFood>{};
    MenuFood mf(Food f) => menuFoods[f.ref] ??= MenuFood(f, per100gWithSugars(f));
    Portion? portionOf(String? label, double grams, double quantity) => label == null || quantity <= 0 ? null : Portion(label, grams / quantity);

    final blocks = <MenuBlock>[];
    final extras = <MenuItem>[];

    // 1. Wat je zelf at (28 dagen): hele maaltijden die terugkomen en losse producten die je vaak bij een maaltijd eet
    final today = _dayOnly(logicalNow());
    final history = [
      for (final e in user.entriesBetween(dayKey(today.plusDays(-28)), dayKey(today.plusDays(-1))))
        if (!e.foodRef.startsWith('supp:')) e,
    ];
    final loggedDays = {for (final e in history) e.day}.length;
    final byMealDay = <(Meal, String), List<DiaryEntry>>{};
    for (final e in history) {
      (byMealDay[(e.meal, e.day)] ??= []).add(e);
    }
    final combos = <String, (Meal, Set<String>, List<DiaryEntry>)>{};
    final singles = <(Meal, String), (Set<String>, DiaryEntry)>{};
    for (final entry in byMealDay.entries) {
      final (meal, day) = entry.key;
      final list = [...entry.value]..sort((a, b) => a.foodRef.compareTo(b.foodRef));
      final key = '${meal.index}|${list.map((e) => e.foodRef).join(',')}';
      final c = combos[key];
      if (c == null || day.compareTo(c.$3.first.day) > 0) {
        combos[key] = (meal, {...?c?.$2, day}, list);
      } else {
        c.$2.add(day);
      }
      for (final e in list) {
        final s = singles[(meal, e.foodRef)];
        if (s == null || day.compareTo(s.$2.day) > 0) {
          singles[(meal, e.foodRef)] = ({...?s?.$1, day}, e);
        } else {
          s.$1.add(day);
        }
      }
    }
    MenuItem? fromEntry(DiaryEntry e, MenuSource src, {String? block}) {
      final f = foodFor(e);
      if (!_allowed(f) || e.grams <= 0) return null;
      return MenuItem(food: mf(f), grams: e.grams, meal: e.meal, source: src, portion: portionOf(e.portionLabel, e.grams, e.quantity), block: block);
    }

    for (final c in combos.entries) {
      final (meal, days, list) = c.value;
      if (days.length < 2) continue;
      final name = list.map((e) => e.name.split(',').first).take(3).join(', ');
      final items = [for (final e in list) ?fromEntry(e, MenuSource.habit, block: name)];
      if (items.length != list.length || items.isEmpty) continue;
      blocks.add(
        MenuBlock(
          id: 'habit:${c.key}',
          name: name,
          meal: meal,
          items: items,
          weight: 1 + 3 * days.length / math.max(loggedDays, 1),
          source: MenuSource.habit,
        ),
      );
    }
    for (final s in singles.entries) {
      if (s.value.$1.length < 2) continue;
      if (fromEntry(s.value.$2, MenuSource.habit) case final it?) extras.add(it);
    }

    // 2. Bewaarde maaltijden: bij hun eigen maaltijd, of anders bij lunch en avondeten
    for (final m in savedMeals()) {
      final meals = m.mealIndex != null && m.mealIndex! < Meal.values.length ? [Meal.values[m.mealIndex!]] : const [Meal.lunch, Meal.dinner];
      for (final meal in meals) {
        final items = <MenuItem>[];
        for (final t in m.items) {
          final f = _foodOf(t.foodRef, t);
          if (!_allowed(f) || t.grams <= 0) break;
          items.add(
            MenuItem(
              food: mf(f),
              grams: t.grams,
              meal: meal,
              source: MenuSource.saved,
              portion: portionOf(t.portionLabel, t.grams, t.quantity),
              block: m.name,
            ),
          );
        }
        if (items.length == m.items.length && items.isNotEmpty) {
          blocks.add(MenuBlock(id: 'saved:${m.id}:${meal.index}', name: m.name, meal: meal, items: items, weight: 1.2, source: MenuSource.saved));
        }
      }
    }

    // 3. Recepten: één portie bij lunch of avondeten (alleen als alle ingrediënten passen)
    for (final r in recipes()) {
      if (r.servings <= 0 || r.totalGrams <= 0) continue;
      final f = user.food(r.ref) ?? r.toFood();
      if (!_allowed(f) || r.ingredients.any((i) => !_allowed(_foodOf(i.foodRef, i)))) continue;
      final serving = r.totalGrams / r.servings;
      final portion = f.portions.firstOrNull ?? Portion(tr('1 serving', '1 portie'), serving);
      for (final meal in const [Meal.lunch, Meal.dinner]) {
        blocks.add(
          MenuBlock(
            id: 'recipe:${r.ref}:${meal.index}',
            name: r.name,
            meal: meal,
            items: [MenuItem(food: mf(f), grams: serving, meal: meal, source: MenuSource.recipe, portion: portion, block: r.name)],
            weight: 1.0,
            source: MenuSource.recipe,
          ),
        );
      }
    }

    // 4. Eenvoudige standaardmaaltijden en bijgerechten (wat niet bij je voorkeuren past, valt weg)
    for (final (meal, en, nl, phrases) in _stapleMeals) {
      final name = tr(en, nl);
      final items = <MenuItem>[];
      for (final p in phrases) {
        final r = _resolve(p);
        if (r == null || !_allowed(r.$1)) continue;
        items.add(MenuItem(food: mf(r.$1), grams: r.$2, meal: meal, source: MenuSource.staple, portion: r.$3, block: name));
      }
      // Zonder het hoofdbestanddeel (bv. kip voor een vegetariër) is het geen maaltijd meer
      if (items.length >= phrases.length - 1 && items.isNotEmpty) {
        blocks.add(MenuBlock(id: 'staple:$en', name: name, meal: meal, items: items, weight: 0.3, source: MenuSource.staple));
      }
    }
    for (final (meal, p) in _stapleExtras) {
      final r = _resolve(p);
      if (r == null || !_allowed(r.$1)) continue;
      extras.add(MenuItem(food: mf(r.$1), grams: r.$2, meal: meal, source: MenuSource.staple, portion: r.$3));
    }

    // 5. Adviesproducten voor je gewone tekorten (en eiwit)
    final focus = usualShortfalls();
    final keys = [
      ...(focus.keys.toList()..sort((a, b) => focus[b]!.compareTo(focus[a]!))).take(5),
      for (final k in _commonGaps)
        if (!focus.containsKey(k)) k,
    ].take(5).toList();
    // Per stof een paar verschillende producten (niet tien soorten spinazie)
    final advice = <MenuFood>[];
    final seen = <String>{};
    for (final k in ['protein', ...keys]) {
      var n = 0;
      for (final (f, _) in richestFor(k, perKcal: true, limit: 20, advice: true)) {
        final m = mf(f);
        if (!seen.add(m.key)) continue;
        advice.add(m);
        if (++n >= 6) break;
      }
    }

    return WeekMenuPlanner(
      WeekMenuInput(blocks: blocks, extras: extras, advice: advice, focus: focus, shares: mealPattern().shares, sugarFocus: sugarFocus),
    );
  }

  /// Een voorstel voor [count] dagen vanaf [start].
  WeekMenu proposeWeekMenu(WeekMenuPlanner planner, {required DateTime start, int count = 7, required Set<Meal> meals, int seed = 0}) {
    final s = _dayOnly(start);
    return planner.propose(
      days: [
        for (var i = 0; i < count; i++)
          () {
            final d = DateTime(s.year, s.month, s.day + i);
            return (d, targetsForDate(d));
          }(),
      ],
      meals: meals,
      seed: seed,
    );
  }

  static ItemTemplate _template(MenuItem i) => ItemTemplate(
    foodRef: i.food.food.ref,
    name: i.food.food.name,
    brand: i.food.food.brand,
    grams: i.grams,
    quantity: i.quantity,
    portionLabel: i.portion?.label,
    per100g: i.food.food.per100g,
  );

  /// Het menu in de planner zetten. Wat al gepland stond bij de gekozen maaltijden van die dagen, wordt vervangen;
  /// andere maaltijden blijven staan.
  void useWeekMenu(WeekMenu menu) {
    for (final d in menu.days) {
      final key = dayKey(d.date);
      setPlan(key, [
        for (final x in planFor(key))
          if (!menu.meals.contains(x.meal)) x,
        for (final i in d.items) PlannedItem(i.meal, _template(i)),
      ]);
    }
  }

  /// Alles uit het menu op de boodschappenlijst, per product opgeteld; bij adviesproducten staat waarvoor. Geeft het
  /// aantal producten terug.
  int shoppingFromMenu(WeekMenu menu) {
    final grams = <String, double>{};
    final reasons = <String, String>{};
    for (final d in menu.days) {
      for (final i in d.items) {
        final name = i.food.food.name;
        grams[name] = (grams[name] ?? 0) + i.grams;
        if (i.reasons.isNotEmpty) reasons[name] ??= nutrientByKey[i.reasons.first]?.name.toLowerCase() ?? '';
      }
    }
    final list = [...shopping];
    for (final e in grams.entries) {
      final at = list.indexWhere((x) => !x.done && x.name.toLowerCase() == e.key.toLowerCase());
      final reason = (reasons[e.key]?.isEmpty ?? true) ? null : reasons[e.key];
      if (at >= 0) {
        final old = list[at];
        list[at] = ShoppingItem(name: old.name, grams: (old.grams ?? 0) + e.value, reason: old.reason ?? reason);
      } else {
        list.add(ShoppingItem(name: e.key, grams: e.value, reason: reason));
      }
    }
    saveShopping(list);
    return grams.length;
  }
}
