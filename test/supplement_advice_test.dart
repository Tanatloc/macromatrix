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

  group('vitamine D', () {
    final ok = labs([
      ['VIT D 25(OH)', '39', 'ng/mL'],
    ]);
    test('in orde: geen hoge dosis nodig, niets aangeraden', () {
      final a = only(supplementAdvice(labs: ok, supplements: []), 'Vitamine D');
      expect(a.kind, AdviceKind.fine);
      expect(a.text, contains('geen hoge dosis nodig'));
      expect(a.catalogId, isNull);
      expect(a.labDay, '2026-02-03');
    });

    test('in orde maar een hoge dosis: waarschuwing', () {
      final a = only(supplementAdvice(labs: ok, supplements: [sup('vitd75')]), 'Vitamine D');
      expect(a.kind, AdviceKind.warning);
      expect(a.text, contains('75 µg per dag is meer dan nodig'));
    });

    test('tekort: 25 µg voorstellen; al genoeg genomen: niets extra', () {
      final low = labs([
        ['Vitamine D', '45', 'nmol/L'], // = 18 ng/mL
      ]);
      expect(only(supplementAdvice(labs: low, supplements: []), 'Vitamine D').catalogId, 'vitd25');
      expect(only(supplementAdvice(labs: low, supplements: [sup('vitd25')]), 'Vitamine D').catalogId, isNull);
    });

    test('wat laag (20–30): 10 µg, niet als je al 10 µg neemt', () {
      final some = labs([
        ['VIT D 25(OH)', '24', 'ng/mL'],
      ]);
      expect(only(supplementAdvice(labs: some, supplements: []), 'Vitamine D').catalogId, 'vitd10');
      final a = only(supplementAdvice(labs: some, supplements: [sup('vitd10')]), 'Vitamine D');
      expect(a.catalogId, isNull);
      expect(a.text, contains('Je neemt al 10 µg'));
    });
  });

  test('ijzer: tekort -> met de arts; hoge ferritine en ijzer slikken -> stoppen', () {
    expect(
      only(
        supplementAdvice(
          labs: labs([
            ['Ferritine', '-', '18', 'µg/L', '30 - 400'],
          ]),
          supplements: [],
        ),
        'IJzer',
      ).catalogId,
      'fe14',
    );
    final high = only(
      supplementAdvice(
        labs: labs([
          ['Ferritine', '260', 'µg/L', '30 - 400'],
        ]),
        supplements: [sup('fe28')],
      ),
      'IJzer',
    );
    expect(high.kind, AdviceKind.warning);
    expect(high.text, contains('Stop met het ijzer'));
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
    expect(a.last.catalogId, 'b12_100');
  });

  testWidgets('supplementenscherm: advies openklappen en meteen toevoegen', (tester) async {
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
    expect(find.textContaining('25 µg (1000 IE) per dag'), findsNothing);
    await tester.tap(find.text('Vitamine D: onvoldoende')); // 17 ng/mL = 42 nmol/L: onvoldoende, geen tekort (N22)
    await tester.pump();
    expect(find.textContaining('25 µg (1000 IE) per dag'), findsOneWidget);
    await tester.tap(find.textContaining('toevoegen').first);
    await tester.pump();
    expect(s.supplements.single.baseId, 'vitd25');
    expect(tester.takeException(), isNull);
  });
}
