import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/quick_log.dart';

/// Snel loggen: vanzelf zoeken, totaal, + en −, wisknop en "Klopt dit?" (N10, N65).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  Future<AppState> open(WidgetTester tester) async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    );
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuickLog(context, meal: Meal.breakfast),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return s;
  }

  testWidgets('leeg veld geeft een melding, typen zoekt vanzelf, + verhoogt het aantal', (tester) async {
    final s = await open(tester);
    await tester.tap(find.text('Find foods'));
    await tester.pump();
    expect(find.textContaining('Type or say what you ate first'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2 eggs');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Total'), findsOneWidget);
    expect(find.textContaining('110 g'), findsWidgets);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.textContaining('165 g'), findsWidgets);

    await tester.tap(find.text('Add 1 to breakfast'));
    await tester.pumpAndSettle();
    expect(s.entriesFor(Meal.breakfast).single.grams, 165);
  });

  testWidgets('wisknop maakt het veld leeg; 1000 bananen vraagt eerst', (tester) async {
    final s = await open(tester);
    await tester.enterText(find.byType(TextField), 'an apple');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.textContaining('Total'), findsNothing);

    await tester.enterText(find.byType(TextField), '1000 bananas');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.textContaining('Unusually large'), findsOneWidget);
    await tester.tap(find.text('Add 1 to breakfast'));
    await tester.pumpAndSettle();
    expect(find.text('Is this right?'), findsOneWidget);
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    expect(s.entriesFor(Meal.breakfast), isEmpty);
  });
}
