import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/labs/supplement_advice.dart';
import 'package:macromatrix/nutrition/supplements.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/body_screen.dart';
import 'package:macromatrix/ui/screens/supplements_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/supplement_advice_view.dart';

/// Gebruikerstest ronde 8 en 9: vitamine D in je eigen eenheid (N22), bloedsuiker in mg/dL met meetmoment (N23)
/// en het aanpassen van een supplement (N71).
Supplement sup(String id) => supplementCatalog.firstWhere((s) => s.id == id);

Map<String, LabResult> labs(List<List<String>> rows) => {
  for (final v in parseLabReport(rows).values)
    if (v.marker != null) v.marker!.key: LabResult(id: v.name, day: '2026-02-03', value: v),
};

void main() {
  late FoodDb foods;
  late AppState s;
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting('nl');
    await initializeDateFormatting('en');
  });
  setUp(() {
    setAppLang(AppLang.nl);
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });
  tearDown(() => setAppLang(AppLang.nl));

  Widget app(Widget home) => ChangeNotifierProvider<AppState>.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  group('N22 vitamine D', () {
    test('49 nmol/L: "onvoldoende" in nmol/L, geen "tekort" in ng/mL', () {
      final a = supplementAdvice(
        labs: labs([
          ['Vitamine D', '49', 'nmol/L'],
        ]),
        supplements: [],
      ).single;
      expect(a.title, 'Vitamine D: onvoldoende');
      expect(a.text, allOf(contains('49 nmol/L'), contains('Onder 25 nmol/L heet een tekort'), isNot(contains('ng/mL'))));
      expect(a.catalogId, 'vitd25');
    });

    test('een tekort pas onder 25 nmol/L; grenzen in ng/mL als je verslag ng/mL gebruikt', () {
      final a = supplementAdvice(
        labs: labs([
          ['VIT D 25(OH)', '8', 'ng/mL'],
        ]),
        supplements: [],
      ).single;
      expect(a.title, 'Vitamine D: tekort');
      expect(a.text, allOf(contains('8 ng/mL'), contains('Onder 10 ng/mL'), isNot(contains('nmol'))));
      final fine = supplementAdvice(
        labs: labs([
          ['Vitamine D', '80', 'nmol/L'],
        ]),
        supplements: [],
      ).single;
      expect(fine.kind, AdviceKind.fine);
      expect(fine.text, contains('80 nmol/L'));
    });
  });

  group('N71 supplementen', () {
    test('lage bloedwaarde en te veel: één kaart "te veel" met de bloedwaarde als uitleg', () {
      final big = Supplement(id: 'c1', name: 'Vitamine D 1000 µg', dose: '1 tablet', nutrients: const {'vit_d': 1000});
      final a = supplementAdvice(
        labs: labs([
          ['Vitamine D', '49', 'nmol/L'],
        ]),
        supplements: [big],
      );
      final d = a.where((x) => x.title.startsWith('Vitamine D')).toList();
      expect(d, hasLength(1));
      expect(d.single.title, 'Vitamine D: te veel');
      expect(d.single.text, allOf(contains('vitamine D per dag'), contains('Je bloedwaarde was laag (49 nmol/L), maar dit is te veel')));
      expect(d.single.labDay, '2026-02-03');
    });

    test('naam midden in een zin: "B6" blijft in hoofdletters', () {
      final b6 = Supplement(id: 'c2', name: 'B6', dose: '1 tablet', nutrients: const {'b6': 50});
      expect(supplementAdvice(labs: const {}, supplements: [b6]).single.text, contains('50 mg B6 (pyridoxine) per dag'));
    });

    test('de naam volgt de dosis, ook het aantal IE', () {
      expect(renameForDose('Vitamine D3 25 µg (1000 IE)', {'vit_d': 25}, {'vit_d': 50}), 'Vitamine D3 50 µg (2000 IE)');
      expect(renameForDose('Vitamin D3 25 µg (1000 IU)', {'vit_d': 25}, {'vit_d': 1000}), 'Vitamin D3 1000 µg (40000 IU)');
      expect(
        renameForDose('Calcium 500 mg + vitamine D 10 µg', {'calcium': 500, 'vit_d': 10}, {'calcium': 500, 'vit_d': 20}),
        'Calcium 500 mg + vitamine D 20 µg',
      );
      // Geen hoeveelheid in de naam, of 2,5 niet te verwarren met 25: niets veranderen
      expect(renameForDose('Mijn D-druppels', {'vit_d': 25}, {'vit_d': 50}), 'Mijn D-druppels');
      expect(renameForDose('Zink 25 mg', {'zinc': 2.5}, {'zinc': 5}), 'Zink 25 mg');
    });

    testWidgets('kop "Veilig gebruik" zonder bloedwaarden', (tester) async {
      s.addSupplement(sup('zn25'));
      s.addSupplement(sup('multi'));
      await tester.pumpWidget(app(const Scaffold(body: SupplementAdvicePanel())));
      expect(find.text('Veilig gebruik'), findsOneWidget);
      expect(find.text('Supplementen en je bloed'), findsNothing);
    });

    testWidgets('aanpassen: naam volgt, eenheid rekent om, "Klopt dit?" boven de bovengrens, grote Opslaan-knop', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      s.addSupplement(sup('vitd25'));
      await tester.pumpWidget(app(const SupplementsScreen()));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Opslaan'), findsOneWidget);
      expect(find.text('Bewaren'), findsNothing);

      final amount = find.byType(TextField).at(2);
      TextEditingController ctl(Finder f) => tester.widget<TextField>(f).controller!;
      await tester.enterText(amount, '50');
      await tester.pump();
      expect(ctl(find.byType(TextField).first).text, 'Vitamine D3 50 µg (2000 IE)');

      // Naar IE: 50 µg wordt 2000 IE, niet "50 IE"
      await tester.tap(find.text('µg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IE').last);
      await tester.pumpAndSettle();
      expect(ctl(amount).text, '2000');
      expect(find.text('= 50 µg'), findsOneWidget);

      await tester.enterText(amount, '40000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();
      expect(find.text('Klopt dit?'), findsOneWidget);
      expect(find.textContaining('1000 µg (40000 IE) per dosis'), findsOneWidget);
      await tester.tap(find.text('Aanpassen'));
      await tester.pumpAndSettle();
      expect(s.supplements.single.nutrients['vit_d'], 25);

      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ja, bewaren'));
      await tester.pumpAndSettle();
      expect(s.supplements.single.nutrients['vit_d'], closeTo(1000, 1e-9));
      expect(s.supplements.single.name, 'Vitamine D3 1000 µg (40000 IE)');
      expect(tester.takeException(), isNull);
    });
  });

  group('N23 bloedsuiker', () {
    test('waarde in de andere eenheid herkennen', () {
      expect(glucoseOtherUnit(141, mgdl: false), 'mg/dL');
      expect(glucoseOtherUnit(7.8, mgdl: false), isNull);
      expect(glucoseOtherUnit(5.5, mgdl: true), 'mmol/L');
      expect(glucoseOtherUnit(99, mgdl: true), isNull);
    });

    test('meetmoment blijft lokaal bij de meting', () {
      final id = s.addBiometric('glucose', 6.1, moment: 'fasting');
      expect(s.user.biometricMoment(id), 'fasting');
      s.user.setBiometricMoment(id, null);
      expect(s.user.biometricMoment(id), isNull);
      expect(UserDb.syncTables.map((t) => t.name), isNot(contains('biometric_moments')));
    });

    testWidgets('141 als mmol/L: "Bedoel je mg/dL?", bewaard in mmol/L, getoond in mg/dL met meetmoment', (tester) async {
      setAppLang(AppLang.en);
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const BodyScreen()));
      await tester.pump();
      await tester.tap(find.text('Measurement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weight (kg)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blood glucose (mmol/L)').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '141');
      await tester.pump();
      expect(find.text('Did you mean 141 mg/dL = 7.8 mmol/L?'), findsOneWidget);
      await tester.tap(find.text('Yes, mg/dL'));
      await tester.pump();
      expect(find.text('Did you mean 141 mg/dL = 7.8 mmol/L?'), findsNothing);
      await tester.tap(find.text('Fasting').last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final b = s.biometrics.single;
      expect(b.type, 'glucose');
      expect(b.value, closeTo(141 / 18, 1e-9));
      expect(s.user.biometricMoment(b.id), 'fasting');
      expect(glucoseInMgdl(s), isTrue);
      expect(find.text('141 mg/dL'), findsOneWidget);
      expect(find.text('Fasting'), findsOneWidget); // de vastenkaart
      expect(find.textContaining(RegExp(r'^Fasting · \d\d:\d\d$')), findsOneWidget); // meetmoment en uur (N78)

      // Bij de volgende meting staan bloedsuiker (de open grafiek, N78) en mg/dL al klaar; wisselen naar mmol/L
      // rekent het getal om
      await tester.tap(find.text('Measurement'));
      await tester.pumpAndSettle();
      expect(find.text('Weight (kg)'), findsNothing);
      expect(find.text('Blood glucose (mg/dL)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '99');
      await tester.pump();
      await tester.tap(find.text('mmol/L'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '5.5');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
