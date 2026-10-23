import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/i18n.dart';
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
    expect(WeeklyReportScreen.energyLine(r), 'Energy: 1680 of 2400 kcal a day (720 kcal deficit) · -220 kcal vs last week');
    expect(WeeklyReportScreen.energyTip(r), contains('720 kcal a day less'));
  });

  test('deeltekst met gewicht, beweging en notities', () {
    final text = WeeklyReportScreen.shareText(report(notes: {'2026-10-14': 'Sick,\nlittle appetite'}), 4);
    expect(text, contains('Weight: 81.2 kg (−0.6 kg this week)'));
    expect(text, contains('Exercise: 3 sessions, 140 min, 950 kcal'));
    expect(text, contains('Energy: 1680 of 2400 kcal'));
    expect(text, contains('Vitamin C 140% (▲ 20)'));
    expect(text, contains('Needs attention: Energy 70% (▼ 10)'));
    expect(text, contains('Sick, little appetite'));
  });
}
