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

    // Profiel in de zijbalk brengt je terug naar het beginscherm van Profiel (P103)
    await tester.tap(find.text('Profiel'));
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsNothing);
  });

  testWidgets('venster smaller en weer breder maken: een open scherm in een tabblad blijft staan', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    await tester.tap(find.text('Instellingen'));
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsOneWidget);

    // Gsm-breedte: het scherm staat er nog, over de balk onderaan heen
    tester.view.physicalSize = const Size(412, 915);
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsOneWidget);
    expect(find.text('SNEL NAAR'), findsNothing);
    expect(find.byTooltip('Toevoegen').hitTestable(), findsNothing);

    // Terug naar een pc: nog altijd open, naast de zijbalk
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsOneWidget);
    expect(find.text('SNEL NAAR'), findsOneWidget);

    // Op een gsm sluit de terugknop van het toestel eerst dat scherm, en toont dan weer de balk onderaan
    tester.view.physicalSize = const Size(412, 915);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe dag begint om'), findsNothing);
    expect(find.byTooltip('Toevoegen').hitTestable(), findsOneWidget);
    // De korte tikbescherming na het sluiten (tap_guard) duurt langer dan de snelle overgang: laten aflopen
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('smal venster: het toevoegmenu is niet uitgerekt en de derde rij is bereikbaar', (tester) async {
    await pumpShell(tester, const Size(780, 700));
    await tester.tap(find.byTooltip('Toevoegen'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GridView)).width, lessThanOrEqualTo(560));
    final check = find.text('Product checken');
    expect(tester.getRect(check).bottom, lessThanOrEqualTo(700));
    expect(check.hitTestable(), findsOneWidget);
  });

  testWidgets('gsm: navigatie onderaan met een + in het midden die het toevoegmenu opent', (tester) async {
    await pumpShell(tester, const Size(412, 915));
    expect(find.text('SNEL NAAR'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
    await tester.tap(find.byTooltip('Toevoegen'));
    await tester.pumpAndSettle();
    expect(find.text('Eten toevoegen'), findsOneWidget);
    expect(find.text('Barcode scannen'), findsOneWidget);
    expect(find.text('Product checken'), findsOneWidget);
  });

  testWidgets('tablet: rail links en Toevoegen in de kop (geen zwevende knop over de kcal, N81)', (tester) async {
    await pumpShell(tester, const Size(900, 1000));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Toevoegen'), findsOneWidget);
  });
}
