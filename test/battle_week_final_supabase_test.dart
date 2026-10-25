import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/cloudflare_auth.dart' show AccountUser;
import 'package:macromatrix/sync/friends.dart';

import 'pro_test.dart' show newState;

/// Ingelogd tegen de nagebootste server hieronder.
class _Remote extends Account {
  _Remote(super.db, this._c) : super(onRemoteChanges: () {});
  final SupabaseClient _c;
  @override
  SupabaseClient? get client => _c;
  @override
  bool get signedIn => true;
  @override
  AccountUser? get user => const AccountUser('me', null);
}

/// Een afgelopen battleweek (vanaf maandag 03:00) gaat nog één keer met de eindstand naar de server, daarna nooit
/// meer, ook niet als je later een regel van die week wijzigt. Apart bestand: een eigen nagebootste server.
void main() {
  late HttpServer http;
  // (methode, week) van elke schrijfactie op weekly_scores
  final writes = <(String, String)>[];

  setUpAll(() => setAppLang(AppLang.en));
  final oldClock = appClock;
  tearDown(() => appClock = oldClock);
  setUp(() async {
    writes.clear();
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await utf8.decodeStream(req);
      if (req.uri.path == '/rest/v1/weekly_scores') {
        final week = req.method == 'DELETE'
            ? req.uri.queryParameters['week']!.replaceFirst('eq.', '')
            : (jsonDecode(body) as Map)['week'] as String;
        writes.add((req.method, week));
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(req.uri.path == '/rest/v1/rpc/friend_extra' ? 'null' : '[]');
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  test('vorige week: één keer na maandag 03:00, daarna nooit meer', () async {
    final s = newState();
    Friends friends() {
      final f = Friends(s, _Remote(s.user, SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key')));
      addTearDown(f.dispose);
      return f;
    }

    final banana = s.foods.search('banana', limit: 1).first;
    // Zondagavond in de week van 12 oktober
    appClock = () => DateTime(2026, 10, 18, 20);
    s.setDate(DateTime(2026, 10, 18));
    s.addFood(banana, meal: Meal.lunch, grams: 150, quantity: 1);
    final f = friends();
    await f.pushScores();
    expect(writes, contains(('POST', '2026-10-12')));
    writes.clear();

    // Maandag 02:30: de app-dag is nog zondag, de week loopt nog. Een late snack gaat nog mee.
    appClock = () => DateTime(2026, 10, 19, 2, 30);
    s.addFood(banana, meal: Meal.snacks, grams: 100, quantity: 1);
    await f.pushScores();
    expect(writes, [('POST', '2026-10-12')]);
    writes.clear();

    // Maandag 04:00: de week is voorbij. Nog één keer de eindstand, ook als die niet veranderde.
    appClock = () => DateTime(2026, 10, 19, 4);
    await f.pushScores();
    expect(writes, contains(('POST', '2026-10-12')));
    writes.clear();

    // Een regel van die week later aanpassen of wissen verandert de uitslag bij vrienden niet meer
    s.setDate(DateTime(2026, 10, 17));
    s.addFood(banana, meal: Meal.lunch, grams: 400, quantity: 1);
    await f.pushScores();
    expect(writes.where((w) => w.$2 == '2026-10-12'), isEmpty);
    // Ook niet na een herstart van de app (de vlag staat lokaal in de databank)
    await friends().pushScores();
    expect(writes.where((w) => w.$2 == '2026-10-12'), isEmpty);
  });
}
