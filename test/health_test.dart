import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/health_view.dart';

void main() {
  setUpAll(() => setAppLang(AppLang.nl));
  final targets = targetsFor(const Profile(), year: 2026);
  final kcal = targets['energy']!.goal!;

  /// Een dag die overal goed scoort, met [over] als afwijkingen.
  NutrientTotals day([Map<String, double> over = const {}, Map<String, double> missingEnergy = const {}]) => NutrientTotals(
    {
      for (final k in stripKeys) k: (targets[k]!.goal ?? 0) * 1.0,
      'energy': kcal,
      'fiber': 32,
      'sfa': kcal * 0.08 / 9,
      'sodium': 1600,
      'potassium': 4000,
      'sugars': kcal * 0.10 / 4,
      'epa_dha': 400,
      'protein': 90,
      'alcohol': 0,
      ...over,
    },
    const {},
    missingEnergy,
    10,
  );

  List<(NutrientTotals, Map<String, Target>)> week(NutrientTotals d, [int n = 7]) => [for (var i = 0; i < n; i++) (d, targets)];

  HealthFactor factor(HealthCheck c, String key) => c.factors.firstWhere((f) => f.key == key);

  test('gezond eten = goed, alles groen en geen advies', () {
    final c = healthCheck(week(day()), weightKg: 75)!;
    expect(c.rating, HealthRating.good);
    expect(c.score, 100);
    expect(c.days, 7);
    expect(c.factors.every((f) => f.rating == HealthRating.good && f.advice == null), isTrue);
  });

  test('veel zout, verzadigd vet en suiker, weinig vezels = slecht, slechtste bovenaan', () {
    final c = healthCheck(
      week(day({'sodium': 4000, 'sfa': kcal * 0.16 / 9, 'fiber': 12, 'sugars': kcal * 0.25 / 4, 'potassium': 2000, 'epa_dha': 0})),
      weightKg: 75,
    )!;
    expect(c.rating, HealthRating.poor);
    expect(factor(c, 'sodium').rating, HealthRating.poor);
    expect(factor(c, 'sodium').advice, isNotNull);
    expect(c.factors.first.rating, HealthRating.poor);
    expect(c.factors.first.weight, 2); // de grote risicofactoren eerst
    expect(c.factors.last.rating, HealthRating.good);
  });

  test('iets te veel zout en wat alcohol = oké per factor', () {
    final c = healthCheck(week(day({'sodium': 2200, 'alcohol': 5})), weightKg: 75)!; // 3,5 glazen per week
    expect(factor(c, 'sodium').rating, HealthRating.ok);
    expect(factor(c, 'alcohol').rating, HealthRating.ok);
    expect(c.rating, HealthRating.good); // de rest is goed
  });

  test('alcohol: meer dan 7 glazen per week = slecht', () {
    final c = healthCheck(week(day({'alcohol': 12})), weightKg: 75)!;
    expect(factor(c, 'alcohol').rating, HealthRating.poor);
  });

  test('te weinig volledige dagen = geen oordeel', () {
    expect(healthCheck(week(day(), 2), weightKg: 75), isNull);
    // Onvolledige dagen (300 kcal) tellen niet mee
    final half = day({'energy': 300});
    expect(healthCheck([...week(day(), 2), ...week(half, 5)], weightKg: 75), isNull);
    expect(healthCheck([...week(day(), 3), ...week(half, 4)], weightKg: 75)!.days, 3);
  });

  test('ontbrekende gegevens = onbekend en telt niet mee', () {
    final c = healthCheck(week(day({'sodium': 5000}, {'sodium': kcal * 0.5})), weightKg: 75)!;
    expect(factor(c, 'sodium').rating, HealthRating.unknown);
    expect(c.score, 100);
  });

  test('eiwit per kilo lichaamsgewicht', () {
    expect(factor(healthCheck(week(day({'protein': 45})), weightKg: 75)!, 'protein').rating, HealthRating.poor); // 0,6 g/kg
    expect(factor(healthCheck(week(day({'protein': 55})), weightKg: 75)!, 'protein').rating, HealthRating.ok); // 0,73 g/kg
    expect(factor(healthCheck(week(day()), weightKg: 0)!, 'protein').rating, HealthRating.unknown);
  });

  test('persoonlijk advies verandert het oordeel niet', () {
    // 0,9 g/kg: goed volgens de algemene richtlijn
    final plain = factor(healthCheck(week(day({'protein': 67.5})), weightKg: 75)!, 'protein');
    expect(plain.rating, HealthRating.good);
    expect(plain.tips, isEmpty);
    final older = factor(healthCheck(week(day({'protein': 67.5})), weightKg: 75, age: 70, trains: true)!, 'protein');
    expect(older.rating, HealthRating.good);
    expect(older.tips, hasLength(2)); // 65+ en training
    // BMI 36: advies met aangepast gewicht
    final heavy = factor(healthCheck(week(day()), weightKg: 110, heightCm: 175)!, 'protein');
    expect(heavy.tips.single, contains('aangepast gewicht'));
  });

  test('vezels: hoger doel voor wie veel eet', () {
    setAppLang(AppLang.nl);
    final big = day({'energy': 3200, 'fiber': 30});
    final f = factor(healthCheck(week(big), weightKg: 75)!, 'fiber');
    expect(f.rating, HealthRating.good);
    expect(f.tips.single, contains('45 g'));
    expect(factor(healthCheck(week(day({'energy': 3200, 'fiber': 46})), weightKg: 75)!, 'fiber').tips, isEmpty);
  });

  test('opgeslagen vitaminen: een dag met veel vult een dag met weinig aan', () {
    final high = day({'vit_d': targets['vit_d']!.goal! * 2});
    final low = day({'vit_d': 0});
    final c = healthCheck([...week(high, 3), ...week(low, 3)], weightKg: 75)!;
    expect(factor(c, 'micro').value, 'Nutrient Score 100');
  });

  test('vitamine C plas je uit: een overschot telt per dag hooguit dubbel', () {
    final goal = targets['vit_c']!.goal!;
    // 1 dag 10x je doel en 5 dagen niets: telt als 2/6, niet als 10/6
    final c = healthCheck([
      ...week(day({'vit_c': goal * 10}), 1),
      ...week(day({'vit_c': 0}), 5),
    ], weightKg: 75)!;
    final m = factor(c, 'micro');
    expect(m.value, isNot('Nutrient Score 100'));
    expect(m.tips, isEmpty); // geen bovengrens voor vitamine C: onschadelijk
  });

  test('boven de bovengrens van een opgeslagen stof = advies', () {
    final c = healthCheck(week(day({'vit_d': 150})), weightKg: 75)!; // bovengrens 100 µg
    expect(factor(c, 'micro').tips.single, contains('Vitamine D'));
  });

  testWidgets('kaart past op een smalle telefoon en toont advies na aantikken', (tester) async {
    setAppLang(AppLang.nl);
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = healthCheck(week(day({'sodium': 4000, 'fiber': 20, 'alcohol': 3})), weightKg: 75)!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(child: HealthPanel(check: c, change: -4)),
        ),
      ),
    );
    expect(find.text('Gezondheid'), findsOneWidget);
    expect(find.textContaining('Zout  ', findRichText: true), findsOneWidget);
    expect(find.textContaining('▼ 4'), findsOneWidget);
    expect(find.textContaining('kruid met kruiden'), findsNothing);
    await tester.tap(find.textContaining('Zout  ', findRichText: true));
    await tester.pump();
    expect(find.textContaining('kruid met kruiden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
