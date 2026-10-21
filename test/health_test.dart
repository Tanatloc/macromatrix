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

  group('beweging', () {
    // Bij 75 kg: kcal per minuut = MET × 3,5 × 75 / 200
    double kcal(double met, double minutes) => met * 3.5 * 75 / 200 * minutes;
    ({String day, double? minutes, double kcal, bool strength}) ex(String day, double met, double minutes, {bool strength = false}) =>
        (day: day, minutes: minutes, kcal: kcal(met, minutes), strength: strength);
    HealthCheck check(ActivityWeek a, {int? age}) => healthCheck(week(day()), weightKg: 75, age: age, activity: a)!;

    test('niets bijgehouden: geen oordeel over beweging', () {
      final c = check(const ActivityWeek());
      expect(c.hasActivity, isFalse);
      expect(c.factors.where((f) => activityFactors.contains(f.key)), isEmpty);
    });

    test('intensief telt dubbel, licht telt niet', () {
      final run = check(ActivityWeek(exercises: [ex('a', 9, 40), ex('b', 9, 40)]));
      expect(factor(run, 'exercise').value, '160 min per week');
      expect(factor(run, 'exercise').rating, HealthRating.good);
      final walk = check(ActivityWeek(exercises: [ex('a', 4, 30), ex('b', 4, 30), ex('c', 2, 60)]));
      expect(factor(walk, 'exercise').value, '60 min per week');
      expect(factor(walk, 'exercise').rating, HealthRating.poor);
    });

    test('je houdt activiteiten bij maar bewoog niet: slecht, niet onbekend', () {
      final c = check(const ActivityWeek(tracksExercise: true));
      expect(factor(c, 'exercise').rating, HealthRating.poor);
      expect(factor(c, 'strength').rating, HealthRating.poor);
    });

    test('lopende week wordt omgerekend naar 7 dagen', () {
      final c = check(ActivityWeek(exercises: [ex('a', 4, 60)], days: 2));
      expect(factor(c, 'exercise').value, '210 min per week');
      expect(factor(c, 'exercise').note, contains('loopt nog'));
    });

    test('krachttraining: dagen tellen, niet sessies', () {
      final twoDays = check(ActivityWeek(exercises: [ex('a', 5, 45, strength: true), ex('c', 5, 45, strength: true)]));
      expect(factor(twoDays, 'strength').rating, HealthRating.good);
      final sameDay = check(ActivityWeek(exercises: [ex('a', 5, 30, strength: true), ex('a', 5, 30, strength: true)]));
      expect(factor(sameDay, 'strength').rating, HealthRating.ok);
    });

    test('stappen: vanaf 3 dagen, lager doel vanaf 60 jaar', () {
      expect(check(const ActivityWeek(steps: [9000, 9000])).factors.where((f) => f.key == 'steps'), isEmpty);
      expect(factor(check(const ActivityWeek(steps: [9000, 8500, 8200])), 'steps').rating, HealthRating.good);
      expect(factor(check(const ActivityWeek(steps: [6500, 6500, 6500])), 'steps').rating, HealthRating.ok);
      expect(factor(check(const ActivityWeek(steps: [6500, 6500, 6500]), age: 65), 'steps').rating, HealthRating.good);
      expect(check(const ActivityWeek(steps: [9000, 9000, 9000])).hasActivity, isTrue);
    });

    test('weinig bewegen telt mee in het eindoordeel', () {
      final c = check(const ActivityWeek(tracksExercise: true, steps: [2000, 2500, 3000]));
      expect(c.score, lessThan(100));
      expect(c.factors.first.key, 'exercise'); // zwaarste slechte factor bovenaan
    });
  });

  group('impact', () {
    test('cijfers per punt, en de grootste winst', () {
      final c = healthCheck(
        week(day({'sodium': 4000, 'fiber': 20})),
        weightKg: 75,
        activity: const ActivityWeek(tracksExercise: true, steps: [3000, 3200, 3500]),
      )!;
      expect(factor(c, 'sodium').impact, contains('beroerte'));
      expect(factor(c, 'sodium').impact, contains('5 g')); // 10 g zout = 5 g boven de grens
      expect(factor(c, 'exercise').impact, contains('30%'));
      expect(factor(c, 'steps').impact, contains('6000'));
      expect(c.biggestGain!.key, 'steps'); // 3200 -> 6000 stappen = ongeveer 40%
    });

    test('alles goed: wel wat het oplevert, geen grootste winst', () {
      final c = healthCheck(week(day()), weightKg: 75)!;
      expect(factor(c, 'fiber').impact, contains('15 à 30%'));
      expect(c.biggestGain, isNull);
    });

    test('beweging volgt de tabel van Arem: 150–300 minuten ongeveer 30%', () {
      expect(
        healthImpact(salt: 4, sfa: 8, fiber: 30, potassium: 4000, epaDha: 300, glasses: 0, exerciseMinutes: 200)['exercise']!.$1,
        contains('30%'),
      );
      expect(healthImpact(salt: 4, sfa: 8, fiber: 30, potassium: 4000, epaDha: 300, glasses: 0, exerciseMinutes: 60)['exercise']!.$2, 11);
      expect(healthImpact(salt: 4, sfa: 8, fiber: 30, potassium: 4000, epaDha: 300, glasses: 25)['alcohol']!.$1, contains('1 à 2 jaar'));
    });
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
