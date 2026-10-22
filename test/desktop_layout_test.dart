import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/shell.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    final user = UserDb(sqlite3.openInMemory());
    final state = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: user,
    );
    final account = Account(user, onRemoteChanges: state.reloadFromDisk);
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
  }

  testWidgets('pc: zijbalk met namen en snelkoppelingen, toevoegen bovenaan', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    expect(find.text('SNEL NAAR'), findsOneWidget);
    expect(find.text('Bloedwaarden'), findsOneWidget);
    expect(find.text('Eten toevoegen'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Een snelkoppeling opent binnen de inhoud: de zijbalk blijft staan
    await tester.tap(find.text('Instellingen'));
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsOneWidget);
    expect(find.text('SNEL NAAR'), findsOneWidget);
  });

  testWidgets('gsm: navigatie onderaan, zoals voorheen', (tester) async {
    await pumpShell(tester, const Size(412, 915));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('SNEL NAAR'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
