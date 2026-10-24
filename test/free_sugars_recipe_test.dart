import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/export.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/custom_food_screen.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  Food food(String ref) => foods.byRef(ref)!;
  AppState state() => AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));

  ItemTemplate item(String ref, double grams) {
    final f = food(ref);
    return ItemTemplate(foodRef: ref, name: f.name, grams: grams, quantity: grams, per100g: f.per100g);
  }

  Food recipe(AppState s, String name, List<ItemTemplate> items, {double? cookedGrams}) {
    final r = Recipe(ref: UserDb.newRecipeRef(), name: name, servings: 2, ingredients: items, cookedGrams: cookedGrams);
    s.user.saveRecipe(r);
    return s.user.food(r.ref)!;
  }

  double sugarsOf(String ref, double grams) => food(ref).per100g['sugars']! * grams / 100;

  group('vrije suikers in recepten en eigen producten', () {
    test('recept met appel en yoghurt: geen vrije suikers, ook al zegt de naam niets', () {
      final s = state();
      final f = recipe(s, 'Ontbijtkom', [item('mvt:06.758', 150), item('ciqual:19593', 200)]);
      expect(f.per100g['sugars'], greaterThan(5));
      s.addFood(f, meal: Meal.breakfast, grams: 200, quantity: 200);
      expect(s.totals['sugars'], greaterThan(10));
      expect(s.totals['free_sugars'], closeTo(0, 0.01));
      expect(s.per100gWithSugars(f)['free_sugars'], closeTo(0, 0.01));
    });

    test('recept met cola en honing: die suikers tellen wel, de appel niet (ook met gewicht na bereiding)', () {
      final s = state();
      final f = recipe(s, 'Appelstoof', [item('mvt:06.758', 300), item('ciqual:31008', 30), item('ciqual:18018', 200)], cookedGrams: 400);
      final free = sugarsOf('ciqual:31008', 30) + sugarsOf('ciqual:18018', 200);
      final all = free + sugarsOf('mvt:06.758', 300);
      // Per 100 g van het eindresultaat (400 g na bereiding)
      expect(s.per100gWithSugars(f)['free_sugars'], closeTo(free / 4, 0.01));
      s.addFood(f, meal: Meal.dinner, grams: 400, quantity: 400);
      expect(s.totals['free_sugars'], closeTo(free, 0.01));
      expect(s.totals['sugars'], closeTo(all, 0.01));
    });

    test('eigen product: zelf ingevulde vrije suikers gaan voor op de naam', () {
      final s = state();
      final own = Food(
        ref: UserDb.newCustomRef(),
        name: 'Mijn granola',
        source: FoodSource.custom,
        per100g: const {'energy': 450, 'sugars': 20, 'free_sugars': 8},
      );
      s.saveCustomFood(own);
      s.addFood(s.user.food(own.ref)!, meal: Meal.breakfast, grams: 50, quantity: 50);
      expect(s.totals['free_sugars'], closeTo(4, 0.001));
      // Zonder ingevulde waarde beslist de naam (granola: alles vrij)
      final guess = Food(ref: UserDb.newCustomRef(), name: 'Mijn granola', source: FoodSource.custom, per100g: const {'sugars': 20});
      expect(s.per100gWithSugars(guess)['free_sugars'], 20);
    });

    testWidgets('formulier eigen product bewaart "waarvan vrije suikers"', (tester) async {
      final s = state();
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const CustomFoodScreen()),
        ),
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Fruitreep');
      await tester.enterText(find.widgetWithText(TextFormField, 'Sugars'), '30');
      final freeField = find.widgetWithText(TextFormField, 'of which free/added sugars (optional)');
      expect(freeField, findsOneWidget);
      // Meer vrije suikers dan suikers kan niet
      await tester.enterText(freeField, '40');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.textContaining('At most the sugars'), findsOneWidget);
      await tester.enterText(freeField, '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = s.user.customFoods().singleWhere((f) => f.name == 'Fruitreep');
      expect(saved.per100g['free_sugars'], 12);
      expect(s.per100gWithSugars(saved)['free_sugars'], 12);
    });

    test('CSV: kolom met vrije suikers, per regel zoals in de totalen', () {
      final s = state();
      s.addFood(food('mvt:06.758'), meal: Meal.snacks, grams: 200, quantity: 200);
      s.addFood(food('ciqual:18018'), meal: Meal.snacks, grams: 330, quantity: 330);
      final lines = diaryCsv(s.user, values: s.entryValues).trim().split('\n');
      final header = lines.first.split(',');
      final col = header.indexOf('Free sugars (g)');
      expect(col, greaterThan(0));
      // Van achteren tellen: productnamen met een komma staan tussen aanhalingstekens
      String freeOf(String product) {
        final cells = lines.firstWhere((l) => l.contains(product)).split(',');
        return cells[cells.length - header.length + col];
      }

      expect(freeOf(food('mvt:06.758').name), '0');
      expect(double.parse(freeOf(food('ciqual:18018').name)), closeTo(sugarsOf('ciqual:18018', 330), 0.01));
      // Ook zonder app-status is de kolom gevuld (schatting uit de naam)
      final plain = diaryCsv(s.user).trim().split('\n');
      expect(plain.first.split(',').indexOf('Free sugars (g)'), col);
      expect(plain.last.split(',').length, greaterThanOrEqualTo(header.length));
    });

    testWidgets('productscherm: "Free sugars" meteen onder Sugars', (tester) async {
      final s = state();
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: FoodDetailScreen(food: food('ciqual:18018'), meal: Meal.snacks, initialGrams: 330),
          ),
        ),
      );
      await tester.pump();
      final free = find.text('Free sugars');
      expect(free, findsWidgets);
      final sugars = find.text('Sugars');
      expect(sugars, findsWidgets);
      expect(tester.getTopLeft(free.last).dy, greaterThan(tester.getTopLeft(sugars.last).dy));
      expect(tester.takeException(), isNull);
    });
  });
}
