import 'package:flutter_test/flutter_test.dart';
import 'package:voedingsapp/nutrition/insights.dart';

void main() {
  test('reeks: tot vandaag, of tot gisteren als vandaag nog leeg is', () {
    final today = DateTime(2026, 10, 16);
    expect(loggingStreak({'2026-10-14', '2026-10-15', '2026-10-16'}, today), (current: 3, longest: 3));
    expect(loggingStreak({'2026-10-14', '2026-10-15'}, today).current, 2);
    expect(loggingStreak({'2026-10-14'}, today).current, 0);
    expect(loggingStreak({}, today), (current: 0, longest: 0));
    final s = loggingStreak({'2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-16'}, today);
    expect(s, (current: 1, longest: 4), reason: 'over de maandgrens heen');
  });

  test('gewichtsdoel: 5 kg in 3 maanden', () {
    final p = WeightPlan.of(current: 80, target: 75, months: 3, tdee: 2600, bmr: 1750, male: true);
    expect(p.weeks, closeTo(13, 0.01));
    expect(p.ratePerWeek, closeTo(-0.385, 0.001));
    expect(p.dailyChange, closeTo(-423, 1));
    expect(p.dailyKcal, closeTo(2177, 1));
    expect(p.warnings, isEmpty);
  });

  test('gewichtsdoel: te snel geeft waarschuwingen', () {
    final p = WeightPlan.of(current: 80, target: 70, months: 1, tdee: 2400, bmr: 1700, male: true);
    expect(p.dailyKcal, lessThan(0));
    expect(p.warnings, hasLength(2));
  });
}
