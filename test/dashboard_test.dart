import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/ui/screens/nutrients_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/nutrient_row.dart';

void main() {
  setUpAll(() => setAppLang(AppLang.nl));
  final targets = targetsFor(const Profile(), year: 2026);
  // Alles op doel, behalve vitamine D (20%), ijzer (50%) en magnesium (90%)
  final values = {
    for (final e in targets.entries) e.key: (e.value.goal ?? 0) * 1.5,
    'vit_d': targets['vit_d']!.goal! * 0.2,
    'iron': targets['iron']!.goal! * 0.5,
    'magnesium': targets['magnesium']!.goal! * 0.9,
    'sodium': 1500.0,
    'sfa': 10.0,
  };

  test('tekorten: alleen onder je doel, grootste eerst, hooguit 10', () {
    expect(KeyNutrients.shortfalls(values, targets), ['vit_d', 'iron', 'magnesium']);
    expect(KeyNutrients.shortfalls({}, targets).length, 10);
    expect(KeyNutrients.shortfalls({}, targets), isNot(contains('sodium')));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('belangrijk: de basis en wat vandaag nog te weinig is', (tester) async {
    var all = false;
    await pump(tester, KeyNutrients(values: values, targets: targets, onShowAll: () => all = true));
    for (final name in ['Eiwit', 'Vezels', 'Verzadigd vet', 'Natrium', 'Vitamine D', 'IJzer', 'Magnesium']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Vitamine C'), findsNothing); // op doel: niet in de lijst
    expect(find.text('Leucine'), findsNothing);
    await tester.tap(find.text('Alle voedingsstoffen tonen'));
    expect(all, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aminozuren ingeklapt als ze allemaal op doel zitten, anders gewoon zichtbaar', (tester) async {
    await pump(tester, NutrientPanel(values: values, targets: targets, groups: const [NutrientGroup.protein]));
    expect(find.text('Eiwit'), findsOneWidget);
    expect(find.text('Leucine'), findsNothing);
    await tester.tap(find.textContaining('essentiële aminozuren op doel'));
    await tester.pump();
    expect(find.text('Leucine'), findsOneWidget);

    await pump(tester, NutrientPanel(values: {...values, 'lysine': 0.1}, targets: targets, groups: const [NutrientGroup.protein]));
    expect(find.text('Leucine'), findsOneWidget);
    expect(find.textContaining('aminozuren op doel'), findsNothing);

    await pump(tester, NutrientPanel(values: values, targets: targets, groups: const [NutrientGroup.protein], collapseAmino: false));
    expect(find.text('Leucine'), findsOneWidget);
  });
}
