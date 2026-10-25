import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../data/user_db.dart';
import '../i18n.dart';
import '../state/app_state.dart';
import '../sync/account.dart';
import 'platform_native.dart';

/// Hoe het werkt: het toestel krijgt bij Supabase een willekeurige code (notify_register). Een taak op de
/// achtergrond (ongeveer elk kwartier, alleen met internet) vraagt met die code de openstaande uitdagingen op
/// (pending_challenges) en toont een melding voor elke nieuwe. Zo heeft de achtergrondtaak je sessie niet nodig.
class BattleNotify {
  static const _task = 'battle-check';

  /// Code aanvragen (één keer per toestel) en de taak inplannen. Veilig om vaak aan te roepen.
  static Future<void> setup(AppState state, Account account) async {
    if (!Platform.isAndroid || !account.signedIn) return;
    final client = account.client;
    if (client == null) return;
    try {
      var token = state.user.setting('_notify')?['token'] as String?;
      if (token == null) {
        token = await client.rpc('notify_register') as String;
        state.user.setSetting('_notify', {'token': token, 'seen': const []});
      }
      await Workmanager().initialize(battleNotifyDispatcher);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Functie nog niet in Supabase (migratie niet uitgevoerd) of geen internet: later opnieuw
    }
  }

  /// Toestemming voor meldingen pas vragen als iemand je echt uitdaagt, niet meteen bij je eerste start
  /// (eerste-maaltijdmeting 25-10). Eén keer per sessie; Android toont het venster zelf niet opnieuw als het al mag.
  static bool _asked = false;
  static Future<void> askPermission() async {
    if (!Platform.isAndroid || _asked) return;
    _asked = true;
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Uitdagingen die je al in de app zag: daarvoor geen melding meer.
  static void markSeen(AppState state, Iterable<String> ids) => _markSeen(state.user, ids);

  static void _markSeen(UserDb db, Iterable<String> ids) {
    final n = db.setting('_notify');
    if (n == null) return;
    final seen = <String>{...((n['seen'] as List?) ?? const []).cast<String>(), ...ids}.toList();
    db.setSetting('_notify', {...n, 'seen': seen.length > 100 ? seen.sublist(seen.length - 100) : seen});
  }

  /// Wordt op de achtergrond uitgevoerd.
  static Future<bool> check() async {
    final db = await openUserDbOnly();
    try {
      final n = db.setting('_notify');
      final token = n?['token'] as String?;
      if (token == null || supabaseUrl.isEmpty) return true;
      final res = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/pending_challenges'),
            headers: {'apikey': supabaseAnonKey, 'Authorization': 'Bearer $supabaseAnonKey', 'Content-Type': 'application/json'},
            body: jsonEncode({'p_token': token}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return true;
      final rows = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final seen = ((n!['seen'] as List?) ?? const []).cast<String>().toSet();
      final fresh = [
        for (final r in rows)
          if (!seen.contains(r['id'])) r,
      ];
      if (fresh.isEmpty) return true;

      // Taal van de app volgen
      if (dutchAvailable && db.setting('ui')?['lang'] == 'nl') setAppLang(AppLang.nl);
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      for (final r in fresh) {
        final name = (r['name'] as String?)?.trim();
        final who = name == null || name.isEmpty ? tr('A friend', 'Een vriend') : name;
        await plugin.show(
          id: (r['id'] as String).hashCode & 0x7fffffff,
          title: tr('New battle challenge', 'Nieuwe battle-uitdaging'),
          body: tr(
            '$who challenged you to a battle. Open MacroMatrix to accept.',
            '$who daagt je uit voor een battle. Open MacroMatrix om te aanvaarden.',
          ),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'friends',
              'Friends',
              channelDescription: 'Battle challenges from friends',
              importance: Importance.high,
            ),
          ),
        );
      }
      _markSeen(db, fresh.map((r) => r['id'] as String));
      return true;
    } catch (_) {
      return true;
    } finally {
      db.close();
    }
  }
}

@pragma('vm:entry-point')
void battleNotifyDispatcher() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, _) => BattleNotify.check());
}
