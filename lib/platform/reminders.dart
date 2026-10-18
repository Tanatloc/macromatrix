/// Herinneringen: een melding als je om (standaard) 20:00 nog niets logde, en om 21:30 als je reeks die avond
/// verloren dreigt te gaan.
///
/// Op Android worden ze echt ingepland (ook als de app dicht is) en telkens opnieuw berekend als je iets logt. Op
/// pc en web verschijnen ze zolang de app openstaat. Instellingen staan per toestel.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../i18n.dart';
import '../state/app_state.dart';

/// Echte Android-app (geplande meldingen ook als de app dicht is).
bool get isAndroidApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class ReminderSettings {
  const ReminderSettings({this.log = true, this.hour = 20, this.minute = 0, this.streak = true});
  final bool log;
  final int hour, minute;
  final bool streak;

  ReminderSettings copyWith({bool? log, int? hour, int? minute, bool? streak}) =>
      ReminderSettings(log: log ?? this.log, hour: hour ?? this.hour, minute: minute ?? this.minute, streak: streak ?? this.streak);

  Map<String, Object?> toJson() => {'log': log, 'hour': hour, 'minute': minute, 'streak': streak};
  factory ReminderSettings.fromJson(Map<String, Object?>? j) => j == null
      ? const ReminderSettings()
      : ReminderSettings(
          log: j['log'] != false,
          hour: (j['hour'] as num?)?.toInt() ?? 20,
          minute: (j['minute'] as num?)?.toInt() ?? 0,
          streak: j['streak'] != false,
        );
}

class Reminders {
  Reminders(this.state);
  final AppState state;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final _timers = <Timer>[];
  Timer? _debounce;

  /// Herinneringen kunnen op dit toestel.
  static bool get supported => kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.linux;

  ReminderSettings get settings => ReminderSettings.fromJson(state.user.setting('_reminders'));

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      if (!kIsWeb) {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        ),
      );
      _ready = true;
      if (_android && (settings.log || settings.streak)) {
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('herinneringen: $e');
    }
    state.addListener(_changed);
    await reschedule();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(reschedule()));
  }

  Future<void> save(ReminderSettings s) async {
    state.user.setSetting('_reminders', s.toJson());
    if (_android && (s.log || s.streak)) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    }
    await reschedule();
  }

  /// Vandaag al eten gelogd (supplementen tellen niet)?
  bool get _loggedToday => state.user.loggedDays().contains(dayKey(DateTime.now()));

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Logging and streak reminders',
      importance: Importance.defaultImportance,
    ),
    linux: LinuxNotificationDetails(),
  );

  /// Alles opnieuw inplannen: vandaag als je nog niets logde, anders vanaf morgen.
  Future<void> reschedule() async {
    if (!_ready) return;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final s = settings;
    try {
      if (_android) await _plugin.cancelAll();
      final now = DateTime.now();
      final logged = _loggedToday;
      final streak = state.streak.current;
      // Twee dagen vooruit plannen, zodat er ook een melding komt als je de app morgen niet opent
      for (var d = 0; d < 2; d++) {
        final day = DateTime(now.year, now.month, now.day + d);
        if (d == 0 && logged) continue;
        if (s.log) {
          await _at(
            1 + d * 10,
            DateTime(day.year, day.month, day.day, s.hour, s.minute),
            tr('Nothing logged yet today', 'Vandaag nog niets gelogd'),
            tr('Log your meals to earn XP and keep your streak going.', 'Log je maaltijden om XP te verdienen en je reeks vol te houden.'),
          );
        }
        if (s.streak && (d == 0 ? streak : streak + (logged ? 1 : 0)) >= 2) {
          final n = d == 0 ? streak : streak + 1;
          await _at(
            2 + d * 10,
            DateTime(day.year, day.month, day.day, 21, 30),
            tr('Your $n-day streak ends tonight', 'Je reeks van $n dagen eindigt vanavond'),
            tr('Log something before midnight to keep it.', 'Log iets voor middernacht om ze te houden.'),
          );
        }
      }
    } catch (e) {
      debugPrint('herinneringen: $e');
    }
  }

  Future<void> _at(int id, DateTime when, String title, String body) async {
    if (!when.isAfter(DateTime.now())) return;
    if (_android) {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } else {
      // pc en web: alleen zolang de app openstaat, en alleen als je dan nog steeds niets logde
      _timers.add(
        Timer(when.difference(DateTime.now()), () {
          if (!_loggedToday) unawaited(_plugin.show(id: id, title: title, body: body, notificationDetails: _details));
        }),
      );
    }
  }
}
