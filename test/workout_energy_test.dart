import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/platform/workout_energy.dart';

void main() {
  final start = DateTime(2026, 10, 27, 18);
  final end = DateTime(2026, 10, 27, 18, 40);
  // Ruststofwisseling 1925 kcal per dag: ±53 kcal in 40 minuten
  const rest = 1925 / 1440;

  test('actieve energie binnen de workout telt, niet het totaal', () {
    final kcal = workoutActiveKcal(
      start: start,
      end: end,
      total: 400,
      active: [EnergySpan(start, start.add(const Duration(minutes: 20)), 170), EnergySpan(start.add(const Duration(minutes: 20)), end, 175)],
      restKcalPerMin: rest,
    );
    expect(kcal, 345);
  });

  test('een dagtotaal aan actieve energie telt niet voor één workout: dan het totaal min rustverbruik', () {
    final kcal = workoutActiveKcal(
      start: start,
      end: end,
      total: 400,
      active: [EnergySpan(DateTime(2026, 10, 27), DateTime(2026, 10, 28), 900)],
      restKcalPerMin: rest,
    );
    expect(kcal, closeTo(400 - 1925 / 1440 * 40, 1e-9));
  });

  test('zonder actieve energie: totaal min rustverbruik, nooit onder 0', () {
    expect(workoutActiveKcal(start: start, end: end, total: 400, active: const [], restKcalPerMin: rest), closeTo(346.5, 0.1));
    expect(workoutActiveKcal(start: start, end: end, total: 30, active: const [], restKcalPerMin: rest), 0);
    expect(workoutActiveKcal(start: start, end: end, total: null, active: const [], restKcalPerMin: rest), isNull);
  });

  test('actieve energie nooit boven het totaal', () {
    expect(workoutActiveKcal(start: start, end: end, total: 300, active: [EnergySpan(start, end, 350)], restKcalPerMin: rest), 300);
  });
}
