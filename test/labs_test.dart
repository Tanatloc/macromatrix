import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/labs/markers.dart';
import 'package:macromatrix/labs/pdf_text.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/labs_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/health_view.dart';

/// Een verslag zoals Helena het geeft (verzonnen persoon en waarden), als regels met kolommen.
const _report = [
  ['Medisch Centrum', 'JAN PEETERS ( 00000000000 )'],
  ['Teststraat 1', 'Datum labo : 03/02/2026'],
  ['Geboortedatum : 01/01/1980'],
  ['Analyse', 'Resultaat', 'Eenheid', 'Referentie', 'Tijd'],
  ['waarden'],
  ['HEMATOLOGIE'],
  ['Hemoglobine', '15,1', 'g/dL', '13,2 - 17,3'],
  ['RDW', '-', '11,0', '%', '11,5 - 14,5'],
  ['Ferritine', '-', '18', 'µg/L', '30 - 400'],
  ['Vitamine B12', '310', 'ng/L', '> 200'],
  ['De kans op een vitamine B12 deficiëntie op'],
  ['<100 ng/L: hoog'],
  ['eGFR (CKD-EPI)', '93', 'mL/min/1,73 m2 > .'],
  ['HDL-cholesterol', '-', '35', 'mg/dL', '> 40'],
  ['Ratio totaal-cholesterol:HDL-cholesterol', '+', '4,6', '< 3,5'],
  ['LDL-cholesterol', '131', 'mg/dL', '< 100'],
  ['SGPT', '+', '52', 'U/L', '< 41'],
  ['VIT D 25(OH)', '18', 'ng/mL', '> .'],
  ['CRP', '< 5', 'mg/L', '< 5,0'],
  ['Contr. lipemisch uitzicht', '9'],
  ['T4 VRIJ', '17,1', 'pmol/L', '12,0 - 22,0'],
];

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting('nl_BE');
  });

  group('verslag lezen', () {
    final r = parseLabReport(_report);
    LabValue v(String key) => r.values.firstWhere((x) => x.marker?.key == key);

    test('datum van de afname, niet de geboortedatum', () {
      expect(r.date, DateTime(2026, 2, 3));
      expect(
        parseLabReport([
          ['Geboortedatum : 01/01/1980'],
          ['Ferritine', '50', 'µg/L', '30 - 400'],
        ]).date,
        isNull,
      );
    });

    test('waarden, eenheden en referenties', () {
      expect(v('hemoglobin').value, 15.1);
      expect(v('hemoglobin').unit, 'g/dL');
      expect((v('hemoglobin').low, v('hemoglobin').high), (13.2, 17.3));
      expect(v('b12').low, 200);
      expect(v('b12').high, isNull);
      expect(v('egfr').unit, 'mL/min/1,73 m2');
      expect(v('crp').comparator, '<');
      expect(v('crp').value, 5);
    });

    test('tekens van het labo: - is te laag, + te hoog', () {
      expect(v('ferritin').flag, -1);
      expect(v('hdl').flag, -1);
      expect(v('alt').flag, 1);
      expect(v('ldl').flag, 1); // geen teken, maar boven de referentie
      expect(v('b12').flag, 0);
    });

    test('vitamine D zonder referentie: de grens van de app (30 ng/mL)', () {
      expect(v('vit_d').low, isNull);
      expect(v('vit_d').status, -1);
    });

    test('onbekende stoffen blijven bewaard, opmerkingen en controles niet', () {
      final names = [for (final x in r.values) x.name];
      expect(names, containsAll(['RDW', 'T4 VRIJ', 'Ratio totaal-cholesterol:HDL-cholesterol']));
      expect(names.where((n) => n.startsWith('Contr.') || n.startsWith('De kans') || n == 'Analyse'), isEmpty);
      expect(names.any((n) => n.contains('PEETERS')), isFalse);
    });

    test('platte tekst met kolommen van minstens twee spaties', () {
      final lines = linesFromText('Ferritine        -   18    µg/L     30 - 400\nVitamine D   45 nmol/L');
      expect(lines.first, ['Ferritine', '-', '18', 'µg/L', '30 - 400']);
    });
  });

  group('eenheden', () {
    test('omrekenen naar de eenheid van de app', () {
      final d = labMarkerByKey['vit_d']!;
      expect(toMarkerUnit(d, 75, 'nmol/L'), closeTo(30, 0.01));
      expect(toMarkerUnit(d, 30, 'ng/mL'), 30);
      expect(toMarkerUnit(labMarkerByKey['ldl']!, 3, 'mmol/L'), closeTo(116, 0.1));
      expect(toMarkerUnit(labMarkerByKey['alt']!, 40, 'IU/L'), 40);
      expect(toMarkerUnit(d, 30, 'g/L'), isNull);
    });

    test('namen in het Frans en Engels', () {
      expect(labMarkerFor('Ferritin')?.key, 'ferritin');
      expect(labMarkerFor('Acide folique')?.key, 'folate');
      expect(labMarkerFor('25-OH Vitamine D')?.key, 'vit_d');
      expect(labMarkerFor('Gamma-GT')?.key, 'ggt');
    });
  });

  test('pdf: tekst op zijn plaats, kolommen en beide soorten lettertypes', () async {
    final lines = await pdfTableLines(_pdf());
    expect(lines, [
      ['Datum labo : 03/02/2026'],
      ['Ferritine', '-', '18', 'µg/L', '30 - 400'],
      ['Vitamine B12', '310', 'ng/L'],
    ]);
    expect(parseLabReport(lines).values.first.flag, -1);
  });

  test('bewaren: zelfde verslag twee keer geeft geen dubbels, wissen haalt alles weg', () {
    final db = UserDb(sqlite3.openInMemory());
    final values = parseLabReport(_report).values;
    db.saveLabs('2026-02-03', values);
    db.saveLabs('2026-02-03', values);
    expect(db.labs(), hasLength(values.length));
    final f = db.labs().firstWhere((r) => r.value.marker?.key == 'ferritin');
    expect((f.value.value, f.value.flag, f.day), (18.0, -1, '2026-02-03'));
    db.deleteLab(f.id);
    expect(db.labs(), hasLength(values.length - 1));
    db.wipeUserData();
    expect(db.labs(), isEmpty);
  });

  group('advies uit bloedwaarden', () {
    final targets = targetsFor(const Profile(), year: 2026);
    final kcal = targets['energy']!.goal!;
    final day = NutrientTotals(
      {
        for (final k in stripKeys) k: (targets[k]!.goal ?? 0) * 1.0,
        'energy': kcal,
        'fiber': 32,
        'sfa': kcal * 0.08 / 9,
        'sodium': 1600,
        'potassium': 4000,
        'sugars': kcal * 0.10 / 4,
        'epa_dha': 400,
        'protein': 60,
      },
      const {},
      const {},
      10,
    );
    final week = [for (var i = 0; i < 7; i++) (day, targets)];
    Map<String, LabResult> labs(List<List<String>> rows) => {
      for (final v in parseLabReport(rows).values)
        if (v.marker != null) v.marker!.key: LabResult(id: v.name, day: '2026-02-03', value: v),
    };
    HealthFactor factor(HealthCheck c, String key) => c.factors.firstWhere((f) => f.key == key);

    test('afwijkende waarden geven advies bij het juiste punt, het oordeel blijft', () {
      final c = healthCheck(week, weightKg: 75, labs: labs(_report))!;
      expect(factor(c, 'sfa').rating, HealthRating.good);
      expect(factor(c, 'sfa').bloodTips.join(), allOf(contains('LDL-cholesterol 131'), contains('HDL-cholesterol 35')));
      expect(factor(c, 'sfa').tips, isEmpty);
      expect(c.labDay, '2026-02-03');
      expect(factor(c, 'fiber').bloodTips.join(), contains('havermout'));
      expect(factor(c, 'micro').bloodTips.join(), allOf(contains('Ferritine 18'), contains('Vitamine D')));
      expect(factor(c, 'alcohol').bloodTips.join(), contains('ALT'));
      expect(factor(c, 'sodium').bloodTips, isEmpty);
    });

    testWidgets('in het rapport: druppeltje en de datum van de bloedafname', (tester) async {
      tester.view.physicalSize = const Size(340, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = healthCheck(week, weightKg: 75, labs: labs(_report))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(child: HealthPanel(check: c)),
          ),
        ),
      );
      expect(find.textContaining('afgestemd op je bloedafname van 03/02/2026'), findsOneWidget);
      expect(find.byIcon(Icons.bloodtype_rounded), findsNWidgets(5)); // bovenaan + 4 punten
      await tester.tap(find.textContaining('Verzadigd vet', findRichText: true));
      await tester.pump();
      expect(find.text('Op basis van je bloedafname van 03/02/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('verminderde nierfunctie: geen advies om meer eiwit te eten', () {
      final kidneys = labs([
        ['eGFR (CKD-EPI)', '-', '48', 'mL/min/1,73 m2', '> 60'],
      ]);
      final c = healthCheck(week, weightKg: 75, age: 70, trains: true, labs: kidneys)!;
      expect(factor(c, 'protein').bloodTips.single, contains('nierfunctie'));
      expect(factor(c, 'protein').tips, isEmpty);
    });

    test('alles in orde: geen extra advies', () {
      final c = healthCheck(
        week,
        weightKg: 75,
        labs: labs([
          ['Ferritine', '120', 'µg/L', '30 - 400'],
        ]),
      )!;
      expect(factor(c, 'micro').bloodTips, isEmpty);
    });
  });

  group('schermen passen op een smalle telefoon', () {
    Future<AppState> pump(WidgetTester tester, Widget screen, {bool withLabs = true}) async {
      tester.view.physicalSize = const Size(340, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final user = UserDb(sqlite3.openInMemory());
      if (withLabs) user.saveLabs('2026-02-03', parseLabReport(_report).values);
      final s = AppState(
        foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
        user: user,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: s,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: screen),
        ),
      );
      return s;
    }

    testWidgets('overzicht met waarden en uitleg per stof', (tester) async {
      await pump(tester, const LabsScreen());
      expect(find.textContaining('waarden buiten de normaal:'), findsOneWidget);
      expect(find.text('Ferritine'), findsOneWidget);
      await tester.tap(find.text('Ferritine'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ijzervoorraad is laag'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('afwijkend zonder uitleg over eten: niet "in orde"', (tester) async {
      final s = await pump(tester, const LabsScreen(), withLabs: false);
      s.saveLabs(
        DateTime(2026, 2, 3),
        parseLabReport([
          ['Fosfor', '-', '0,63', 'mmol/L', '0,810 - 1,450'],
        ]).values,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fosfor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('bespreek ze met je arts'), findsOneWidget);
      expect(find.text('Je laatste waarde is in orde.'), findsNothing);
    });

    testWidgets('leeg: uitleg en knoppen', (tester) async {
      await pump(tester, const LabsScreen(), withLabs: false);
      expect(find.text('PDF inlezen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nakijken en bewaren', (tester) async {
      final s = await pump(tester, LabReviewScreen(report: parseLabReport(_report)), withLabs: false);
      final n = parseLabReport(_report).values.length;
      expect(find.text('$n waarden bewaren'), findsOneWidget);
      await tester.tap(find.text('$n waarden bewaren'));
      await tester.pumpAndSettle();
      expect(s.labResults, hasLength(n));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Een kleine PDF zoals een labo ze maakt: elk vakje met zijn eigen plaats (cm), een gewoon lettertype (WinAnsi)
/// en een Type0-lettertype met een ToUnicode-tabel, zoals Helena gebruikt.
Uint8List _pdf() {
  // Type0: code 1 = 'F', 2 = 'e', ... via ToUnicode
  const word = 'Ferritine';
  final cid = [for (var i = 0; i < word.length; i++) (i + 1).toRadixString(16).padLeft(4, '0')].join();
  final cmap = StringBuffer('/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n${word.length} beginbfchar\n');
  for (var i = 0; i < word.length; i++) {
    cmap.writeln('<${(i + 1).toRadixString(16).padLeft(4, '0')}> <${word.codeUnitAt(i).toRadixString(16).padLeft(4, '0')}>');
  }
  cmap.write('endbfchar\nendcmap\nend end');
  final content =
      '''
q 1 0 0 -1 0 792 cm
q 1 0 0 1 40 40 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm [(Datum labo : 03/02/2026)] TJ ET Q
q 1 0 0 1 40 120 cm BT /F2 9 Tf 1 0 0 -1 0 8 Tm [<$cid>] TJ ET Q
q 1 0 0 1 200 120 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (-) Tj ET Q
q 1 0 0 1 228 120 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (18) Tj ET Q
q 1 0 0 1 300 120 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (\\265g/L) Tj ET Q
q 1 0 0 1 370 120 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (30 - 400) Tj ET Q
q 1 0 0 1 40 132 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (Vita) Tj 17.5 0 Td (mine B12) Tj ET Q
q 1 0 0 1 228 132 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (310) Tj ET Q
q 1 0 0 1 300 132 cm BT /F1 9 Tf 1 0 0 -1 0 8 Tm (ng/L) Tj ET Q
Q
''';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type0 /BaseFont /Arial /Encoding /Identity-H /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Arial /DW 556 >>] /ToUnicode 6 0 R >>',
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, o) in objects.indexed) {
    offsets.add(latin1.encode(out.toString()).length);
    out.write('${i + 1} 0 obj\n$o\nendobj\n');
  }
  final xref = latin1.encode(out.toString()).length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return latin1.encode(out.toString());
}
