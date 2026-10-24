import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/labs/supplement_advice.dart';
import 'package:macromatrix/nutrition/supplements.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/supplements_screen.dart';
import 'package:macromatrix/ui/theme.dart';

Supplement sup(String id) => supplementCatalog.firstWhere((s) => s.id == id);

Map<String, LabResult> labs(List<List<String>> rows) => {
  for (final v in parseLabReport(rows).values)
    if (v.marker != null) v.marker!.key: LabResult(id: v.name, day: '2026-02-03', value: v),
};

SupplementAdvice only(List<SupplementAdvice> list, String title) => list.singleWhere((a) => a.title.startsWith(title));

void main() {
  setUpAll(() => setAppLang(AppLang.nl));

  // GP-9: advies uit je bloed geeft geen dosissen, stelt geen supplement voor en noemt geen oorzaken; wel de
  // waarde tegenover de normaalwaarden en "bespreek met je arts".
  final dose = RegExp(r'\d+\s*(µg|mg|IE)');
  group('vitamine D', () {
    final ok = labs([
      ['VIT D 25(OH)', '39', 'ng/mL'],
    ]);
    test('in orde: binnen de normaalwaarden, niets aangeraden', () {
      final a = only(supplementAdvice(labs: ok, supplements: []), 'Vitamine D');
      expect(a.kind, AdviceKind.fine);
      expect(a.text, contains('binnen de normaalwaarden'));
      expect(a.catalogId, isNull);
      expect(a.labDay, '2026-02-03');
    });

    test('in orde met een supplement: alleen als feit wat je neemt, geen oordeel over de dosis', () {
      final a = only(supplementAdvice(labs: ok, supplements: [sup('vitd75')]), 'Vitamine D');
      expect(a.kind, AdviceKind.fine);
      expect(a.text, contains('Je supplementen geven nu 75 µg per dag'));
      expect(a.text, isNot(contains('meer dan nodig')));
    });

    test('laag: geen dosis en geen supplement voorgesteld, wel naar de arts', () {
      final low = labs([
        ['Vitamine D', '45', 'nmol/L'], // = 18 ng/mL
      ]);
      final a = only(supplementAdvice(labs: low, supplements: []), 'Vitamine D');
      expect(a.kind, AdviceKind.suggest);
      expect(a.catalogId, isNull);
      expect(a.text, allOf(contains('Bespreek met je arts'), contains('of een supplement zinvol is')));
      expect(a.text.replaceAll('45 nmol/L', ''), isNot(matches(dose)));
      expect(only(supplementAdvice(labs: low, supplements: [sup('vitd25')]), 'Vitamine D').catalogId, isNull);
    });

    test('wat laag (20–30): aan de lage kant, zonder dosis', () {
      final some = labs([
        ['VIT D 25(OH)', '24', 'ng/mL'],
      ]);
      final a = only(supplementAdvice(labs: some, supplements: []), 'Vitamine D');
      expect(a.title, 'Vitamine D: aan de lage kant');
      expect(a.catalogId, isNull);
      expect(a.text, isNot(contains('400')));
      expect(a.text, isNot(contains('oktober')));
    });
  });

  test('ijzer: laag -> naar de arts, geen tabletten of dosis; hoge ferritine en ijzer slikken -> waarschuwing', () {
    final low = only(
      supplementAdvice(
        labs: labs([
          ['Ferritine', '-', '18', 'µg/L', '30 - 400'],
        ]),
        supplements: [],
      ),
      'Ferritine',
    );
    expect(low.catalogId, isNull);
    expect(low.text, allOf(contains('Bespreek met je arts'), isNot(contains('mg')), isNot(contains('oorzaak'))));
    final high = only(
      supplementAdvice(
        labs: labs([
          ['Ferritine', '260', 'µg/L', '30 - 400'],
        ]),
        supplements: [sup('fe28')],
      ),
      'Ferritine',
    );
    expect(high.kind, AdviceKind.warning);
    expect(high.text, allOf(contains('28 mg ijzer per dag'), contains('Bespreek met je arts'), isNot(contains('lever'))));
    // In orde en geen ijzer: niets te zeggen
    expect(
      supplementAdvice(
        labs: labs([
          ['Ferritine', '100', 'µg/L', '30 - 400'],
        ]),
        supplements: [],
      ),
      isEmpty,
    );
  });

  test('alle supplementen samen boven de bovengrens, ook zonder bloedwaarden', () {
    final a = supplementAdvice(labs: const {}, supplements: [sup('vitd75'), sup('vitdk2'), sup('multi')]);
    final d = only(a, 'Vitamine D');
    expect(d.kind, AdviceKind.warning);
    expect(d.text, allOf(contains('105 µg'), contains('100 µg'), contains('Multivitamine')));
    expect(only(supplementAdvice(labs: const {}, supplements: [sup('mg300')]), 'Magnesium').text, contains('250'));
    expect(supplementAdvice(labs: const {}, supplements: [sup('vitd25'), sup('mg200')]), isEmpty);
  });

  test('waarschuwingen eerst', () {
    final a = supplementAdvice(
      labs: labs([
        ['Vitamine B12', '-', '180', 'ng/L', '> 200'],
      ]),
      supplements: [sup('zn25'), sup('multi')],
    );
    expect(a.first.kind, AdviceKind.warning); // zink 35 mg
    expect(a.last.title, 'Vitamine B12: laag');
    expect(a.last.catalogId, isNull);
  });

  testWidgets('supplementenscherm: advies openklappen, zonder dosis of toevoegknop', (tester) async {
    tester.view.physicalSize = const Size(340, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final user = UserDb(sqlite3.openInMemory());
    user.saveLabs(
      dayKey(DateTime.now()),
      parseLabReport(const [
        ['VIT D 25(OH)', '17', 'ng/mL'],
      ]).values,
    );
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: user,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const SupplementsScreen()),
      ),
    );
    expect(find.text('Supplementen en je bloed'), findsOneWidget);
    await tester.tap(find.text('Vitamine D: laag')); // 17 ng/mL = 42 nmol/L: laag, geen "tekort" (N22, GP-9)
    await tester.pump();
    expect(find.textContaining('Bespreek met je arts'), findsOneWidget);
    expect(find.textContaining('1000 IE'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
