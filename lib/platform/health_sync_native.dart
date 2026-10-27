import 'dart:io';

import 'package:health/health.dart';

import '../i18n.dart';
import '../nutrition/targets.dart';
import '../state/app_state.dart';
import 'workout_energy.dart';

class HealthSync {
  HealthSync(this.state);
  final AppState state;

  static bool get supported => Platform.isAndroid;
  static final _health = Health();
  // Workouts lezen ook hun verbrande energie en afstand, dus daar is aparte toestemming voor nodig. Actieve energie:
  // alleen wat je door de training extra verbrandde (rustverbruik zit al in je doel, zie workoutActiveKcal)
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.WEIGHT,
    HealthDataType.WORKOUT,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.LEAN_BODY_MASS,
    HealthDataType.BODY_WATER_MASS,
  ];

  /// Lichaamssamenstelling van een slimme weegschaal: de app van de weegschaal rekent de
  /// percentages uit en zet ze in Health Connect, wij nemen ze daar over.
  static const _bodyTypes = {
    HealthDataType.BODY_FAT_PERCENTAGE: 'body_fat',
    HealthDataType.LEAN_BODY_MASS: 'lean_mass',
    HealthDataType.BODY_WATER_MASS: 'body_water',
  };

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

  /// Toestemming opnieuw vragen als er een soort bij kwam (zoals actieve energie sinds 1.22): Health Connect toont
  /// dan alleen wat nog ontbreekt. Alleen bij een tik van de gebruiker, nooit bij het automatisch overnemen.
  Future<void> requestMissing() async {
    if (!supported || !enabled) return;
    final read = [for (final _ in _types) HealthDataAccess.READ];
    if (await _health.hasPermissions(_types, permissions: read) == true) return;
    await _health.requestAuthorization(_types, permissions: read);
  }

  /// De laatste 7 dagen overnemen. Geeft het aantal nieuwe of bijgewerkte items.
  Future<int> sync() async {
    if (!supported || !enabled) return 0;
    try {
      await _health.configure();
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).plusDays(-6);
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
        await _health.getHealthDataFromTypes(
          types: [HealthDataType.WEIGHT, HealthDataType.WORKOUT, ..._bodyTypes.keys],
          startTime: from,
          endTime: now,
        ),
      );

      // Gewicht: de laatste meting per dag
      String? latestDay;
      for (final MapEntry(key: day, value: (at, kg)) in _lastPerDay(points, HealthDataType.WEIGHT).entries) {
        if (db.upsertBiometric(id: 'hc:weight:$day', day: day, type: 'weight', value: (kg * 10).round() / 10, time: _hhmm(at))) {
          changed++;
          if (latestDay == null || day.compareTo(latestDay) > 0) latestDay = day;
        }
      }

      // Lichaamssamenstelling: ook de laatste meting per dag
      for (final MapEntry(key: hcType, value: bioType) in _bodyTypes.entries) {
        for (final MapEntry(key: day, value: (at, value)) in _lastPerDay(points, hcType).entries) {
          if (db.upsertBiometric(id: 'hc:$bioType:$day', day: day, type: bioType, value: (value * 10).round() / 10, time: _hhmm(at))) changed++;
        }
      }

      // Workouts met verbrande energie: de actieve energie tijdens de workout, of het totaal min je rustverbruik
      final active = await _activeEnergy(from, now);
      final profile = state.profile;
      final restPerMin = bmr(profile, profile.ageIn(now.year)) / 1440;
      for (final p in points.where((p) => p.type == HealthDataType.WORKOUT)) {
        final v = p.value;
        if (v is! WorkoutHealthValue) continue;
        final kcal = workoutActiveKcal(
          start: p.dateFrom,
          end: p.dateTo,
          total: v.totalEnergyBurned?.toDouble(),
          active: active,
          restKcalPerMin: restPerMin,
        );
        if (kcal == null || kcal <= 0) continue;
        final minutes = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
        if (db.insertExerciseOnce(
          id: 'hc:${p.uuid}',
          day: dayKey(p.dateFrom),
          name: _workoutName(v.workoutActivityType),
          kcal: kcal.roundToDouble(),
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

  /// Actieve-energieblokken van [from] tot [to]. Leeg zonder toestemming (wie Health Connect aanzette vóór 1.22)
  /// of als de bron ze niet schrijft: dan rekent [workoutActiveKcal] met het totaal.
  static Future<List<EnergySpan>> _activeEnergy(DateTime from, DateTime to) async {
    try {
      final points = await _health.getHealthDataFromTypes(types: [HealthDataType.ACTIVE_ENERGY_BURNED], startTime: from, endTime: to);
      return [
        for (final p in _health.removeDuplicates(points))
          if (p.value case NumericHealthValue(:final numericValue)) EnergySpan(p.dateFrom, p.dateTo, numericValue.toDouble()),
      ];
    } on Exception {
      return const [];
    }
  }

  /// De laatste meting per dag voor één soort, als dag → (tijdstip, waarde).
  static Map<String, (DateTime, double)> _lastPerDay(List<HealthDataPoint> points, HealthDataType type) {
    final out = <String, (DateTime, double)>{};
    for (final p in points.where((p) => p.type == type)) {
      final v = p.value;
      if (v is! NumericHealthValue) continue;
      final day = dayKey(p.dateFrom);
      if (out[day] == null || p.dateFrom.isAfter(out[day]!.$1)) out[day] = (p.dateFrom, v.numericValue.toDouble());
    }
    return out;
  }

  static String _hhmm(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

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
