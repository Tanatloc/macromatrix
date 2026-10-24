import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/account.dart';
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
  User? get user => const User(id: 'me', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-10-01T00:00:00Z');
}

/// Blokkeren en melden tegen een kleine nagebootste PostgREST-server: met de migratie block_report.sql (de functies
/// antwoorden) en zonder (PGRST202: de knoppen verdwijnen). Apart bestand: testWidgets vervangt HttpClient.
void main() {
  late HttpServer http;
  var missing = false;
  final calls = <String, Map<String, dynamic>?>{};
  var blockedRows = <Map<String, dynamic>>[];

  setUpAll(() => setAppLang(AppLang.en));
  setUp(() async {
    calls.clear();
    blockedRows = [];
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await utf8.decodeStream(req);
      final path = req.uri.path;
      final fn = path.startsWith('/rest/v1/rpc/') ? path.substring('/rest/v1/rpc/'.length) : null;
      if (fn != null) calls[fn] = body.isEmpty ? null : (jsonDecode(body) as Map?)?.cast<String, dynamic>();
      req.response.headers.contentType = ContentType.json;
      const blockFns = {'friend_block', 'friend_unblock', 'friend_report', 'friend_blocked_list'};
      if (missing && blockFns.contains(fn)) {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.$fn in the schema cache'}));
      } else {
        if (fn == 'friend_block') {
          blockedRows = [
            {'other': calls[fn]!['p_other'], 'name': 'Bob', 'avatar': null, 'created_at': '2026-10-24T10:00:00Z'},
          ];
        }
        if (fn == 'friend_unblock') blockedRows = [];
        req.response.write(
          jsonEncode(switch (fn) {
            'friend_me' => [
              {'code': 'ABCD1234', 'name': 'Me'},
            ],
            'friend_list_v2' => blockedRows.isEmpty && !calls.containsKey('friend_block')
                ? [
                    {'other': 'bob', 'name': 'Bob', 'state': 'friend', 'level': 2},
                  ]
                : [],
            'friend_blocked_list' => blockedRows,
            'friend_report' => 'reported',
            'friend_block' || 'friend_unblock' || 'friend_extra' => null,
            _ => [],
          }),
        );
      }
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  Friends friends() {
    final s = newState();
    final f = Friends(s, _Remote(s.user, SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key')));
    addTearDown(f.dispose);
    return f;
  }

  test('met de migratie: blokkeren, deblokkeren en melden', () async {
    missing = false;
    final f = friends();
    await f.load();
    expect(f.blockAvailable, isTrue);
    expect(f.list.map((x) => x.id), ['bob']);
    expect(f.blocked, isEmpty);

    expect(await f.block('bob', name: 'Bob'), isTrue);
    expect(calls['friend_block'], {'p_other': 'bob'});
    expect(f.list, isEmpty);
    expect(f.blocked.map((b) => (b.id, b.name)), [('bob', 'Bob')]);

    expect(await f.report('bob', 'harassment', note: '  rude name  '), 'reported');
    expect(calls['friend_report'], {'p_other': 'bob', 'p_reason': 'harassment', 'p_note': 'rude name'});
    // Lege notitie gaat als null; een te lange wordt ingekort tot 500 tekens
    await f.report('bob', 'spam', note: '   ');
    expect(calls['friend_report']!['p_note'], isNull);
    await f.report('bob', 'other', note: 'x' * 800);
    expect((calls['friend_report']!['p_note'] as String).length, 500);

    expect(await f.unblock('bob'), isTrue);
    expect(calls['friend_unblock'], {'p_other': 'bob'});
    expect(f.blocked, isEmpty);
    expect(f.error, isNull);
  });

  test('zonder de migratie: blockAvailable false, geen foutmelding', () async {
    missing = true;
    final f = friends();
    await f.load();
    expect(f.code, 'ABCD1234');
    expect(f.blockAvailable, isFalse);
    expect(f.list.map((x) => x.id), ['bob']);

    // Ook als de knoppen nog zichtbaar waren (bv. migratie net teruggedraaid)
    f.blockAvailable = true;
    expect(await f.block('bob'), isFalse);
    expect(f.blockAvailable, isFalse);
    expect(f.error, isNull);
    expect(await f.report('bob', 'spam'), isNull);
    expect(f.error, isNull);
  });

  test('BlockedUser en meldingsteksten', () {
    final b = BlockedUser.fromRow({'other': 'x', 'name': null, 'avatar': 'a:3'});
    expect((b.id, b.name, b.avatar), ('x', '', 'a:3'));
    expect(reportReasons, ['spam', 'harassment', 'inappropriate', 'other']);
    expect(reportMessage('reported'), contains('received your report'));
    expect(reportMessage('limit'), contains('tomorrow'));
    expect(reportMessage('bad_reason'), 'That did not work.');
  });
}
