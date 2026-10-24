/// Wekelijkse coach: de kleine samenvatting van je week die naar /api/coach gaat, en wat terugkomt.
///
/// Alleen cijfers die het weekrapport al berekent, plus de producten met de meeste energie als gewone namen en je
/// voorkeuren en allergieën als codes. Nooit je dagboek, notities, namen of iets anders dat je zelf typte.
library;

import 'package:flutter/foundation.dart';

import '../i18n.dart';
import 'allergens.dart';
import 'insights.dart' show stripKeys;
import 'nutrients.dart';
import 'preferences.dart';
import 'report.dart';

/// Vanaf zoveel volledig gelogde dagen biedt het weekrapport de coach aan (ook de server weigert minder).
const coachMinDays = 3;

/// Natrium en chloride onder je doel zijn geen tip waard: die haalt bijna iedereen ruim.
const _notLow = {'sodium', 'chloride'};

/// 'lactoseFree' → 'lactose_free'
String _snake(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

int _pct(double f) => (f * 100).round();

/// De samenvatting van [r] voor /api/coach.
Map<String, Object?> coachWeek(WeeklyReport r, {Set<DietPref> diet = const {}, Set<Allergen> allergies = const {}, String? lang}) {
  Map<String, Object?>? macro(String k) {
    final f = r.avg[k], g = r.goals[k];
    if (f == null || g == null || g <= 0) return null;
    return {'avg': (f * g).round(), 'goal': g.round()};
  }

  // De vitaminen en mineralen die het verst onder je doel bleven
  final low = [
    for (final k in stripKeys)
      if (!_notLow.contains(k) && (r.avg[k] ?? 1) < 1) MapEntry(k, r.avg[k]!),
  ]..sort((a, b) => a.value.compareTo(b.value));
  // Wat gemiddeld boven een veilige bovengrens zat
  final high = [
    for (final e in r.upperShare.entries)
      if (e.value > 1 && nutrientByKey.containsKey(e.key)) e,
  ]..sort((a, b) => b.value.compareTo(a.value));

  final t = r.weightTrend;
  final change = r.weightChange ?? t?.change;
  final trend = t == null
      ? null
      : (t.stable
            ? 'stable'
            : switch (t.direction) {
                -1 => 'down',
                1 => 'up',
                _ => null,
              });

  return {
    'v': 1,
    'lang': lang ?? (isNl ? 'nl' : 'en'),
    'days': r.days,
    'score': r.score,
    'goal': r.plan.name,
    if (r.kcalAvg != null && r.kcalGoal != null) 'energy': {'avg': r.kcalAvg!.round(), 'goal': r.kcalGoal!.round()},
    'macros': {
      for (final k in const ['protein', 'carbs', 'fat', 'fiber']) k: ?macro(k),
    },
    'low': [
      for (final e in low.take(5)) {'key': e.key, 'name': nutrientByKey[e.key]!.name, 'pct': _pct(e.value)},
    ],
    'high': [
      for (final e in high.take(5)) {'key': e.key, 'name': nutrientByKey[e.key]!.name, 'pct': _pct(e.value)},
    ],
    if (change != null || trend != null) 'weight': {if (change != null) 'change_kg': double.parse(change.toStringAsFixed(1)), 'trend': ?trend},
    'foods': r.topFoods.take(5).toList(),
    'diet': [for (final d in diet) _snake(d.name)],
    'allergies': [for (final a in allergies) a.name],
  };
}

/// Wat de coach schreef.
@immutable
class CoachResult {
  const CoachResult({required this.summary, required this.tips, this.lang = 'en'});
  final String summary;
  final List<String> tips;
  final String lang;

  static CoachResult? fromJson(Object? j) {
    if (j is! Map || j['summary'] is! String || j['tips'] is! List) return null;
    final summary = (j['summary'] as String).trim();
    final tips = [
      for (final t in j['tips'] as List)
        if (t is String && t.trim().isNotEmpty) t.trim(),
    ];
    if (summary.isEmpty || tips.isEmpty) return null;
    return CoachResult(summary: summary, tips: tips.take(3).toList(), lang: j['lang'] == 'nl' ? 'nl' : 'en');
  }

  Map<String, Object?> toJson() => {'summary': summary, 'tips': tips, 'lang': lang};
}
