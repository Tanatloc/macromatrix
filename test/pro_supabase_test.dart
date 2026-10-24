import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/sync/pro.dart';

/// SupabaseProRemote tegen een kleine nagebootste PostgREST-server: met de migratie (antwoorden van my_pro en
/// photo_quota) en zonder (PGRST202 wordt ProMissing). Apart bestand: testWidgets vervangt HttpClient.
void main() {
  late HttpServer http;
  var missing = false;
  final paths = <String>[];
  setUp(() async {
    paths.clear();
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      await utf8.decodeStream(req);
      paths.add(req.uri.path);
      req.response.headers.contentType = ContentType.json;
      if (missing) {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function in the schema cache'}));
      } else {
        req.response.write(
          jsonEncode(switch (req.uri.path) {
            '/rest/v1/rpc/my_pro' => {'pro': true, 'until': '2099-01-01T00:00:00+00:00', 'source': 'manual', 'show_badge': false},
            '/rest/v1/rpc/photo_quota' => {'allowed': true, 'used': 1, 'limit': 50, 'pro': true},
            _ => null,
          }),
        );
      }
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  SupabaseProRemote remote() => SupabaseProRemote(SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key'));

  test('met de migratie: status en teller', () async {
    missing = false;
    final r = remote();
    final s = await r.mine();
    expect(s.activeAt(DateTime(2026, 10, 24)), isTrue);
    expect(s.source, 'manual');
    expect(s.showBadge, isFalse);
    final q = (await r.quota())!;
    expect((q.used, q.limit, q.pro, q.left), (1, 50, true, 49));
    await r.showBadge(true);
    expect(paths, ['/rest/v1/rpc/my_pro', '/rest/v1/rpc/photo_quota', '/rest/v1/rpc/pro_show_badge']);
  });

  test('zonder de migratie: ProMissing', () async {
    missing = true;
    final r = remote();
    await expectLater(r.mine(), throwsA(isA<ProMissing>()));
    await expectLater(r.quota(), throwsA(isA<ProMissing>()));
    await expectLater(r.showBadge(false), throwsA(isA<ProMissing>()));
  });
}
