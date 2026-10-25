/// Uitdagingen en het dagboek: welke uitdagingen je hebt (lokaal bewaard, ook zonder account) en hoe elke dag
/// ervoor staat. Alleen het resultaat per dag (gehaald of niet) gaat ooit naar vrienden.
library;

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../data/user_db.dart';
import '../nutrition/challenges.dart';
import '../nutrition/values.dart';
import 'app_state.dart';

extension ChallengeDays on AppState {
  /// Alle uitdagingen (lopend, nog te beginnen en afgelopen), nieuwste eerst.
  List<Challenge> get challenges {
    final raw = (user.setting('challenges')?['list'] as List?) ?? const [];
    final out = <Challenge>[];
    for (final r in raw) {
      try {
        out.add(Challenge.fromJson((r as Map).cast<String, Object?>()));
      } catch (_) {
        // Onleesbare rij (oudere of kapotte versie): overslaan
      }
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  void saveChallenges(List<Challenge> list) => saveChallengeList([for (final c in list) c.toJson()]);

  /// Een nieuwe uitdaging alleen voor jezelf (werkt zonder account).
  Challenge addChallenge(ChallengeTemplate t, DateTime start, {String? remoteId, bool owner = true}) {
    final c = Challenge(id: const Uuid().v4(), template: t, start: DateTime(start.year, start.month, start.day), remoteId: remoteId, owner: owner);
    saveChallenges([...challenges, c]);
    return c;
  }

  void updateChallenge(Challenge c) => saveChallenges([for (final x in challenges) x.id == c.id ? c : x]);

  void removeChallenge(String id) => saveChallenges([
    for (final x in challenges)
      if (x.id != id) x,
  ]);

  /// Lopende en nog te beginnen uitdagingen.
  List<Challenge> get activeChallenges {
    final today = logicalNow();
    return [
      for (final c in challenges)
        if (c.activeOn(today)) c,
    ];
  }

  /// Stand van een uitdaging vandaag, uit het dagboek.
  ChallengeProgress challengeProgressOf(Challenge c) {
    final today = logicalNow();
    final t = DateTime(today.year, today.month, today.day);
    final last = c.end.isBefore(t) ? c.end : t;
    final byDay = <String, List<DiaryEntry>>{};
    if (!last.isBefore(c.start)) {
      for (final e in user.entriesBetween(dayKey(c.start), dayKey(last))) {
        byDay.putIfAbsent(e.day, () => []).add(e);
      }
    }
    return challengeProgress(c, t, (day) => challengeInputFor(c.template.nutrient, byDay[dayKey(day)] ?? const [], day));
  }

  /// Wat één dag oplevert voor een uitdaging op [nutrient].
  ChallengeDayInput challengeInputFor(String nutrient, List<DiaryEntry> entries, DateTime day) {
    final food = [
      for (final e in entries)
        if (!e.foodRef.startsWith('supp:')) e,
    ];
    if (food.isEmpty) return ChallengeDayInput.empty;
    final double value;
    if (nutrient == vegKey) {
      value = vegPortions(entries);
    } else {
      value = NutrientTotals.sumOf(entries.map(entryValues)).values[nutrient] ?? 0;
    }
    return ChallengeDayInput(logged: true, value: value, goal: targetsWithExercise(day)[nutrient]?.goal);
  }

  /// Porties groenten (80 g) in [entries]; peulvruchten tellen hoogstens één portie. Een recept telt met de
  /// groenten in zijn ingrediënten.
  double vegPortions(Iterable<DiaryEntry> entries) {
    var veg = 0.0, legume = 0.0;
    void add(String ref, double grams, int depth) {
      if (ref.startsWith('recipe:') && depth < 3) {
        final r = user.recipe(ref);
        if (r == null || r.totalGrams <= 0) return;
        final share = grams / r.totalGrams;
        for (final i in r.ingredients) {
          add(i.foodRef, i.grams * share, depth + 1);
        }
        return;
      }
      switch (labelFor(ref)?.group) {
        case 'vegetable':
          veg += grams;
        case 'legume':
          legume += grams;
      }
    }

    for (final e in entries) {
      add(e.foodRef, e.grams, 0);
    }
    return (veg + math.min(legume, vegPortionGrams)) / vegPortionGrams;
  }
}
