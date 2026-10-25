import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/cloudflare_auth.dart' show AccountUser;
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';

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

/// Supporterranden tegen een kleine nagebootste PostgREST-server: met de migratie supporter_frame.sql (friend_frames
/// antwoordt) en zonder (PGRST202: geen randen, de vriendenlijst werkt gewoon). Apart bestand: testWidgets vervangt
/// HttpClient.
void main() {
  late HttpServer http;
  var missing = false;
  final calls = <String, Map<String, dynamic>?>{};

  setUpAll(() => setAppLang(AppLang.en));
  setUp(() async {
    calls.clear();
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await utf8.decodeStream(req);
      final path = req.uri.path;
      final fn = path.startsWith('/rest/v1/rpc/') ? path.substring('/rest/v1/rpc/'.length) : null;
      if (fn != null) calls[fn] = body.isEmpty ? null : (jsonDecode(body) as Map?)?.cast<String, dynamic>();
      req.response.headers.contentType = ContentType.json;
      if (missing && (fn == 'friend_frames' || fn == 'pro_set_frame')) {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.$fn in the schema cache'}));
      } else {
        req.response.write(
          jsonEncode(switch (fn) {
            'friend_me' => [
              {'code': 'ABCD1234', 'name': 'Me'},
            ],
            'friend_list_v2' => [
              {'other': 'bob', 'name': 'Bob', 'state': 'friend', 'level': 2, 'supporter': true},
              {'other': 'ann', 'name': 'Ann', 'state': 'friend', 'level': 9},
            ],
            'friend_frames' => [
              {'other': 'bob', 'frame': 'orbit'},
              // Een tegenstander uit een battle, geen vriend
              {'other': 'zoe', 'frame': 'laurel'},
              // Een rand die deze versie van de app nog niet kent
              {'other': 'ann', 'frame': 'rainbow'},
            ],
            'pro_set_frame' => true,
            'friend_extra' => null,
            _ => [],
          }),
        );
      }
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  SupabaseClient client() => SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key');

  Friends friends() {
    final s = newState();
    final f = Friends(s, _Remote(s.user, client()));
    addTearDown(f.dispose);
    return f;
  }

  test('met de migratie: frameFor geeft de rand van vrienden en tegenstanders', () async {
    missing = false;
    final f = friends();
    await f.load();
    expect(calls.containsKey('friend_frames'), isTrue);
    expect(f.framesAvailable, isTrue);
    expect(f.frameFor('bob'), AvatarFrame.orbit);
    expect(f.frameFor('zoe'), AvatarFrame.laurel);
    expect(f.frameFor('ann'), isNull);
    expect(f.frameFor('nobody'), isNull);
    expect(f.frameFor(null), isNull);
    // Zonder Pro geen eigen rand
    expect(f.myFrame, isNull);
    expect(f.error, isNull);
  });

  test('zonder de migratie: geen randen, geen foutmelding, de lijst laadt', () async {
    missing = true;
    final f = friends();
    await f.load();
    expect(f.framesAvailable, isFalse);
    expect(f.frameFor('bob'), isNull);
    expect(f.list.map((x) => x.id), ['bob', 'ann']);
    expect(f.error, isNull);
  });

  test('pro_set_frame: met en zonder de migratie', () async {
    missing = false;
    final remote = SupabaseProRemote(client());
    expect(await remote.setFrame(AvatarFrame.sparkle), isTrue);
    expect(calls['pro_set_frame'], {'p_frame': 'sparkle'});
    await remote.setFrame(null);
    expect(calls['pro_set_frame'], {'p_frame': null});

    missing = true;
    await expectLater(remote.setFrame(AvatarFrame.glow), throwsA(isA<FrameMissing>()));
  });
}
