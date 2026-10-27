import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/shell.dart';
import 'package:macromatrix/ui/theme.dart';

/// Vandaag: "Laatste 7 dagen" naar Week (N16), opgeslagen maaltijd via de kaart (N20), + bij een lege maaltijd
/// (N27) en de volgorde op 1024 × 700 (N31).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  AppState newState() => AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  void logBanana(AppState s, Meal meal) {
    final banana = s.foods.search('banana', limit: 1).first;
    s.addFood(banana, meal: meal, grams: 120, quantity: 120);
  }

  Future<AppState> pumpShell(WidgetTester tester, Size size, {void Function(AppState s)? setup}) async {
    final state = newState();
    setup?.call(state);
    final account = Account(state.user, onRemoteChanges: state.reloadFromDisk);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: account),
          Provider.value(value: Reminders(state)),
          ChangeNotifierProvider(create: (_) => Friends(state, account)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Shell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    return state;
  }

  Future<AppState> pumpDiary(WidgetTester tester, {void Function(AppState s)? setup, Size size = const Size(412, 3000)}) async {
    final s = newState();
    setup?.call(s);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const DiaryScreen()),
      ),
    );
    await tester.pump();
    return s;
  }

  group('N16 Laatste 7 dagen', () {
    testWidgets('gsm: opent het tabblad Dashboard op Week, met de menubalk', (tester) async {
      // Hoog genoeg dat de kaart zonder scrollen in beeld staat
      await pumpShell(tester, const Size(412, 2400), setup: (s) => logBanana(s, Meal.breakfast));
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      // Week: het weekrapport staat er, en de balk onderaan blijft zichtbaar
      expect(find.text('Weekly report'), findsOneWidget);
      expect(find.textContaining(RegExp('this week', caseSensitive: false)), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      // Via Vandaag in de balk terug
      await tester.tap(find.text('Today').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
    });

    testWidgets('los dagboek: eigen scherm op Week met een terugpijl', (tester) async {
      await pumpDiary(tester, setup: (s) => logBanana(s, Meal.breakfast));
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      expect(find.text('Weekly report'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Weekly report'), findsNothing);
    });
  });

  group('N20 opgeslagen maaltijd', () {
    test('aan elkaar geplakte naam wordt gesplitst', () {
      expect(savedMealName('BreakfastWeekday porridge'), 'Weekday porridge');
      expect(savedMealName('OntbijtHavermout met melk'), 'Havermout met melk');
      expect(savedMealName('SnackShake na training'), 'Shake na training');
      expect(savedMealName('Lunch box'), 'Lunch box');
      expect(savedMealName('Breakfast'), 'Breakfast');
      expect(mealInName('DinnerChicken stir fry'), Meal.dinner);
      expect(mealInName('Lunchroomsalade'), isNull);
      const glued = SavedMeal(id: 'a', name: 'DinnerChicken stir fry', items: []);
      expect(savedMealTarget(glued, Meal.breakfast), Meal.dinner);
      expect(savedMealTitle(glued, Meal.dinner), 'Dinner · Chicken stir fry');
      expect(savedMealTitle(const SavedMeal(id: 'b', name: 'Breakfast', items: []), Meal.breakfast), 'Breakfast');
    });

  });

  testWidgets('N27 tik op het midden van + bij een lege maaltijd opent niet het …-menu', (tester) async {
    await pumpDiary(tester);
    final plus = find.descendant(of: find.byTooltip('Add to lunch'), matching: find.byIcon(Icons.add_rounded));
    final more = find.descendant(
      of: find.ancestor(of: plus, matching: find.byType(Row)).first,
      matching: find.byTooltip('More'),
    );
    // Eigen knoppen van minstens 44 × 44, met ruimte ertussen
    final addBox = tester.getRect(find.byTooltip('Add to lunch'));
    final moreBox = tester.getRect(more);
    expect(addBox.width, greaterThanOrEqualTo(44));
    expect(addBox.height, greaterThanOrEqualTo(44));
    expect(moreBox.left - addBox.right, greaterThanOrEqualTo(8));
    // Elke plek in de +-knop raakt de + en niet het menu
    for (final dx in [0.5, addBox.width / 2, addBox.width - 0.5]) {
      final hits = tester.hitTestOnBinding(Offset(addBox.left + dx, addBox.center.dy));
      final targets = hits.path.map((e) => e.target).whereType<RenderObject>().toSet();
      final moreRender = tester.renderObject(more);
      expect(targets.contains(moreRender), isFalse, reason: 'dx $dx');
    }
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.text('Copy from yesterday'), findsNothing);
  });

  testWidgets('N31 op 1024 × 700 staan de maaltijden boven de inzichten', (tester) async {
    await pumpShell(tester, const Size(1024, 700), setup: (s) => logBanana(s, Meal.breakfast));
    final meals = tester.getTopLeft(find.text('Meals')).dy;
    final week = tester.getTopLeft(find.text('Last 7 days')).dy;
    expect(meals, lessThan(week));
    // De samenvatting (energiering) blijft wel bovenaan
    expect(find.text('Lunch'), findsWidgets);
  });
}
