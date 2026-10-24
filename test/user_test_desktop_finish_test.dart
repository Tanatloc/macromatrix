import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/add_food_screen.dart';
import 'package:macromatrix/ui/screens/labs_screen.dart';
import 'package:macromatrix/ui/shell.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

/// Bevindingen N49, N50, N81, N82 en N93: afwerking op pc, middelgrote vensters, smalle schermen, zoeken en het
/// donkere thema.
void main() {
  late FoodDb foods;
  late AppState s;
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });
  setUp(() {
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    tester.view.physicalSize = size;
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
  }

  Widget app(Widget home, {TargetPlatform? platform, Brightness brightness = Brightness.light}) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(brightness).copyWith(platform: platform), home: home),
  );

  double offset(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((x) => x.position.axis == Axis.vertical)
      .map((x) => x.position.pixels)
      .fold(0.0, (a, b) => a > b ? a : b);

  group('N81 middelgroot venster', () {
    testWidgets('Toevoegen en kalender in de kop, geen zwevende knop over de kcal', (tester) async {
      await pumpShell(tester, const Size(900, 700));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Toevoegen'), findsOneWidget);
      expect(find.byTooltip('Kies een dag'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Ook op de smalste rail-breedte past de kop
      tester.view.physicalSize = const Size(800, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Meer in de rail opent de snelkoppelingen van de zijbalk', (tester) async {
      await pumpShell(tester, const Size(900, 700));
      await tester.tap(find.text('Meer'));
      await tester.pumpAndSettle();
      for (final t in ['Orakel', 'Lichaam', 'Bloedwaarden', 'Supplementen', 'Instellingen']) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.text('Instellingen'));
      await tester.pumpAndSettle();
      expect(find.text('Nieuwe dag begint om'), findsOneWidget);
      // Meer is nu gemarkeerd, niet Profiel
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 5);
    });

    testWidgets('andere indeling: geen oude scrollpositie van vroeger', (tester) async {
      await pumpShell(tester, const Size(700, 700));
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(offset(tester), greaterThan(300));
      // Breder (pc), daar terug naar boven, en weer smaller: Vandaag staat bovenaan, niet halverwege
      tester.view.physicalSize = const Size(1024, 700);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(offset(tester), 0);
      tester.view.physicalSize = const Size(700, 700);
      await tester.pumpAndSettle();
      expect(offset(tester), 0);
    });

    testWidgets('een uitlegballon verdwijnt als het venster van grootte verandert', (tester) async {
      await pumpShell(tester, const Size(900, 700));
      final kcal = find.byTooltip('Kies een dag');
      await tester.longPress(kcal);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Kies een dag'), findsOneWidget);
      tester.view.physicalSize = const Size(820, 700);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Kies een dag'), findsNothing);
    });
  });

  group('N50 bovenste kaart op een smal scherm', () {
    testWidgets('tabs met tekst, groot genoeg om te raken; de dag heeft plaats', (tester) async {
      // 340 in plaats van 320: het testlettertype is veel breder dan het echte, en dan loopt een lege maaltijdkaart
      // over, los van deze test
      await pumpShell(tester, const Size(340, 640));
      expect(tester.takeException(), isNull);
      for (final t in ['Doelen', 'Energie', 'Uitgelicht', 'Score']) {
        final tab = find.ancestor(of: find.text(t), matching: find.byType(InkWell)).first;
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(tab).width, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.text('Energie'));
      await tester.pumpAndSettle();
      expect(find.text('ENERGIEBALANS'), findsOneWidget);
      // Ruimte voor de dag tussen de pijlen: vroeger amper 36 px (de titel kromp tot ±13 px)
      final title = find.byWidgetPredicate((w) => w is Text && w.data == 'Vandaag' && w.style?.fontSize == 21);
      final box = find.ancestor(of: title, matching: find.byType(FittedBox)).first;
      expect(tester.getSize(box).width, greaterThanOrEqualTo(80));
    });
  });

  group('N49 pc zonder aanraakscherm', () {
    testWidgets('bloedwaarden: verwijderknop in plaats van veeg-tekst', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      s.saveLabs(
        DateTime(2026, 2, 3),
        parseLabReport([
          ['Fosfor', '-', '0,63', 'mmol/L', '0,810 - 1,450'],
        ]).values,
      );
      await tester.pumpWidget(app(const LabsScreen(), platform: TargetPlatform.linux));
      await tester.tap(find.text('Fosfor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Veeg een waarde'), findsNothing);
      await tester.tap(find.byTooltip('Verwijderen'));
      await tester.pumpAndSettle();
      expect(s.labResults, isEmpty);
      expect(find.text('Uitslag verwijderd'), findsOneWidget);
    });

    testWidgets('bloedwaarden op een gsm: vegen, met de uitleg', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      s.saveLabs(
        DateTime(2026, 2, 3),
        parseLabReport([
          ['Fosfor', '-', '0,63', 'mmol/L', '0,810 - 1,450'],
        ]).values,
      );
      await tester.pumpWidget(app(const LabsScreen(), platform: TargetPlatform.android));
      await tester.tap(find.text('Fosfor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Veeg een waarde'), findsOneWidget);
      expect(find.byTooltip('Verwijderen'), findsNothing);
    });

    testWidgets('eten toevoegen: het zoekveld heeft meteen de focus', (tester) async {
      await tester.pumpWidget(app(const AddFoodScreen(meal: Meal.lunch), platform: TargetPlatform.linux));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).first).focusNode!.hasFocus, isTrue);
    });
  });

  group('N82 zoekresultaten blijven op hun plaats', () {
    test('de gewone volgorde verandert niet na het loggen', () {
      final before = [for (final f in s.searchLocal('yoghurt', personal: false)) f.ref];
      final second = s.searchLocal('yoghurt', personal: false)[1];
      s.addFood(second, meal: Meal.breakfast, grams: 150, quantity: 150);
      expect([for (final f in s.searchLocal('yoghurt', personal: false)) f.ref], before);
      // Met voorrang staat wat je at nog altijd eerst (Snel loggen gebruikt dat)
      expect(s.searchLocal('yoghurt').first.ref, second.ref);
    });

    testWidgets('wat je at, staat apart bovenaan onder een kop', (tester) async {
      setAppLang(AppLang.en);
      addTearDown(() => setAppLang(AppLang.nl));
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final second = s.searchLocal('yoghurt', personal: false)[1];
      s.addFood(second, meal: Meal.breakfast, grams: 150, quantity: 150);
      await tester.pumpWidget(app(const AddFoodScreen(meal: Meal.lunch)));
      await tester.enterText(find.byType(TextField).first, 'yoghurt');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Recent and favourites'), findsOneWidget);
      expect(find.text('All results'), findsOneWidget);
    });
  });

  group('N93 chips in het donker', () {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    test('de rand haalt minstens 3:1 tegen achtergrond en kaarten', () {
      for (final c in [Palette.dark.bg, Palette.dark.surface, Palette.dark.surface2]) {
        expect(contrast(chipEdgeDark, c), greaterThanOrEqualTo(3));
      }
      expect(buildTheme(Brightness.dark).chipTheme.side?.color, chipEdgeDark);
    });

    testWidgets('een niet-gekozen PillChip krijgt die rand', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(body: PillChip(label: 'Groenten', selected: false, onTap: () {})),
          brightness: Brightness.dark,
        ),
      );
      final m = tester.widget<Material>(find.descendant(of: find.byType(PillChip), matching: find.byType(Material)).first);
      expect((m.shape! as StadiumBorder).side.color, chipEdgeDark);
    });
  });
}
