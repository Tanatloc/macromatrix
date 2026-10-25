import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/cloudflare_auth.dart' show AccountUser;
import 'package:macromatrix/sync/features.dart';
import 'package:macromatrix/sync/roadmap.dart';

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

/// Vroege toegang en de roadmap tegen een kleine nagebootste PostgREST-server: met de migratie
/// 20261031000000_early_access.sql (de functies antwoorden) en zonder (PGRST202).
void main() {
  late HttpServer http;
  var missing = false;
  final calls = <String, Map<String, dynamic>?>{};

  setUpAll(() => setAppLang(AppLang.en));
  setUp(() async {
    calls.clear();
    missing = false;
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await utf8.decodeStream(req);
      final path = req.uri.path;
      final fn = path.startsWith('/rest/v1/rpc/') ? path.substring('/rest/v1/rpc/'.length) : null;
      if (fn != null) calls[fn] = body.isEmpty ? null : (jsonDecode(body) as Map?)?.cast<String, dynamic>();
      req.response.headers.contentType = ContentType.json;
      if (missing) {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.$fn in the schema cache'}));
      } else {
        req.response.write(
          jsonEncode(switch (fn) {
            'my_features' => [
              {
                'id': 'demo_flag',
                'title_en': 'Demo',
                'title_nl': 'Demo',
                'early_from': '2020-01-01T00:00:00Z',
                'public_from': '2020-01-02T00:00:00Z',
                'enabled': true,
                'early': false,
              },
            ],
            'roadmap_list' => [
              {
                'id': '6f1c0a1e-0000-4000-8000-000000000001',
                'title_en': 'Training and rest days',
                'title_nl': 'Trainings- en rustdagen',
                'desc_en': 'Different goals per weekday.',
                'desc_nl': 'Andere doelen per weekdag.',
                'status': 'building',
                'sort': 10,
                'votes': 7,
                'mine': true,
              },
            ],
            'roadmap_vote' => 'limit',
            _ => [],
          }),
        );
      }
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  Account account() => _Remote(newState().user, SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key'));

  test('my_features: de server zet een vlag aan', () async {
    final f = Features(account(), known: const {'demo_flag': false});
    addTearDown(f.dispose);
    await f.refresh();
    expect(calls.containsKey('my_features'), isTrue);
    expect(f.available, isTrue);
    expect(f.has('demo_flag'), isTrue);
  });

  test('my_features ontbreekt: de standaarden', () async {
    missing = true;
    final f = Features(account(), known: const {'demo_flag': true});
    addTearDown(f.dispose);
    await f.refresh();
    expect(f.available, isFalse);
    expect(f.has('demo_flag'), isTrue);
  });

  test('roadmap_list en roadmap_vote', () async {
    final r = Roadmap(account());
    addTearDown(r.dispose);
    await r.refresh();
    expect(r.available, isTrue);
    final item = r.items.single;
    expect(item.status, RoadmapStatus.building);
    expect(item.votes, 7);
    expect(item.mine, isTrue);
    expect(item.title, 'Training and rest days');
    final res = await r.toggle(item);
    expect(calls['roadmap_vote'], {'p_item': item.id, 'p_on': false});
    expect(res, VoteResult.limit);
    // Teruggedraaid
    expect(r.items.single.mine, isTrue);
    expect(r.items.single.votes, 7);
  });

  test('roadmap ontbreekt: niet beschikbaar, geen fout', () async {
    missing = true;
    final r = Roadmap(account());
    addTearDown(r.dispose);
    await r.refresh();
    expect(r.available, isFalse);
    expect(r.failed, isFalse);
  });
}
