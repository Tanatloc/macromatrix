import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Productscherm: melding met Ongedaan maken na toevoegen (N62), samenvoegen in een andere eenheid, eenheid wisselen
/// rekent om (N43), en na het bewerken van een recept een verse portie (N59).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  AppState newState() => AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  const skyr = Food(
    ref: 'custom:skyr-test',
    name: 'Skyr',
    source: FoodSource.custom,
    per100g: {'energy': 60, 'protein': 11},
    portions: [Portion('1 bowl', 150)],
  );

  /// Een gewoon scherm met een knop die het productscherm opent, zoals het dagboek.
  Future<void> pump(WidgetTester tester, AppState s, Widget Function() screen) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<Object>(builder: (_) => screen())),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester) async {
    await tester.tap(find.textContaining('Add to breakfast'));
    await tester.pumpAndSettle();
  }

  testWidgets('toevoegen geeft een melding; nog eens bijtellen zegt hoeveel het nu is, Ongedaan maken neemt alleen de laatste terug', (
    tester,
  ) async {
    final s = newState();
    await pump(tester, s, () => const FoodDetailScreen(food: skyr, meal: Meal.breakfast));
    await add(tester);
    expect(find.text('Skyr (1 bowl) added to breakfast'), findsOneWidget);
    expect(s.entries.single.quantity, 1);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await add(tester);
    expect(find.text('Skyr: 1 bowl added to breakfast (now 2)'), findsOneWidget);
    expect(s.entries.single.quantity, 2);

    // Een tik in de eerste halve seconde telt niet (dubbeltik-bescherming)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.entries.single.quantity, 1);
    expect(s.entries.single.grams, 150);
  });

  testWidgets('zelfde product in een andere eenheid: één regel in gram, en Ongedaan maken zet de oude regel terug', (tester) async {
    final s = newState();
    s.addFood(skyr, meal: Meal.breakfast, grams: 250, quantity: 250);
    await pump(tester, s, () => const FoodDetailScreen(food: skyr, meal: Meal.breakfast));
    await add(tester);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.grams, 400);
    expect(s.entries.single.quantity, 400);
    expect(s.entries.single.portionLabel, isNull);
    expect(find.text('Skyr: 1 bowl added to breakfast (now 400 g in one line)'), findsOneWidget);

    // Een tik in de eerste halve seconde telt niet (dubbeltik-bescherming)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.entries.single.grams, 250);
  });

  testWidgets('naar gram wisselen rekent de hoeveelheid om', (tester) async {
    final s = newState();
    await pump(tester, s, () => const FoodDetailScreen(food: skyr, meal: Meal.breakfast));
    // Per 1 portie (N32): 1 → 2 kommen
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('= 300 g'), findsOneWidget);
    await tester.tap(find.text('Grams'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '300'), findsOneWidget);
  });

  testWidgets('recept bewerken: daarna 1 verse portie, en 0 porties wordt geweigerd', (tester) async {
    final s = newState();
    final recipe = Recipe(
      ref: 'recipe:test',
      name: 'Dal',
      servings: 4,
      ingredients: const [ItemTemplate(foodRef: 'custom:lentils', name: 'Lentils', grams: 1200, quantity: 1200, per100g: {'energy': 100})],
    );
    s.saveRecipe(recipe);
    await pump(tester, s, () => FoodDetailScreen(food: recipe.toFood(), meal: Meal.breakfast));
    expect(find.text('= 300 g'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit recipe'));
    await tester.pumpAndSettle();
    final servings = find.widgetWithText(TextField, 'Number of servings');
    await tester.enterText(servings, '0');
    await tester.pump();
    expect(find.text('At least 1 portion'), findsOneWidget);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Save recipe'), findsOneWidget, reason: 'met 0 porties blijft het recept open');

    await tester.enterText(servings, '6');
    await tester.pump();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Save recipe'), findsNothing);
    expect(find.text('× 1 serving (1/6 of the recipe)'), findsOneWidget);
    expect(find.text('= 200 g'), findsOneWidget);
  });

  testWidgets('recept: absurd gewicht na bereiding geweigerd, ongewoon gewicht eerst gevraagd', (tester) async {
    final s = newState();
    final recipe = Recipe(
      ref: 'recipe:test2',
      name: 'Soup',
      servings: 4,
      ingredients: const [ItemTemplate(foodRef: 'custom:veg', name: 'Vegetables', grams: 690, quantity: 690, per100g: {'energy': 40})],
    );
    s.saveRecipe(recipe);
    await pump(tester, s, () => FoodDetailScreen(food: recipe.toFood(), meal: Meal.breakfast));
    await tester.tap(find.byTooltip('Edit recipe'));
    await tester.pumpAndSettle();
    final cooked = find.widgetWithText(TextField, 'Weight after cooking');
    await tester.enterText(cooked, '99999');
    await tester.pump();
    expect(find.textContaining('At most'), findsOneWidget);

    await tester.enterText(cooked, '2500');
    await tester.pump();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Is this right?'), findsOneWidget);
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    expect(find.text('Save recipe'), findsOneWidget);
  });
}
