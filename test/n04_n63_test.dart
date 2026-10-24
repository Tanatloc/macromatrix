import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/screens/shopping_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// N04: dubbele tik op × in de boodschappenlijst wist één item. N63/N28: suiker van heel fruit kleurt "Effect op
/// vandaag" niet rood; met "Let op suiker" staat de suikerregel bovenaan.
void main() {
  late AppState s;
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  setUp(() => s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  ));

  Widget app(Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  testWidgets('N04 boodschappenlijst: dubbele tik wist één item, ongedaan maken zet het terug', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s.addShopping('apples');
    s.addShopping('bread');
    s.addShopping('milk');
    await tester.pumpWidget(app(const ShoppingScreen()));
    await tester.pump();
    final close = find.byIcon(Icons.close_rounded);
    await tester.tap(close.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    expect(s.shopping, hasLength(2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.shopping, hasLength(3));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  const apple = Food(
    ref: 'custom:apple-test',
    name: 'Apple, raw',
    source: FoodSource.custom,
    per100g: {'energy': 52, 'carbs': 14, 'sugars': 10.4, 'fiber': 2.4, 'vitamin_c': 4.6, 'potassium': 107},
    portions: [Portion('1 medium', 180)],
  );

  testWidgets('N63 appel met Let op suiker: geen rode suiker, wel uitleg bovenaan', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s.setSugarFocus(true);
    s.setOverride('sugars', const Target(upper: 30));
    // Al 28 g suiker uit frisdrank vandaag
    s.addFood(
      const Food(ref: 'custom:cola-test', name: 'Cola', source: FoodSource.custom, per100g: {'energy': 42, 'carbs': 10.6, 'sugars': 10.6}),
      meal: Meal.lunch,
      grams: 264,
      quantity: 264,
    );
    await tester.pumpWidget(app(const FoodDetailScreen(food: apple, meal: Meal.snacks)));
    await tester.pumpAndSettle();
    expect(find.text('Effect on today'), findsOneWidget);
    expect(find.text('Sugars (max)'), findsNothing);
    expect(find.text('Free sugars (max)'), findsOneWidget);
    expect(find.textContaining('is natural'), findsOneWidget);
  });
}
