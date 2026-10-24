import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/allergens.dart';
import 'package:macromatrix/nutrition/processing.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/screens/nutrients_screen.dart';
import 'package:macromatrix/ui/shell.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/allergen_banner.dart';
import 'package:macromatrix/ui/widgets/processing_card.dart';
import 'package:macromatrix/ui/widgets/undo.dart';

/// Kleine bevindingen uit de gebruikerstest van v1.11 (N34, N39, N42, N56, N91).
void main() {
  late FoodDb foods;
  late AppState s;

  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  setUp(() {
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });

  Widget app(Widget child) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('N56: 0% ultrabewerkt maar veel bewerkt is geen "vooral echt eten"', (tester) async {
    final share = ProcessingShare({Nova.unprocessed: 260, Nova.processed: 740}, 0);
    await tester.pumpWidget(app(ProcessingCard(share: share)));
    expect(find.textContaining('Mostly real food'), findsNothing);
    expect(find.textContaining('No ultra-processed food. Great!'), findsOneWidget);
  });

  testWidgets('N34: (i) bij de Voedingsscore en bij NOVA opent een uitleg', (tester) async {
    await tester.pumpWidget(app(const Column(children: [ScoreCard()])));
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('vitamins and minerals'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final share = ProcessingShare({Nova.unprocessed: 500, Nova.ultra: 500}, 0);
    await tester.pumpWidget(app(ProcessingCard(share: share)));
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 Ultra-processed'), findsOneWidget);
  });

  testWidgets('N39: een tik op het vlammetje legt de reeks uit, zonder uitroepteken', (tester) async {
    final oats = foods.search('oats', limit: 1).first;
    s.shiftDay(-2);
    s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
    s.shiftDay(1);
    s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
    s.shiftDay(1);
    await tester.pumpWidget(app(const StreakFlame()));
    expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
    await tester.tap(find.byType(StreakFlame));
    await tester.pumpAndSettle();
    expect(find.text('Your streak'), findsOneWidget);
    expect(find.textContaining('2 days in a row'), findsOneWidget);
  });

  testWidgets('N91: een gok op naam is oranje, geen rode foutstijl', (tester) async {
    s.setAllergies({Allergen.milk});
    const yogurt = Food(ref: 'test:yogurt', name: 'Greek yogurt', source: FoodSource.off, per100g: {});
    await tester.pumpWidget(app(const AllergenBanner(food: yogurt)));
    final box = tester.widget<Container>(find.descendant(of: find.byType(AllergenBanner), matching: find.byType(Container)).first);
    final color = (box.decoration! as BoxDecoration).color;
    expect(color, Palette.light.lowSoft);
    expect(color, isNot(Palette.light.high));

    // Zonder ingestelde allergie geen melding
    s.setAllergies({});
    await tester.pumpWidget(app(const AllergenBanner(food: yogurt)));
    expect(find.textContaining('milk'), findsNothing);
  });

  testWidgets('N42: de melding met Ongedaan maken verdwijnt na 7 s', (tester) async {
    await tester.pumpWidget(app(Builder(builder: (c) => TextButton(onPressed: () => showUndo(c, 'Removed', () {}), child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsNothing);
  });

  testWidgets('N42: een ander tabblad sluit de melding, een nieuw scherm ook', (tester) async {
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider.value(value: account),
          Provider.value(value: Reminders(s)),
          ChangeNotifierProvider(create: (_) => Friends(s, account)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Shell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final ctx = tester.element(find.byType(Shell));

    showUndo(ctx, 'Measurement removed', () {});
    await tester.pumpAndSettle();
    expect(find.text('Measurement removed'), findsOneWidget);
    await tester.tap(find.text('Dashboard').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Measurement removed'), findsNothing);

    showUndo(ctx, 'Measurement removed', () {});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplements').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Measurement removed'), findsNothing);
  });
}
