import 'dart:io';

import 'package:health/health.dart';

import '../i18n.dart';
import '../state/app_state.dart';

class HealthSync {
  HealthSync(this.state);
  final AppState state;

  static bool get supported => Platform.isAndroid;
  static final _health = Health();
  // Workouts lezen ook hun verbrande energie en afstand, dus daar is aparte toestemming voor nodig
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.WEIGHT,
    HealthDataType.WORKOUT,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.DISTANCE_DELTA,
  ];

  /// Aan op dit toestel (lokale instelling, want toestemming geldt per toestel).
  bool get enabled => state.user.setting('_health')?['on'] == true;

  /// Toestemming vragen en aanzetten. Geeft false als Health Connect ontbreekt of je weigerde.
  Future<bool> enable() async {
    if (!supported) return false;
    await _health.configure();
    if (!await _health.isHealthConnectAvailable()) {
      await _health.installHealthConnect();
      return false;
    }
    final ok = await _health.requestAuthorization(_types, permissions: [for (final _ in _types) HealthDataAccess.READ]);
    if (!ok) return false;
    state.user.setSetting('_health', {'on': true});
    await sync();
    return true;
  }

  void disable() => state.user.setSetting('_health', {'on': false});

  /// De laatste 7 dagen overnemen. Geeft het aantal nieuwe of bijgewerkte items.
  Future<int> sync() async {
    if (!supported || !enabled) return 0;
    try {
      await _health.configure();
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      var changed = 0;
      final db = state.user;

      // Stappen per dag
      for (var d = from; !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
        final end = DateTime(d.year, d.month, d.day + 1);
        final steps = await _health.getTotalStepsInInterval(d, end.isAfter(now) ? now : end);
        if (steps != null && steps > 0) {
          if (db.upsertBiometric(id: 'hc:steps:${dayKey(d)}', day: dayKey(d), type: 'steps', value: steps.toDouble())) changed++;
        }
      }

      final points = _health.removeDuplicates(
        await _health.getHealthDataFromTypes(types: const [HealthDataType.WEIGHT, HealthDataType.WORKOUT], startTime: from, endTime: now),
      );

      // Gewicht: de laatste meting per dag
      final weights = <String, (DateTime, double)>{};
      for (final p in points.where((p) => p.type == HealthDataType.WEIGHT)) {
        final v = p.value;
        if (v is! NumericHealthValue) continue;
        final day = dayKey(p.dateFrom);
        if (weights[day] == null || p.dateFrom.isAfter(weights[day]!.$1)) weights[day] = (p.dateFrom, v.numericValue.toDouble());
      }
      String? latestDay;
      for (final MapEntry(key: day, value: (at, kg)) in weights.entries) {
        final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        if (db.upsertBiometric(id: 'hc:weight:$day', day: day, type: 'weight', value: (kg * 10).round() / 10, time: time)) {
          changed++;
          if (latestDay == null || day.compareTo(latestDay) > 0) latestDay = day;
        }
      }

      // Workouts met verbrande energie
      for (final p in points.where((p) => p.type == HealthDataType.WORKOUT)) {
        final v = p.value;
        if (v is! WorkoutHealthValue || (v.totalEnergyBurned ?? 0) <= 0) continue;
        final minutes = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
        if (db.insertExerciseOnce(
          id: 'hc:${p.uuid}',
          day: dayKey(p.dateFrom),
          name: _workoutName(v.workoutActivityType),
          kcal: v.totalEnergyBurned!.toDouble(),
          minutes: minutes > 0 ? minutes : null,
        )) {
          changed++;
        }
      }

      state.user.setSetting('_health', {'on': true, 'last': now.millisecondsSinceEpoch});
      if (changed > 0) state.healthImported(latestWeightDay: latestDay);
      return changed;
    } on Exception {
      return 0;
    }
  }

  /// Wanneer voor het laatst overgenomen, of null.
  DateTime? get lastSync {
    final ms = state.user.setting('_health')?['last'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static String _workoutName(HealthWorkoutActivityType t) {
    final known = <HealthWorkoutActivityType, (String, String)>{
      HealthWorkoutActivityType.RUNNING: ('Running', 'Lopen'),
      HealthWorkoutActivityType.WALKING: ('Walking', 'Wandelen'),
      HealthWorkoutActivityType.BIKING: ('Cycling', 'Fietsen'),
      HealthWorkoutActivityType.SWIMMING_POOL: ('Swimming', 'Zwemmen'),
      HealthWorkoutActivityType.SWIMMING_OPEN_WATER: ('Swimming', 'Zwemmen'),
      HealthWorkoutActivityType.STRENGTH_TRAINING: ('Strength training', 'Krachttraining'),
      HealthWorkoutActivityType.WEIGHTLIFTING: ('Weightlifting', 'Gewichtheffen'),
      HealthWorkoutActivityType.YOGA: ('Yoga', 'Yoga'),
      HealthWorkoutActivityType.HIKING: ('Hiking', 'Wandeltocht'),
      HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING: ('HIIT', 'HIIT'),
    };
    final k = known[t];
    if (k != null) return tr(k.$1, k.$2);
    final s = t.name.toLowerCase().replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }
}
