import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/day_clock.dart';
import 'package:macromatrix/nutrition/targets.dart';

void main() {
  DateTime inDays(int d) {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day + d);
  }

  test('pace follows from what is left until the date', () {
    final p = Profile(weightKg: 80, goal: Goal.lose, targetWeightKg: 76, targetDate: inDays(56));
    expect(p.hasPlan, isTrue);
    expect(p.rate, closeTo(-0.5, 0.001));
    expect(p.goalKcal, closeTo(-550, 1));
    // Lichter geworden: het tempo daalt mee
    expect(p.copyWith(weightKg: 78).rate, closeTo(-0.25, 0.001));
  });

  test('too fast is capped, a reached goal stops the deficit', () {
    final fast = Profile(weightKg: 90, goal: Goal.lose, targetWeightKg: 80, targetDate: inDays(28));
    expect(fast.planRate, closeTo(-2.5, 0.001));
    expect(fast.rate, -Profile.maxLoss);
    final reached = Profile(weightKg: 75.9, goal: Goal.lose, targetWeightKg: 76, targetDate: inDays(28));
    expect(reached.rate, 0);
    final gain = Profile(weightKg: 60, goal: Goal.gain, targetWeightKg: 64, targetDate: inDays(7));
    expect(gain.rate, Profile.maxGain);
  });

  test('a passed date does not blow up and maintain ignores the plan', () {
    final late = Profile(weightKg: 80, goal: Goal.lose, targetWeightKg: 78, targetDate: inDays(-10));
    // Datum voorbij: het standaardtempo van het doel tot je een nieuwe datum kiest, niet het hoogste tempo
    expect(late.rate, Goal.lose.defaultRate);
    final maintain = Profile(weightKg: 80, goal: Goal.maintain, targetWeightKg: 70, targetDate: inDays(100));
    expect(maintain.hasPlan, isFalse);
    expect(maintain.rate, 0);
  });

  test('plan survives json', () {
    final p = Profile(weightKg: 80, goal: Goal.lose, targetWeightKg: 72.5, targetDate: DateTime(2027, 3, 1));
    final back = Profile.fromJson(p.toJson());
    expect(back.targetWeightKg, 72.5);
    expect(back.targetDate, DateTime(2027, 3, 1));
    expect(Profile.fromJson(const Profile().toJson()).targetDate, isNull);
  });
}
