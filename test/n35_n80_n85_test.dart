import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/screens/recipe_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Bevindingen van gebruikerstest ronde 9: exotische tips (N35), receptoverzicht (N80), melk en water in ml (N85).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  AppState state() => AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));

  Widget app(AppState s, Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  test('N35 geen paling, gans, viskuit of geroosterde sojabonen als tip', () {
    for (final q in ['eel', 'goose', 'cod roe', 'soybeans roasted']) {
      for (final f in foods.search(q, limit: 30)) {
        final food = f.label?.food ?? '';
        final odd = RegExp(r'\b(eel|goose|roe)\b').hasMatch(food) || (food == 'soybean' && f.label?.state == 'roasted');
        if (odd) expect(isAdviceFood(f), isFalse, reason: f.name);
      }
    }
    final s = state();
    for (final k in ['vit_d', 'vit_b12', 'protein', 'iron']) {
      for (final (f, _) in s.richestFor(k, perKcal: true, limit: 25, advice: true)) {
        expect(f.name, isNot(matches(RegExp(r'\b(eel|goose|roe)\b', caseSensitive: false))), reason: k);
      }
    }
  });

  group('N85', () {
    test('verhaspelde melknaam rechtgezet, water in ml', () {
      expect(tidyFoodName('Milk, whole, 3.5, (UHT), % fat'), 'Milk, whole, 3.5% fat (UHT)');
      expect(tidyFoodName('Milk, whole, UHT'), 'Milk, whole, UHT');
      expect(foods.byRef('frida:1265')!.name, 'Milk, whole, 3.5% fat (UHT)');
      expect(nutrientByKey['water']!.unit, 'ml');
    });

    testWidgets('melk op het productscherm in ml', (tester) async {
      final s = state();
      final milk = foods.search('semi-skimmed milk', limit: 5).firstWhere((f) => f.name.toLowerCase().startsWith('milk'));
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(s, FoodDetailScreen(food: milk, meal: Meal.breakfast)));
      await tester.pump();
      // Een glas is 200 ml; melk weegt 1,03 g per ml, dus 206 g (NF-15)
      expect(find.textContaining(RegExp(r'^= \d+ ml \(\d+ g\)$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^= \d+ g$')), findsNothing);
    });
  });

  group('N80 recept per portie', () {
    final recipe = Recipe(
      ref: 'recipe:test',
      name: 'Pancakes',
      servings: 2,
      ingredients: const [
        ItemTemplate(
          foodRef: 'custom:batter',
          name: 'Batter',
          grams: 400,
          quantity: 400,
          per100g: {'energy': 200, 'protein': 8, 'carbs': 30, 'sugars': 10, 'fat': 5, 'water': 50, 'caffeine': 1},
        ),
        ItemTemplate(foodRef: 'custom:honey', name: 'Honey', grams: 40, quantity: 40, per100g: {'energy': 300, 'carbs': 80, 'sugars': 80}),
      ],
    );

    test('vrije suikers uit de ingrediënten, ook voor een recept dat nog niet bewaard is', () {
      final t = state().recipeTotalsWithSugars(recipe);
      expect(t['sugars'], closeTo(72, 0.01));
      expect(t['free_sugars'], greaterThanOrEqualTo(32));
      expect(t['free_sugars'], lessThanOrEqualTo(72.01));
    });

    testWidgets('macro\'s bovenaan, water en cafeïne onderaan', (tester) async {
      tester.view.physicalSize = const Size(600, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(state(), RecipeScreen(existing: recipe)));
      await tester.pump();
      expect(find.textContaining('Protein 16 g · Carbs 76 g · Sugars 36 g · Fat 10 g'), findsOneWidget);
      final protein = tester.getTopLeft(find.text('Protein').last).dy;
      final water = tester.getTopLeft(find.text('Water').last).dy;
      expect(protein, lessThan(water));
    });
  });
}
