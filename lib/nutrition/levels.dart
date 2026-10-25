/// Levels en XP.
///
/// - Elke dag waarop je in de app eten logt, geeft XP gelijk aan je volledigheidsscore van die dag (0–100).
/// - Vanaf de 7e dag op rij (een reeks van een week of langer) krijg je 1,5 keer zoveel.
/// - Alleen wat je in de app logt telt, en alleen als je het die dag of de dag erna logde: geïmporteerde gegevens
///   en achteraf ingevulde oude dagen geven geen XP. Zo begint iedereen eerlijk op level 1.
/// - Elk level vraagt meer XP. Level 100 haal je met ongeveer een jaar lang elke dag goed loggen.
library;

import 'dart:math' as math;

import '../day_clock.dart';

/// Reeks vanaf deze lengte geeft extra XP.
const streakBonusDays = 7;
const streakBonus = 1.5;

/// Totale XP die je nodig hebt om [level] te bereiken (level 1 = 0 XP).
int xpForLevel(int level) => level <= 1 ? 0 : (45 * math.pow(level - 1, 1.5)).round();

int levelForXp(int xp) {
  var l = 1;
  while (xpForLevel(l + 1) <= xp) {
    l++;
  }
  return l;
}

/// Sterren rond je profielfoto: één per 25 levels, maximaal 4.
int starsFor(int level) => math.min(4, level ~/ 25);

/// Tint van de rand rond je profielfoto (graden op het kleurenwiel): van groen via blauw en paars naar rood. De eerste
/// tien levels schuiven elk 5° op, zodat je de kleur ook in de eerste weken ziet veranderen; daarna ongeveer 1,8° per
/// level. Na level 100 verandert ze niet meer.
double levelHue(int level) {
  final steps = math.min(math.max(level, 1), 100) - 1;
  return 150 + (steps <= 9 ? steps * 5.0 : 45 + (steps - 9) * (208 - 45) / 90);
}

class DayXp {
  const DayXp(this.day, this.score, this.bonus);
  final String day;
  final int score;
  final bool bonus;
  int get xp => (score * (bonus ? streakBonus : 1)).round();
}

class LevelInfo {
  LevelInfo(this.days, {this.bonus = 0}) : xp = days.fold(0, (a, d) => a + d.xp) + bonus;

  /// Dagen die XP gaven, oudste eerst.
  final List<DayXp> days;

  /// Extra XP die niet uit gelogde dagen komt (door de beheerder toegekend).
  final int bonus;
  final int xp;

  int get level => levelForXp(xp);
  int get stars => starsFor(level);
  int get levelStart => xpForLevel(level);
  int get nextLevel => xpForLevel(level + 1);

  /// Voortgang naar het volgende level (0–1).
  double get progress => (xp - levelStart) / (nextLevel - levelStart);

  DayXp? dayOf(String day) => days.where((d) => d.day == day).firstOrNull;
}

/// XP uit de volledigheidsscore per dag ([scores]: dag "jjjj-mm-dd" → score), met de reeksbonus.
LevelInfo levelFromScores(Map<String, int> scores, {int bonus = 0}) {
  final days = scores.keys.toList()..sort();
  final out = <DayXp>[];
  var run = 0;
  DateTime? prev;
  for (final k in days) {
    final d = DateTime.parse(k);
    run = (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) ? run + 1 : 1;
    out.add(DayXp(k, scores[k]!, run >= streakBonusDays));
    prev = d;
  }
  return LevelInfo(out, bonus: bonus);
}

/// Telt een dagboekregel mee voor XP? Niet als ze geïmporteerd is, of later dan de dag erna gelogd werd.
bool countsForXp({required String id, required String day, required int createdAtMs}) {
  if (id.startsWith('import-')) return false;
  final d = DateTime.parse(day);
  final deadline = DateTime(d.year, d.month, d.day + 2, dayStartHour).millisecondsSinceEpoch;
  return createdAtMs < deadline;
}
