import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/add_food_screen.dart';
import 'package:macromatrix/ui/screens/body_screen.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/tap_guard.dart';

/// Bevindingen van gebruikerstest ronde 8 en 9: N03, N04, N12, N14, N46, N57.
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
  tearDown(() => setAppLang(AppLang.en));

  Widget app(Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  group('N57 kopieer van gisteren', () {
    test('gelijke producten worden samengevoegd, ongedaan maken zet alles terug', () {
      final oats = foods.search('oats', limit: 1).first;
      final banana = foods.search('banana', limit: 1).first;
      s.shiftDay(-1);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
      s.addFood(banana, meal: Meal.breakfast, grams: 120, quantity: 120);
      s.shiftDay(1);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);

      final added = s.copyMealFromYesterday(Meal.breakfast);
      expect(added, hasLength(2));
      expect(s.entriesFor(Meal.breakfast), hasLength(2));
      expect(s.entriesFor(Meal.breakfast).firstWhere((e) => e.foodRef == oats.ref).grams, 160);

      s.undoAdds(added);
      expect(s.entriesFor(Meal.breakfast), hasLength(1));
      expect(s.entriesFor(Meal.breakfast).single.grams, 80);
    });

    test('hele dag: elke maaltijd, met ongedaan maken', () {
      final oats = foods.search('oats', limit: 1).first;
      s.shiftDay(-1);
      s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
      s.addFood(oats, meal: Meal.dinner, grams: 50, quantity: 50);
      s.shiftDay(1);
      final added = s.copyDayFromYesterday();
      expect(added, hasLength(2));
      expect(s.entries, hasLength(2));
      s.undoAdds(added);
      expect(s.entries, isEmpty);
    });

    testWidgets('vraagt eerst als de maaltijd al iets bevat', (tester) async {
      final oats = foods.search('oats', limit: 1).first;
      s.shiftDay(-1);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
      s.shiftDay(1);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => copyFromYesterday(context, meal: Meal.breakfast),
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('copy'));
      await tester.pumpAndSettle();
      expect(find.text('Add anyway'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.entriesFor(Meal.breakfast).single.grams, 80);

      await tester.tap(find.text('copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add anyway'));
      await tester.pump();
      expect(s.entriesFor(Meal.breakfast).single.grams, 160);
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(s.entriesFor(Meal.breakfast).single.grams, 80);
      // De melding verdwijnt vanzelf na 4-5 s
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('N12 Orakel', () {
    test('eiwit in groenten en noten met alleen gewone producten: nooit leeg, geen gedroogd zeewier', () {
      for (final g in ['vegetable', 'nut/seed', 'dairy']) {
        final relaxed = <String>{};
        final r = s.oracle('protein', groups: {g}, limit: 25, everyday: true, relaxed: relaxed);
        expect(r, hasLength(25), reason: g);
        expect(r.every((x) => x.$1.label?.group == g), isTrue);
        expect(r.any((x) => RegExp('spirulina|seaweed|nori|laver', caseSensitive: false).hasMatch(x.$1.name)), isFalse, reason: g);
        expect(relaxed, isEmpty);
      }
    });

    test('een groep zonder gewone producten valt terug op alle producten, met melding', () {
      final relaxed = <String>{};
      final r = s.oracle('protein', groups: {'processed meat'}, limit: 10, everyday: true, relaxed: relaxed);
      expect(r, isNotEmpty);
      expect(relaxed, {'processed meat'});
    });
  });

  testWidgets('N03 sluiten van een scherm in een geneste navigator blokkeert tikken ~320 ms', (tester) async {
    final guard = TapGuard();
    final nested = guard.observer();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => guard.wrap(child),
        home: Navigator(
          key: nav,
          observers: [nested],
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Scaffold(body: Text('root'))),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(guard.blocked.value, isFalse);
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('detail'))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    nav.currentState!.pop();
    await tester.pump();
    expect(guard.blocked.value, isTrue);
    await tester.pump(const Duration(milliseconds: 280));
    expect(guard.blocked.value, isTrue);
    await tester.pump(const Duration(milliseconds: 60));
    expect(guard.blocked.value, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('N04 dubbele tik op × wist één meting; ongedaan maken zet alle recente terug', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s.addBiometric('weight', 80);
    s.addBiometric('waist', 90);
    await tester.pumpWidget(app(const BodyScreen()));
    await tester.pump();
    expect(s.biometrics, hasLength(2));
    final close = find.byIcon(Icons.close);
    await tester.tap(close.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(close.first);
    await tester.pump();
    expect(s.biometrics, hasLength(1));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(s.biometrics, isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 measurements removed'), findsOneWidget);
    // showUndo negeert een tik in de eerste halve seconde (echte tijd)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 550)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.biometrics, hasLength(2));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('N14 × in het zoekveld: veld leeg, focus blijft', (tester) async {
    await tester.pumpWidget(app(const AddFoodScreen(meal: Meal.lunch)));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'bread');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'apple');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'apple');
  });

  test('N46 kalender in de taal van de app, week vanaf maandag', () {
    expect(pickerLocale, const Locale('en', 'GB'));
    setAppLang(AppLang.nl);
    expect(pickerLocale, const Locale('nl', 'BE'));
  });
}
