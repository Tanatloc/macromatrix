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
import 'package:macromatrix/nutrition/portions.dart';
import 'package:macromatrix/nutrition/processing.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/custom_food_screen.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Gebruikerstest ronde 9: eigen product (N29, N72), recept (N75, N76) en bovengrenzen in "Effect op vandaag" (N70).
void main() {
  late AppState s;
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  setUp(
    () => s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    ),
  );

  Widget app(Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  /// Vanaf een gewoon scherm openen, zodat Opslaan kan terugkeren.
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<Object>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ItemTemplate item(String ref, double grams, {String? portion, double? quantity, Map<String, double> per100g = const {'energy': 350}}) =>
      ItemTemplate(foodRef: ref, name: ref, grams: grams, quantity: quantity ?? grams, portionLabel: portion, per100g: per100g);

  testWidgets('N29 suikers boven de koolhydraten: geweigerd, fout in beeld', (tester) async {
    size(tester, const Size(360, 740));
    await tester.pumpWidget(app(const CustomFoodScreen()));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Granola Honey Crunch');
    await tester.enterText(find.widgetWithText(TextFormField, 'Carbohydrates'), '57');
    await tester.enterText(find.widgetWithText(TextFormField, 'Sugars'), '70');
    await tester.enterText(find.widgetWithText(TextFormField, 'Fat'), '10');
    await tester.enterText(find.widgetWithText(TextFormField, 'Saturated fat'), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(s.user.customFoods(), isEmpty);
    final sugarError = find.text('At most the carbohydrates (57 g)');
    expect(sugarError, findsOneWidget);
    expect(find.text('At most the fat (10 g)'), findsOneWidget);
    // De bovenste fout staat volledig boven de knop Opslaan
    final save = tester.getTopLeft(find.widgetWithText(FilledButton, 'Save')).dy;
    expect(tester.getBottomLeft(find.text('At most the fat (10 g)')).dy, lessThan(save));
  });

  testWidgets('N72 eigen product: zelf gekozen NOVA en portie; lege macro is onbekend', (tester) async {
    size(tester, const Size(900, 1600));
    await open(tester, const CustomFoodScreen());
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Honey protein yoghurt');
    await tester.enterText(find.widgetWithText(TextFormField, 'Energy'), '85');
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight of one serving (optional)'), '150');
    await tester.enterText(find.widgetWithText(TextFormField, 'Serving name (optional)'), '1 pot');
    await tester.tap(find.text('Don\'t know'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ultra-processed').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = s.user.customFoods().single;
    expect(saved.nova, 4);
    expect(saved.portions.single.label, '1 pot');
    expect(saved.per100g.containsKey('protein'), isFalse);

    // Zonder keuze: geen groep en geen porties uit één woord in de naam
    final own = Food(ref: 'custom:honey', name: 'Honey protein yoghurt', source: FoodSource.custom, per100g: const {'energy': 85});
    expect(novaOf(own), isNull);
    expect(everydayPortions(own), isEmpty);

    await tester.pumpWidget(app(FoodDetailScreen(food: saved, meal: Meal.breakfast)));
    await tester.pumpAndSettle();
    expect(find.text('Ultra-processed (NOVA 4)'), findsOneWidget);
    expect(find.text('on a slice'), findsNothing);
    expect(find.text('unknown'), findsWidgets);
    expect(find.text('0 g'), findsNothing);
  });

  test('N76 gewicht na koken: het verschil is water', () {
    const lentils = <String, double>{'energy': 350, 'protein': 24, 'water': 10};
    final dal = Recipe(ref: 'recipe:dal', name: 'Dal', servings: 6, cookedGrams: 1200, ingredients: [item('lentils', 300, per100g: lentils)]);
    expect(dal.totals['water'], closeTo(30 + 900, 1e-9));
    expect(dal.toFood().per100g['water'], closeTo(930 / 12, 1e-9));
    // Inkoken: water eraf, nooit onder 0
    const sauce = <String, double>{'energy': 30, 'water': 90};
    final reduced = Recipe(ref: 'recipe:saus', name: 'Saus', servings: 2, cookedGrams: 600, ingredients: [item('tomato', 1000, per100g: sauce)]);
    expect(reduced.totals['water'], closeTo(900 - 400, 1e-9));
    // Zonder gewicht na koken verandert er niets
    final raw = Recipe(ref: 'recipe:raw', name: 'Raw', servings: 1, ingredients: [item('lentils', 300, per100g: lentils)]);
    expect(raw.totals['water'], closeTo(30, 1e-9));
  });

  test('N75 hetzelfde ingrediënt twee keer: één regel', () {
    final items = [item('lentils', 250), item('rice', 100)];
    expect(Recipe.addIngredient(items, item('lentils', 50)), 0);
    expect(items, hasLength(2));
    expect(items[0].grams, 300);
    expect(items[0].quantity, 300);
    // Dezelfde portie: porties optellen; een andere portie: in gram
    final eggs = [item('egg', 110, portion: '1 egg', quantity: 2)];
    Recipe.addIngredient(eggs, item('egg', 55, portion: '1 egg', quantity: 1));
    expect((eggs.single.quantity, eggs.single.portionLabel, eggs.single.grams), (3.0, '1 egg', 165.0));
    Recipe.addIngredient(eggs, item('egg', 20));
    expect((eggs.single.quantity, eggs.single.portionLabel, eggs.single.grams), (185.0, null, 185.0));
    // Ander product (of andere waarden): een nieuwe regel
    expect(Recipe.addIngredient(eggs, item('egg', 20, per100g: const {'energy': 140})), isNull);
    expect(eggs, hasLength(2));
  });

  testWidgets('N70 boven de veilige bovengrens: rood en met uitleg; gewone stoffen eerst', (tester) async {
    size(tester, const Size(900, 2400));
    const lentilDal = Food(
      ref: 'custom:dal-test',
      name: 'Lentil dal',
      source: FoodSource.custom,
      per100g: {'energy': 120, 'protein': 8, 'vit_c': 30, 'iron': 3, 'molybdenum': 700, 'phosphorus': 900},
    );
    await tester.pumpWidget(app(const FoodDetailScreen(food: lentilDal, meal: Meal.dinner)));
    await tester.pumpAndSettle();
    expect(find.text('Effect on today'), findsOneWidget);
    expect(find.text('Above the safe upper limit of 600 µg'), findsOneWidget);
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    // Vitamine C en ijzer vóór fosfor en molybdeen
    expect(y('Vitamin C'), lessThan(y('Phosphorus')));
    expect(y('Iron'), lessThan(y('Molybdenum')));
  });
}
