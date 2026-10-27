import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/ui/screens/add_food_screen.dart';
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/screens/scan_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

/// Testronde 11: registreren en inloggen, de eerste stap, de scanner, de standaardmaaltijd rond middernacht, de
/// kalender en loggen met een foto.
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() {
    appClock = DateTime.now;
    dayStartHour = 3;
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));

  Future<(AppState, Account)> pump(WidgetTester tester, Widget home, {Size size = const Size(420, 1400)}) async {
    final user = UserDb(sqlite3.openInMemory());
    final state = AppState(foods: foods, user: user);
    final account = Account(user, onRemoteChanges: state.reloadFromDisk);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: account),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ),
    );
    await tester.pump();
    return (state, account);
  }

  /// Een knop die [open] oproept met een context onder de providers.
  Widget opener(Future<void> Function(BuildContext context) open) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')),
    ),
  );

  group('standaardmaaltijd rond middernacht (NW-20)', () {
    test('vóór het begin van de dag is het een tussendoortje, geen ontbijt', () {
      dayStartHour = 3;
      expect(Meal.forHour(0), Meal.snacks);
      expect(Meal.forHour(2), Meal.snacks);
      expect(Meal.forHour(3), Meal.breakfast);
      expect(Meal.forHour(12), Meal.lunch);
      expect(Meal.forHour(22), Meal.snacks);
      dayStartHour = 0;
      expect(Meal.forHour(0), Meal.breakfast);
    });

    test('Snel loggen en Eten toevoegen om 00:48: de app-dag is nog zaterdag, dus Snack', () {
      appClock = () => DateTime(2026, 10, 25, 0, 48);
      final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
      expect(s.date, DateTime(2026, 10, 24));
      expect(s.isToday, isTrue);
      expect(s.suggestedMeal, Meal.snacks);
      appClock = () => DateTime(2026, 10, 25, 8);
      expect(s.suggestedMeal, Meal.breakfast);
    });
  });

  group('kalender: "vandaag" is de dag van de app (SU-13)', () {
    for (final (name, open) in [('naar een dag springen', pickDay), ('deze dag kopiëren naar', pickDayToCopyTo)]) {
      testWidgets(name, (tester) async {
        appClock = () => DateTime(2026, 10, 25, 0, 40);
        await pump(tester, opener(open));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
        expect(dialog.currentDate, DateTime(2026, 10, 24));
      });
    }
  });

  group('thema (NW-8, NW-16)', () {
    test('standaard licht, tot je zelf kiest', () {
      final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
      expect(s.themeMode, 'light');
      s.setThemeMode('system');
      expect(s.themeMode, 'system');
    });

    testWidgets('de eerste stap zegt "Last step"; het thema is licht zonder vraag', (tester) async {
      final (s, _) = await pump(tester, const ProfileSetupScreen());
      expect(find.text('Step 2 of 2'.toUpperCase()), findsNothing);
      expect(find.textContaining(RegExp('last step', caseSensitive: false)), findsOneWidget);
      // Geen themakeuze meer in de eerste stap (eerste-maaltijdmeting 25-10): in Instellingen → Weergave
      expect(find.byWidgetPredicate((w) => w is Segmented<String>), findsNothing);
      expect(s.themeMode, 'light');
    });
  });

  group('scanner zonder camera (NW-14, NW-19)', () {
    setUp(() => scanCameras = () async => throw CameraException('none', 'No camera'));
    tearDown(() => scanCameras = availableCameras);

    testWidgets('melding, opnieuw proberen en het nummer zelf typen', (tester) async {
      String? result = 'nog niets';
      await pump(
        tester,
        opener((context) async => result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Geen camera in een test: dezelfde uitweg als in een browser zonder camera
      expect(find.byKey(const ValueKey('scan-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scan-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-error')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('scan-typed')), '12345');
      await tester.tap(find.byKey(const ValueKey('scan-typed-go')));
      await tester.pump();
      expect(find.textContaining('That is not a barcode'), findsOneWidget);
      expect(result, 'nog niets');

      await tester.enterText(find.byKey(const ValueKey('scan-typed')), '5400141 367867');
      await tester.pump();
      expect(find.textContaining('That is not a barcode'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('scan-typed-go')));
      await tester.pumpAndSettle();
      expect(result, '5400141367867');
      expect(find.byType(ScanScreen), findsNothing);
    });

    testWidgets('terug uit de scanner (vanuit het +-menu) is terug naar waar je was, niet het zoekscherm', (tester) async {
      await pump(tester, opener((context) => scanBarcodeFor(context, Meal.breakfast)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ScanScreen), findsNothing);
      expect(find.byType(AddFoodScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('account aanmaken (NW-4, NW-5, NW-6)', () {
    Finder field(String label) => find.widgetWithText(TextField, label);
    String? errorOf(WidgetTester tester, String label) => tester.widget<TextField>(field(label)).decoration?.errorText;

    testWidgets('fout bij het veld zelf, het formulier verspringt niet, en de melding gaat weg als je het aanpast', (tester) async {
      await pump(tester, const AuthScreen(register: true), size: const Size(420, 900));
      final before = tester.getTopLeft(field('Email address'));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(errorOf(tester, 'Email address'), 'Enter a valid email address.');
      expect(tester.getTopLeft(field('Email address')), before, reason: 'bovenaan, niet gecentreerd');

      await tester.enterText(field('Email address'), 'nieuw@example.com');
      await tester.pump();
      expect(errorOf(tester, 'Email address'), isNull);

      await tester.enterText(field('Password'), 'geheim123');
      await tester.enterText(field('Repeat the password'), 'geheim124');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(errorOf(tester, 'Repeat the password'), 'The two passwords do not match.');
      await tester.enterText(field('Repeat the password'), 'geheim123');
      await tester.pump();
      expect(errorOf(tester, 'Repeat the password'), isNull);

      // Het vakje: rood gemarkeerd met de melding eronder, weg zodra je het aanvinkt
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.byKey(const ValueKey('terms-error')), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).isError, isTrue);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.byKey(const ValueKey('terms-error')), findsNothing);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).isError, isFalse);
    });

    testWidgets('een registratie die op de code wacht: het welkomscherm biedt aan ze af te maken', (tester) async {
      final (_, account) = await pump(tester, const WelcomeScreen());
      expect(find.byKey(const ValueKey('pending-confirm')), findsNothing);
      account.setPendingConfirmation('nieuw@example.com');
      await tester.pump();
      expect(find.byKey(const ValueKey('pending-confirm')), findsOneWidget);
      expect(find.textContaining('nieuw@example.com'), findsOneWidget);

      await tester.tap(find.text('Confirm your account'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your email address'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Code from the email'), findsOneWidget);
      expect(find.textContaining('we sent to nieuw@example.com'), findsOneWidget);

      // Ander adres: de wachtende bevestiging vervalt en je staat in het formulier
      await tester.tap(find.text('Different email address'));
      await tester.pumpAndSettle();
      expect(account.pendingConfirmation, isNull);
      expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
    });

    testWidgets('terug op het codescherm: het formulier met alles nog ingevuld, en het welkomscherm onthoudt het', (tester) async {
      final user = UserDb(sqlite3.openInMemory());
      final state = AppState(foods: foods, user: user);
      final account = _SignUpOk(user);
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<Account>.value(value: account),
          ],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const WelcomeScreen()),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email address'), 'nieuw@example.com');
      await tester.enterText(field('Password'), 'geheim123');
      await tester.enterText(field('Repeat the password'), 'geheim123');
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your email address'), findsOneWidget);
      expect(account.pendingConfirmation, 'nieuw@example.com');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
      expect(tester.widget<TextField>(field('Email address')).controller!.text, 'nieuw@example.com');
      expect(tester.widget<TextField>(field('Password')).controller!.text, 'geheim123');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending-confirm')), findsOneWidget);
    });

    test('een wachtende bevestiging vervalt na een week', () {
      final db = UserDb(sqlite3.openInMemory());
      final a = Account(db, onRemoteChanges: () {});
      a.setPendingConfirmation(' nieuw@example.com ');
      expect(a.pendingConfirmation, 'nieuw@example.com');
      db.setSetting('_pending_confirm', {
        'email': 'nieuw@example.com',
        'at': DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch,
      });
      expect(a.pendingConfirmation, isNull);
    });
  });

  group('loggen met een foto: de bereiding en de soort tellen (SU-5)', () {
    late final AppState s;
    setUpAll(() => s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory())));
    String first(String q) => s.resolveQuick(QuickItem(q)).first.$1.name.toLowerCase();

    test('"fried ham" is ham, geen gebakken champignons of rundvlees', () {
      expect(first('fried ham'), matches(RegExp(r'\bham\b')));
      expect(first('fried ham'), isNot(contains('raw')));
    });

    test('"ham" op je bord is bereide ham, geen rauwe hamlap; rauw alleen als je het zegt', () {
      expect(first('ham'), matches(RegExp(r'\bham\b')));
      expect(first('ham'), isNot(contains('raw')));
      expect(first('raw ham'), contains('raw'));
    });

    test('"balsamic glaze" is balsamico, geen taartglazuur', () {
      expect(first('balsamic glaze'), contains('balsamic'));
      expect(first('balsamic glaze'), isNot(contains('frosting')));
      // Alleen "glaze" mag wel glazuur blijven
      expect(first('glaze'), contains('glaze'));
    });

    test('de bereiding die het model noemt, blijft staan', () {
      expect(first('scrambled eggs'), contains('scrambled'));
      expect(first('fried egg'), contains('fried'));
      expect(first('wholemeal bread'), contains('wholemeal'));
      expect(first('rye bread'), contains('rye'));
      expect(first('caesar dressing'), contains('caesar'));
    });
  });
}

/// Registreren lukt meteen (zonder Supabase): Supabase stuurt dan een code.
class _SignUpOk extends Account {
  _SignUpOk(super.db) : super(onRemoteChanges: () {});

  @override
  Future<bool> signUp(String email, String password) async => true;
}
