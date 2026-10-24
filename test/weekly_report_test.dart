import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/report.dart';
import 'package:macromatrix/ui/screens/weekly_report_screen.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  group('aandacht', () {
    final micros = [const MapEntry('vit_d', 0.3), const MapEntry('iodine', 0.5), const MapEntry('vit_a', 0.6)];

    test('een duidelijk energietekort gaat voor op vitaminen', () {
      final order = attentionOrder({'energy': 0.6, 'protein': 1.0}, micros);
      expect(order.map((e) => e.key), ['energy', 'vit_d', 'iodine']);
    });

    test('te weinig eiwit komt ook voor de vitaminen', () {
      final order = attentionOrder({'energy': 1.0, 'protein': 0.6}, micros);
      expect(order.map((e) => e.key), ['protein', 'vit_d', 'iodine']);
    });

    test('energie in orde: alleen vitaminen en mineralen', () {
      expect(attentionOrder({'energy': 0.95, 'protein': 0.9}, micros).map((e) => e.key), ['vit_d', 'iodine', 'vit_a']);
    });
  });

  test('tip: nooit een zout product', () {
    expect(tooSaltyForTip(1200, 0.5), isTrue); // gezouten makreel
    expect(tooSaltyForTip(60, 0.5), isFalse); // wortel
    expect(tooSaltyForTip(200, 0.7), isFalse);
    expect(tooSaltyForTip(200, 1.3), isTrue); // je eet al te veel zout
  });

  WeeklyReport report({Map<String, String> notes = const {}}) => WeeklyReport(
    monday: DateTime(2026, 10, 12),
    score: 70,
    days: 5,
    partialDays: 1,
    prevScore: 65,
    best: [(nutrientByKey['vit_c']!, 1.4)],
    worst: [(nutrientByKey['energy']!, 0.7), (nutrientByKey['vit_d']!, 0.3)],
    avg: const {'energy': 0.7, 'vit_c': 1.4, 'vit_d': 0.3},
    prevAvg: const {'energy': 0.8, 'vit_c': 1.2},
    kcalAvg: 1680,
    kcalGoal: 2400,
    prevKcalAvg: 1900,
    weightStart: 81.8,
    weightEnd: 81.2,
    exercise: const WeeklyExercise(sessions: 3, minutes: 140, kcal: 950),
    notes: notes,
  );

  test('energiebalans, gewicht en verschil met vorige week', () {
    final r = report();
    expect(r.energyBalance, -720);
    expect(r.energyOff, -1);
    expect(r.kcalChange, -220);
    expect(r.weightChange, closeTo(-0.6, 1e-9));
    expect(r.changeFor('vit_c'), closeTo(0.2, 1e-9));
    expect(r.changeFor('vit_d'), isNull);
    expect(
      WeeklyReportScreen.energyLine(r),
      'Energy: 1680 of 2400 kcal a day (720 kcal deficit; average of 5 fully logged days) · -220 kcal vs last week',
    );
    expect(WeeklyReportScreen.energyTip(r), contains('720 kcal a day below your goal'));
    expect(WeeklyReportScreen.suggestGoalChange(r), isFalse);
  });

  test('energietip: stabiel gewicht = je doel ligt te hoog, met knop naar je doel', () {
    final r = WeeklyReport(
      monday: DateTime(2026, 10, 12),
      score: 70,
      days: 6,
      best: const [],
      worst: const [],
      avg: const {'energy': 0.65},
      kcalAvg: 1680,
      kcalGoal: 2600,
      weightTrend: const WeightTrend(change: -0.1, days: 13, count: 6),
    );
    expect(r.energyCase, EnergyCase.goalOff);
    expect(WeeklyReportScreen.energyTip(r), contains('Your weight is stable at about 1700 kcal'));
    expect(WeeklyReportScreen.energyTip(r), isNot(contains('Add about')));
    expect(WeeklyReportScreen.suggestGoalChange(r), isTrue);
  });

  test('verschil met vorige week: begrensd en met eenheid', () {
    final r = WeeklyReport(
      monday: DateTime(2026, 10, 12),
      score: 70,
      days: 5,
      best: const [],
      worst: const [],
      avg: const {'magnesium': 953.0, 'iron': 0.5},
      prevAvg: const {'magnesium': 0.5, 'iron': 1.24},
      goals: const {'magnesium': 350},
    );
    expect(WeeklyReportScreen.delta(r, 'magnesium'), '▲ >999%');
    expect(WeeklyReportScreen.delta(r, 'iron'), '▼ 74%');
    expect(WeeklyReportScreen.goalText(r, nutrientByKey['magnesium']!), 'goal 350 mg');
  });

  test('let op suiker: koolhydraten, suiker en bloedsuiker', () {
    final lines = WeeklyReportScreen.sugarLines(
      const SugarWeek(
        days: 6,
        carbs: 163,
        carbsGoal: 150,
        carbDaysOver: 3,
        sugars: 52,
        freeSugars: 20,
        freeSugarsMax: 50,
        freeSugarDaysOver: 1,
        glucose: 7.24,
        glucoseCount: 6,
      ),
    );
    expect(lines.first, 'Carbohydrates: 163 g a day (goal 150 g) · 3 of 6 days above');
    expect(lines, contains('Free sugar: 20 g a day (max 50 g) · 1 of 6 days above'));
    expect(lines.last, 'Blood glucose: 7.2 mmol/L on average (6 readings this week)');
  });

  test('deeltekst met gewicht, beweging en notities', () {
    final text = WeeklyReportScreen.shareText(report(notes: {'2026-10-14': 'Sick,\nlittle appetite'}), 4);
    expect(text, contains('Weight: 81.2 kg at your last weigh-in (−0.6 kg this week)'));
    expect(text, contains('Exercise: 3 sessions, 140 min logged, 950 kcal'));
    expect(text, contains('Energy: 1680 of 2400 kcal'));
    expect(text, contains('Nutrient score: 70 (+5 vs last week), average of 5 fully logged days'));
    expect(text, contains('Vitamin C 140% (▲ 20%)'));
    expect(text, contains('Needs attention: Energy 70% (▼ 10%)'));
    expect(text, contains('Sick, little appetite'));
  });

  test('Voedingsscore heet in het Nederlands nooit "Nutrient score"', () {
    setAppLang(AppLang.nl);
    addTearDown(() => setAppLang(AppLang.en));
    final text = WeeklyReportScreen.shareText(report(), 4);
    expect(text, contains('Voedingsscore: 70'));
    expect(text, isNot(contains('Nutrient score')));
  });
}
