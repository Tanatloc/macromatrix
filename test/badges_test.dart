import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/nutrition/badges.dart';
import 'package:macromatrix/nutrition/levels.dart';
import 'package:macromatrix/sync/friends.dart';

String _day(int i) {
  final d = DateTime(2026, 1, 1 + i);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Battle _b(int week, int me, int other, {int myMid = 0, int otherMid = 0}) => Battle(
  id: '$week',
  week: DateTime(2026, 1, 5 + 7 * week),
  challengedByMe: true,
  accepted: true,
  other: 'x',
  otherName: 'X',
  myPoints: me,
  otherPoints: other,
  myMid: myMid,
  otherMid: otherMid,
);

void main() {
  test('badges uit dagen en level', () {
    final days = {for (var i = 0; i < 31; i++) _day(i): DayStat(score: i == 3 ? 97 : 80, vitD: true, fiber: i < 10, omega: i < 7)};
    final level = levelFromScores({for (final k in days.keys) k: days[k]!.score});
    final v = badgeValues(days: days, level: level, battles: const BattleRecord(), today: DateTime(2026, 2, 1));
    final t = badgeTiers(v);
    expect(v['streak'], 31);
    expect(t['days'], 2, reason: '31 dagen: zilver (30)');
    expect(t['streak'], 2);
    expect(t['perfect'], 1);
    expect(t['vitd'], 2);
    expect(t['fiber'], 1, reason: '10 dagen: brons (7)');
    expect(t['omega'], 2, reason: '7 op rij');
    expect(t['wins'], 0);
    expect(showcaseOf([], t).length, 3);
    expect(showcaseOf(['fiber'], t).first, 'fiber');
    expect(decodeShowcase(encodeShowcase(['streak', 'fiber'], t)), [('streak', 2), ('fiber', 1)]);
  });

  test('battle-uitslag, comeback en record', () {
    final won = _b(0, 400, 300, myMid: 100, otherMid: 200);
    expect(won.result, BattleResult.won);
    expect(won.finished, isTrue);
    expect(won.comeback, isTrue);
    expect(_b(1, 200, 300).result, BattleResult.lost);
    expect(_b(2, 300, 300).result, BattleResult.draw);
    final battles = [for (var i = 0; i < 6; i++) _b(i, 500, 100)];
    var streak = 0, best = 0;
    for (final b in battles) {
      streak = b.result == BattleResult.won ? streak + 1 : 0;
      if (streak > best) best = streak;
    }
    final t = badgeTiers(
      badgeValues(
        days: const {},
        level: levelFromScores({}),
        battles: BattleRecord(played: 6, wins: 6, bestWinStreak: best, comebacks: 1),
      ),
    );
    expect(t['battles'], 2);
    expect(t['wins'], 2);
    expect(t['winstreak'], 3, reason: '6 op rij: goud (5)');
    expect(t['comeback'], 1);
    expect(availableTitles(t).map((x) => x.id), containsAll(['rookie', 'challenger', 'comeback_kid', 'unbeatable']));
    expect(availableTitles(t).map((x) => x.id), isNot(contains('champion')));
  });

  test('variatie, eiwit, perfecte weken, vrienden en scans', () {
    final days = {
      for (var i = 0; i < 14; i++) _day(4 + i): DayStat(score: 92, protein: i < 7, foods: {'f$i', 'f${i + 1}'}),
    };
    final t = badgeTiers(
      badgeValues(days: days, level: levelFromScores({}), battles: const BattleRecord(), friends: 3, scanned: 12, today: DateTime(2026, 1, 20)),
    );
    expect(t['variety'], 0, reason: '15 verschillende producten');
    expect(t['protein'], 1);
    expect(t['perfectweek'], 1, reason: '2 volle weken boven 90');
    expect(t['social'], 2);
    expect(t['scanner'], 2);
  });
}
