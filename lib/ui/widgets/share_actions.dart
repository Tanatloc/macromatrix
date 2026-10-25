/// Ingangen voor de deelkaarten: maandoverzicht, reeks, badge, alle vitaminen en het weekrapport. Elk haalt de
/// gegevens uit AppState en opent het voorbeeld (share_sheet.dart).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/report.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import 'pro_widgets.dart';
import 'share_cards.dart';
import 'share_sheet.dart';

ShareProfile _profile(BuildContext context, AppState s) =>
    ShareProfile(avatar: s.avatar, level: s.level.level, frame: myFrameOf(context, listen: false));

ShareToggle get _profileToggle => ShareToggle(ShareShow.profile, tr('Show my profile picture and level', 'Mijn profielfoto en level tonen'));

/// Maand- of jaaroverzicht delen.
Future<void> shareRecap(BuildContext context, Recap r, {String? copyText}) {
  final s = context.read<AppState>();
  final profile = _profile(context, s);
  return showShareSheet(
    context,
    fileName: r.year ? 'macromatrix-${r.from.year}' : 'macromatrix-${dayKey(r.from).substring(0, 7)}',
    copyText: copyText,
    toggles: [
      if (r.topFoods.isNotEmpty) ShareToggle(ShareShow.topFood, tr('Show my most logged food', 'Wat ik het vaakst at tonen'), initial: true),
      ShareToggle(ShareShow.energy, tr('Show my average energy (kcal)', 'Mijn gemiddelde energie (kcal) tonen')),
      _profileToggle,
    ],
    card: (show) => RecapShareCard(recap: r, show: show, profile: profile),
  );
}

/// De laatste 14 dagen (oudste eerst): gelogd of niet.
List<bool> recentLogged(Set<String> days, DateTime today) => [
  for (var i = 13; i >= 0; i--) days.contains(dayKey(DateTime(today.year, today.month, today.day - i))),
];

/// Je reeks delen ([days] = de reeks of mijlpaal die op de kaart komt; standaard je huidige reeks).
Future<void> shareStreak(BuildContext context, {int? days}) {
  final s = context.read<AppState>();
  final logged = s.user.loggedDays();
  final st = s.streak;
  final profile = _profile(context, s);
  final n = days ?? st.current;
  return showShareSheet(
    context,
    fileName: 'macromatrix-streak-$n',
    toggles: [_profileToggle],
    card: (show) => StreakShareCard(
      days: n,
      longest: st.longest < n ? n : st.longest,
      recent: recentLogged(logged, logicalNow()),
      totalDays: logged.length,
      show: show,
      profile: profile,
    ),
  );
}

/// Een badge delen. Bij de reeks-badge met een lopende reeks: de reekskaart.
Future<void> shareBadge(BuildContext context, {required String category, required int tier, required int value}) {
  final s = context.read<AppState>();
  if (category == 'streak' && s.streak.current >= 2) return shareStreak(context);
  final profile = _profile(context, s);
  return showShareSheet(
    context,
    fileName: 'macromatrix-badge-$category',
    toggles: [_profileToggle],
    card: (show) => GoalShareCard.badge(category: category, tier: tier, value: value, show: show, profile: profile),
  );
}

/// Vitaminen en mineralen die meetellen voor "allemaal gehaald": met een doel, zonder de basis (zout).
List<(String, String)> _microsWithGoal(Map<String, Target> targets) => [
  for (final (k, abbr) in [...stripVitamins, ...stripMinerals])
    if (k != 'sodium' && (targets[k]?.goal ?? 0) > 0) (k, abbr),
];

/// Hoeveel vitaminen en mineralen je doel haalden, van hoeveel.
({int reached, int total}) microsReached(NutrientMap values, Map<String, Target> targets) {
  final keys = _microsWithGoal(targets);
  return (reached: keys.where((x) => (values[x.$1] ?? 0) >= targets[x.$1]!.goal!).length, total: keys.length);
}

/// "Alle vitaminen en mineralen vandaag" delen.
Future<void> shareAllMicros(BuildContext context, {required NutrientMap values, required Map<String, Target> targets, DateTime? day}) {
  final s = context.read<AppState>();
  final profile = _profile(context, s);
  final m = microsReached(values, targets);
  final labels = [for (final (_, a) in _microsWithGoal(targets)) a];
  final d = day ?? logicalNow();
  return showShareSheet(
    context,
    fileName: 'macromatrix-${dayKey(d)}',
    toggles: [_profileToggle],
    card: (show) => GoalShareCard.allMicros(reached: m.reached, total: m.total, day: d, labels: labels, show: show, profile: profile),
  );
}

/// Weekrapport delen. Gewicht en energie alleen als je ze aanvinkt.
Future<void> shareWeek(BuildContext context, WeeklyReport r, {String? copyText}) {
  final s = context.read<AppState>();
  final profile = _profile(context, s);
  // Dezelfde dagen als de kop en het gemiddelde: volledig gelogd en voorbij (SU-4), niet de battleregel "op tijd"
  final scores = [for (var i = 0; i < 7; i++) r.dayScores[dayKey(r.monday.plusDays(i))]];
  final streak = s.streak.current;
  return showShareSheet(
    context,
    fileName: 'macromatrix-week-${dayKey(r.monday)}',
    copyText: copyText,
    toggles: [
      if (r.kcalAvg != null) ShareToggle(ShareShow.energy, tr('Show my average energy (kcal)', 'Mijn gemiddelde energie (kcal) tonen')),
      if (r.weightChange != null) ShareToggle(ShareShow.weight, tr('Show my weight change', 'Mijn gewichtsverandering tonen')),
      _profileToggle,
    ],
    card: (show) => WeekShareCard(report: r, dayScores: scores, streak: streak, show: show, profile: profile),
  );
}
