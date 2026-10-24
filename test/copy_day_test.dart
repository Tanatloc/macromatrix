import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// N58: een hele dag kopiëren, van elke eerdere dag en naar morgen of een andere dag.
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

  DateTime plus(int days) => DateTime(s.date.year, s.date.month, s.date.day + days);
  List<DiaryEntry> on(DateTime d) => s.user.entriesBetween(dayKey(d), dayKey(d));

  Widget app() => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(onPressed: () => openDayMenu(context), child: const Text('menu')),
              TextButton(onPressed: () => pickDayToCopyFrom(context), child: const Text('from')),
            ],
          ),
        ),
      ),
    ),
  );

  group('AppState.copyDay', () {
    test('van een eerdere dag: samenvoegen en ongedaan maken', () {
      final oats = foods.search('oats', limit: 1).first;
      final banana = foods.search('banana', limit: 1).first;
      s.shiftDay(-3);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
      s.addFood(banana, meal: Meal.dinner, grams: 120, quantity: 120);
      s.shiftDay(3);
      s.addFood(oats, meal: Meal.breakfast, grams: 50, quantity: 50);

      final added = s.copyDay(from: plus(-3));
      expect(added, hasLength(2));
      expect(s.entries, hasLength(2));
      expect(s.entriesFor(Meal.breakfast).single.grams, 130);

      s.undoAdds(added);
      expect(s.entries, hasLength(1));
      expect(s.entriesFor(Meal.breakfast).single.grams, 50);
    });

    test('naar morgen: de gekozen dag blijft ongewijzigd, ongedaan maken haalt het weer weg', () {
      final oats = foods.search('oats', limit: 1).first;
      s.addFood(oats, meal: Meal.lunch, grams: 60, quantity: 60);
      final added = s.copyDay(from: s.date, to: plus(1));
      expect(added, hasLength(1));
      expect(s.entries, hasLength(1));
      expect(on(plus(1)).single.meal, Meal.lunch);

      // Nog eens: wordt samengevoegd tot één regel
      final again = s.copyDay(from: s.date, to: plus(1));
      expect(on(plus(1)).single.grams, 120);
      s.undoAdds(again);
      s.undoAdds(added);
      expect(on(plus(1)), isEmpty);
    });

    test('dezelfde dag naar zichzelf doet niets', () {
      s.addFood(foods.search('oats', limit: 1).first, meal: Meal.lunch, grams: 60, quantity: 60);
      expect(s.copyDay(from: s.date), isEmpty);
      expect(s.entries, hasLength(1));
    });
  });

  group('dagmenu', () {
    testWidgets('kopieer deze dag naar morgen, met melding en ongedaan maken', (tester) async {
      s.addFood(foods.search('oats', limit: 1).first, meal: Meal.breakfast, grams: 80, quantity: 80);
      await tester.pumpWidget(app());
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.text('Copy day from…'), findsOneWidget);
      await tester.tap(find.text('Copy this day to tomorrow'));
      await tester.pumpAndSettle();
      expect(on(plus(1)), hasLength(1));
      expect(find.text('Copied 1 item to tomorrow'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(on(plus(1)), isEmpty);
    });

    testWidgets('vraagt eerst als morgen al iets bevat', (tester) async {
      final oats = foods.search('oats', limit: 1).first;
      s.shiftDay(1);
      s.addFood(oats, meal: Meal.dinner, grams: 40, quantity: 40);
      s.shiftDay(-1);
      s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
      await tester.pumpWidget(app());
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy this day to tomorrow'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow already has 1 item'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(on(plus(1)), hasLength(1));
    });

    testWidgets('lege dag: alleen "Kopieer dag van…", zonder eerdere dagen een melding', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.text('Copy this day to tomorrow'), findsNothing);
      expect(find.text('Copy this day to…'), findsNothing);
      await tester.tap(find.text('Copy day from…'));
      await tester.pumpAndSettle();
      expect(find.text('No earlier day has items yet.'), findsOneWidget);
    });

    testWidgets('kopieer dag van: kalender opent op de laatste dag met items, melding noemt de dag', (tester) async {
      s.shiftDay(-4);
      s.addFood(foods.search('oats', limit: 1).first, meal: Meal.breakfast, grams: 80, quantity: 80);
      s.shiftDay(4);
      await tester.pumpWidget(app());
      await tester.tap(find.text('from'));
      await tester.pumpAndSettle();
      expect(find.text('Copy day from'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(s.entries, hasLength(1));
      final label = DateFormat(plus(-4).year == s.date.year ? 'EEE d MMM' : 'EEE d MMM yyyy', appLocale).format(plus(-4));
      expect(find.text('Copied 1 item from $label'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  });
}
