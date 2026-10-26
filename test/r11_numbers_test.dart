import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/product_info.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/allergens.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/portions.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/friends.dart' show mondayOf;
import 'package:macromatrix/ui/screens/nutrients_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/macro_schedule.dart';

/// Ronde 11: getallen, scores, weekrapport, productcheck en zoeken (SP-4 … NF-19).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  AppState newState() => AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  Food byRef(String ref) => foods.byRef(ref)!;

  group('SP-7: energie telt mee in de Voedingsscore van een afgesloten dag', () {
    const goal = {'energy': Target(goal: 3000)};

    test('binnen ±15% niets, eronder tot ×0,75, erboven tot ×0,85', () {
      expect(energyScoreFactor(2600, 3000), 1);
      expect(energyScoreFactor(3400, 3000), 1);
      expect((98 * energyScoreFactor(2000, 3000)).round(), 85);
      expect((98 * energyScoreFactor(1000, 3000)).round(), 74);
      expect(energyScoreFactor(0, 3000), energyScoreMinUnder);
      expect(energyScoreFactor(4500, 3000), closeTo(energyScoreMinOver, 1e-9));
      expect(energyScoreFactor(9000, 3000), energyScoreMinOver);
      expect(energyScoreFactor(1000, null), 1);
    });

    test('vandaag loopt nog: geen aftrek, wel uitleg (als je erboven zit of s avonds)', () {
      final targets = targetsFor(const Profile(), year: 2026);
      final v = {for (final k in stripKeys) k: targets[k]!.goal ?? 0, 'energy': targets['energy']!.goal! * 0.6};
      final micro = completenessScore(v, targets);
      expect(dayScore(v, targets, closed: false), micro);
      expect(dayScore(v, targets), lessThan(micro));

      expect(scoreEnergyNote({'energy': 2000}, goal)!.$1, 'Score lowered: 1,000 kcal under your goal');
      expect(scoreEnergyNote({'energy': 3700}, goal)!.$1, 'Score lowered: 700 kcal over your goal');
      expect(scoreEnergyNote({'energy': 2700}, goal), isNull);
      expect(scoreEnergyNote({'energy': 1200}, goal, closed: false, hour: 10), isNull, reason: 'na het ontbijt is iedereen onder zijn doel');
      expect(scoreEnergyNote({'energy': 2000}, goal, closed: false, hour: 22)!.$1, 'Energy counts once the day is over: now 1,000 kcal under your goal');
      expect(scoreEnergyNote({'energy': 3700}, goal, closed: false, hour: 10)!.$2, isFalse);
    });

    test('weekrapport, weekscore en daggegevens gebruiken dezelfde score', () {
      final s = newState();
      final bread = foods.search('bread', limit: 1).first;
      final yesterday = DateTime(logicalNow().year, logicalNow().month, logicalNow().day).plusDays(-1);
      // Gisteren: 60% van je energie (een volledige dag, wel 40% onder je doel), op tijd gelogd
      s.setDate(yesterday);
      final grams = s.targets['energy']!.goal! * 0.6 / (bread.per100g['energy']! / 100);
      s.addFood(bread, meal: Meal.lunch, grams: grams, quantity: 1);
      final key = dayKey(yesterday);
      final v = s.dailyTotals(yesterday, yesterday)[key]!.values;
      final t = s.targetsForDate(yesterday);
      final expected = dayScore(v, t);
      expect(expected, lessThan(completenessScore(v, t)));
      expect(s.dayStats[key]!.score, expected);
      expect(s.dayStats[key]!.micro, completenessScore(v, t), reason: 'XP en badges zonder energiefactor');
      final r = s.weeklyReport(mondayOf(yesterday));
      if (r != null) expect(r.dayScores[key], expected);
      final week = s.weekScore(mondayOf(yesterday))!;
      if (week.days == 1) expect(week.score, expected);
    });
  });

  testWidgets('SP-7: de scorekaart van gisteren zegt waarom de score lager is', (tester) async {
    final s = newState();
    final bread = foods.search('bread', limit: 1).first;
    final yesterday = DateTime(logicalNow().year, logicalNow().month, logicalNow().day).plusDays(-1);
    s.setDate(yesterday);
    s.addFood(bread, meal: Meal.lunch, grams: s.targets['energy']!.goal! * 0.6 / (bread.per100g['energy']! / 100), quantity: 1);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: SingleChildScrollView(child: ScoreCard())),
        ),
      ),
    );
    final v = s.totals.values;
    expect(find.text('${dayScore(v, s.targets)} /100', findRichText: true), findsOneWidget);
    expect(find.textContaining('Score lowered:'), findsOneWidget);
    expect(find.textContaining('kcal under your goal'), findsOneWidget);
  });

  test('SU-4: de deelkaart toont de volledig gelogde dagen van het rapport, niet vandaag', () {
    final s = newState();
    final now = logicalNow();
    final monday = DateTime(mondayOf(now).year, mondayOf(now).month, mondayOf(now).day - 7);
    final bread = foods.search('bread', limit: 1).first;
    final grams = s.targets['energy']!.goal! / (bread.per100g['energy']! / 100);
    // Wo, do en vr van vorige week achteraf gelogd, za maar een beetje
    for (final i in [2, 3, 4]) {
      s.setDate(monday.plusDays(i));
      s.addFood(bread, meal: Meal.lunch, grams: grams, quantity: 1);
    }
    s.setDate(monday.plusDays(5));
    s.addFood(bread, meal: Meal.lunch, grams: 40, quantity: 1);
    final r = s.weeklyReport(monday)!;
    expect(r.days, 3);
    expect(r.dayScores.keys, [for (final i in [2, 3, 4]) dayKey(monday.plusDays(i))]);
    // Achteraf gelogd telt niet voor XP of battles, wel in het rapport en dus op de kaart
    expect(s.dayStats.keys.where((k) => k.compareTo(dayKey(monday)) >= 0 && k.compareTo(dayKey(monday.plusDays(6))) <= 0), isEmpty);
  });

  testWidgets('SP-4: het macroschema toont de echte verdeling van je doel', (tester) async {
    // Aankomen: eiwit volgt de onderhoudsenergie, dus minder dan 20% van een hoger doel
    final p = const Profile().copyWith(goal: Goal.gain);
    final t = targetsFor(p, year: 2026);
    final share = macroShare('protein', t['protein']!.goal!, t['energy']!.goal!) * 100;
    expect(share.round(), lessThan(p.proteinPct.round()));

    final s = newState()..saveProfile(p);
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: SingleChildScrollView(child: MacroScheduleCard())),
        ),
      ),
    );
    final today = s.todayTargets;
    final real = (macroShare('protein', today['protein']!.goal!, today['energy']!.goal!) * 100).round();
    expect(find.text('$real%'), findsWidgets);
    expect(find.text('${p.proteinPct.round()}%'), findsNothing);
    expect(find.textContaining('real shares of your daily goal'), findsOneWidget);
  });

  group('productcheck', () {
    late AdditiveCatalog catalog;
    setUpAll(() async => catalog = await AdditiveCatalog.load());

    test('NF-4: zonder ingrediëntenlijst geen "Excellent" en additieven niet als 100%', () {
      const drink = ProductInfo(code: '4065019142130', name: 'High protein drink', nutriscore: 'a');
      expect(drink.additivesKnown, isFalse);
      expect(drink.scoreIncomplete, isTrue);
      expect(drink.score(catalog), 86);
      const withList = ProductInfo(code: '1', name: 'x', nutriscore: 'a', ingredients: 'milk, cocoa');
      expect(withList.scoreIncomplete, isFalse);
      expect(withList.score(catalog), 90);
    });

    test('NF-13: E-nummers en gangbare namen uit de ingrediëntentekst', () {
      expect(additivesInText("farine de blé, sucre, mono- et diglycérides d'acides gras, émulsifiant: E322"), containsAll(['e471', 'e322']));
      expect(additivesInText('water, oats 10%, tricalcium phosphate, sea salt'), contains('e341'));
      expect(additivesInText('suiker, sojalecithine, aroma'), contains('e322'));
      expect(additivesInText('oats, water, salt'), isEmpty);
      const wafer = ProductInfo(
        code: '5410126832051',
        name: 'Gaufre',
        nutriscore: 'e',
        additiveTags: ['en:e481', 'en:e322'],
        ingredients: 'wheat flour, sugar, emulsifiers (mono- and diglycerides of fatty acids, E481, soy lecithin)',
      );
      expect(wafer.additives(catalog).map((a) => a.code), containsAll(['e481', 'e322', 'e471']));
    });

    test('NF-12: ingrediënten uit de EU en daarbuiten is gemengd', () {
      const granola = ProductInfo(code: '5400113739319', name: 'Granola', ingredientOrigins: ['en:european-union', 'en:non-european-union']);
      expect(granola.origin.region, Region.mixed);
      expect(granola.origin.place, 'the EU, outside the EU');
    });

    test('NF-3: alle allergenen op het etiket, ook zonder eigen allergie', () {
      final peanut = labelAllergens(const LabelInfo(allergens: ['en:peanuts'], ingredients: 'ARACHIDES 100%'));
      expect(peanut.contains, [Allergen.peanuts]);
      final waffle = labelAllergens(const LabelInfo(allergens: ['en:eggs', 'en:gluten', 'en:soybeans'], traces: ['en:milk']));
      expect(waffle.contains, containsAll([Allergen.eggs, Allergen.gluten, Allergen.soy]));
      expect(waffle.traces, [Allergen.milk]);
    });

    test('NF-9: betere keuzes uit België of Nederland eerst', () {
      final p = ProductInfo.fromOff({
        'code': '1',
        'product_name': 'Peanut butter',
        'countries_tags': ['en:belgium'],
      }, null);
      expect(p.soldNearby, isTrue);
      expect(const ProductInfo(code: '2', name: 'x', countries: ['en:france']).soldNearby, isFalse);
      expect(productInfoFields, contains('countries_tags'));
    });
  });

  group('zoeken', () {
    late AppState s;
    setUpAll(() => s = newState());
    Food box(String q) => groupFoods(s.searchLocal(q)).first.main;

    test('NF-7: chips zijn een zakje chips; Britse "chips" heten frietjes', () {
      for (final q in ['chips', 'potato chips']) {
        expect(box(q).name.toLowerCase(), contains('crisps'), reason: q);
        expect((box(q).per100g['energy'] ?? 0), greaterThan(400), reason: q);
      }
      expect(byRef('cofid:13-557').name, startsWith('French fries'));
      // Amerikaanse "potato chips" (USDA) zijn wel chips
      expect(byRef('usda_sr:170253').name, startsWith('Potato chips'));
    });

    test('NW-13: "oatmeal" geeft havervlokken; Noors havermeel heet "Oat flour"', () {
      expect(byRef('mvt:05.004').name, 'Oat flour');
      expect(box('oatmeal').name.toLowerCase(), isNot(contains('flour')));
      expect(box('oatmeal').name.toLowerCase(), contains('oat'));
    });

    test('NF-8: appelmoes en apple sauce: appelmoes, geen donut met vulling', () {
      for (final q in ['appelmoes', 'apple sauce', 'applesauce']) {
        final top = s.searchLocal(q).take(2).map((f) => f.name.toLowerCase());
        for (final n in top) {
          expect(n, matches(RegExp(r'apple ?sauce')), reason: '$q: $n');
          expect(n, isNot(contains('doughnut')), reason: q);
        }
      }
    });
  });

  group('porties', () {
    test('NF-15: een glas melk van 200 ml weegt 206 g; water 200 g', () {
      final milk = foods.search('semi-skimmed milk', limit: 5).firstWhere((f) => f.name.toLowerCase().startsWith('milk'));
      expect(mlDensity(milk), 1.03);
      final glass = everydayPortions(milk).firstWhere((p) => p.label.contains('glass'));
      expect(glass.grams, closeTo(206, 0.01));
      expect(glass.label, contains('200 ml'));
      const water = Food(ref: 'x:water', name: 'Water, tap', source: FoodSource.ciqual, per100g: {});
      expect(mlDensity(water), 1);
      const oatDrink = Food(ref: 'x:oat', name: 'Oat drink, unfortified', source: FoodSource.ciqual, per100g: {});
      expect(mlDensity(oatDrink), 1);
    });

    test('NF-14: visfilet 125 g, gekookte linzen 150 g zonder cup, amandelen een handvol', () {
      final salmon = foods.search('salmon farmed baked', limit: 20).firstWhere((f) => f.ref.startsWith('cofid:'));
      final fish = defaultServing(salmon);
      expect(fish.portion, isNull);
      expect(fish.quantity, 125);
      final lentils = foods.search('lentils cooked', limit: 30).firstWhere((f) => f.portions.any((p) => p.label.contains('cup')));
      final l = defaultServing(lentils);
      expect(l.portion?.label ?? '', isNot(contains('cup')), reason: lentils.name);
      expect(l.portion == null ? l.quantity : l.portion!.grams, 150);
      final almonds = foods.search('almonds', limit: 10).firstWhere((f) => isNuts(f));
      final a = defaultServing(almonds);
      // Een handvol (de databank heeft soms al een handvol van 20 à 30 g), geen 100 g
      expect(a.portion == null ? a.quantity : a.portion!.grams * a.quantity, inInclusiveRange(15, 40), reason: almonds.name);
    });

    test('NF-19: gerookte, gravad en gezouten vis in het Orakel: 50 g', () {
      final gravad = foods.search('salmon gravad', limit: 10).first;
      expect(AppState.oracleServing(gravad).grams, 50, reason: gravad.name);
      final salted = foods.search('mackerel salted', limit: 10).firstWhere((f) => f.name.toLowerCase().contains('salted'));
      expect(AppState.oracleServing(salted).grams, 50, reason: salted.name);
      final fresh = foods.search('salmon raw', limit: 10).first;
      expect(AppState.oracleServing(fresh).grams, 120);
    });
  });

  test('NF-18: EPA, DPA en DHA in mg, zoals EPA + DHA', () {
    final epa = nutrientByKey['epa']!;
    expect(epa.shownUnit, 'mg');
    expect(formatAmount(1.095, epa), '1,095');
    expect(nutrientByKey['epa_dha']!.shownUnit, 'mg');
    expect(formatAmount(3195, nutrientByKey['epa_dha']!), '3,195');
    expect(nutrientByKey['protein']!.shownUnit, 'g');
  });

  test('SU-15: geen drie keer hetzelfde product op de boodschappenlijst', () {
    final s = newState();
    final today = DateTime(logicalNow().year, logicalNow().month, logicalNow().day);
    final rice = foods.search('rice', limit: 1).first;
    for (var i = 1; i <= 4; i++) {
      s.setDate(today.plusDays(-i));
      s.addFood(rice, meal: Meal.lunch, grams: 300, quantity: 1);
    }
    final tips = s.shoppingTips();
    expect(tips, isNotEmpty);
    for (final (_, _, list) in tips) {
      final names = [for (final f in list) f.label?.food ?? f.name];
      expect(names.toSet().length, names.length, reason: '$names');
    }
  });
}
