import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/recap_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Het maandoverzicht bouwt met echte gegevens, als maand en als jaar, op gsm en desktop.
void main() {
  setUpAll(() async => initializeDateFormatting(appLocale));

  testWidgets('maand- en jaaroverzicht bouwen met kalender, energie, macro\'s en top 5', (tester) async {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    final now = logicalNow();
    final apple = foods.search('apple', limit: 1).first, bread = foods.search('bread', limit: 1).first;
    for (var i = 0; i < 6; i++) {
      s.setDate(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
      s.addFood(apple, meal: Meal.breakfast, grams: 150, quantity: 1);
      if (i.isEven) s.addFood(bread, meal: Meal.lunch, grams: 70, quantity: 1);
    }
    for (final (w, year) in [(390.0, false), (1366.0, false), (390.0, true)]) {
      tester.view.physicalSize = Size(w, 2400);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: s,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: RecapScreen(from: year ? DateTime(now.year) : DateTime(now.year, now.month), year: year),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(year ? 'Month by month' : 'Day by day'), findsOneWidget);
      expect(find.text('Your top 5'), findsOneWidget);
    }
    addTearDown(tester.view.reset);
  });
}
