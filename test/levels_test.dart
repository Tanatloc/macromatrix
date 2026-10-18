import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/nutrition/levels.dart';

void main() {
  test('levelcurve: elk level vraagt meer, level 100 ongeveer een jaar', () {
    expect(xpForLevel(1), 0);
    expect(levelForXp(0), 1);
    for (var l = 2; l < 120; l++) {
      expect(xpForLevel(l + 1) - xpForLevel(l), greaterThan(xpForLevel(l) - xpForLevel(l - 1)));
    }
    // Een jaar elke dag score 80, met reeksbonus na de eerste 6 dagen
    final year = {for (var i = 0; i < 365; i++) _day(i): 80};
    final info = levelFromScores(year);
    expect(info.level, inInclusiveRange(95, 101));
    expect(levelForXp(xpForLevel(100)), 100);
  });

  test('reeksbonus vanaf de 7e dag op rij', () {
    final info = levelFromScores({for (var i = 0; i < 8; i++) _day(i): 50});
    expect(info.days.map((d) => d.bonus), [false, false, false, false, false, false, true, true]);
    expect(info.xp, 6 * 50 + 2 * 75);
    // Gat in de reeks: opnieuw beginnen
    final gap = levelFromScores({_day(0): 50, _day(1): 50, _day(3): 50});
    expect(gap.days.every((d) => !d.bonus), isTrue);
  });

  test('sterren, maximaal 4; kleur stopt bij 100', () {
    expect([1, 24, 25, 50, 75, 99, 100, 150].map(starsFor), [0, 0, 1, 2, 3, 3, 4, 4]);
    expect(levelHue(100), levelHue(250));
    expect(levelHue(2), isNot(levelHue(3)));
  });

  test('bonus-XP telt mee', () {
    final info = levelFromScores({_day(0): 80}, bonus: xpForLevel(100));
    expect(info.level, 100);
    expect(info.xp, xpForLevel(100) + 80);
  });

  test('geïmporteerd of achteraf gelogd telt niet', () {
    final made = DateTime(2026, 10, 16, 20).millisecondsSinceEpoch;
    expect(countsForXp(id: 'abc', day: '2026-10-16', createdAtMs: made), isTrue);
    expect(countsForXp(id: 'import-crono-x', day: '2026-10-16', createdAtMs: made), isFalse);
    expect(
      countsForXp(id: 'abc', day: '2026-10-15', createdAtMs: made),
      isTrue,
      reason: 'de dag erna mag nog',
    );
    expect(countsForXp(id: 'abc', day: '2026-10-14', createdAtMs: made), isFalse);
  });
}

String _day(int i) {
  final d = DateTime(2026, 1, 1 + i);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
