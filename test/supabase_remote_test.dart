import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:voedingsapp/data/user_db.dart';
import 'package:voedingsapp/sync/account.dart';

/// Controleert hoe [SupabaseRemote] zijn verzoeken naar de REST-API (PostgREST) opbouwt.
void main() {
  late HttpServer server;
  final requests = <(String method, Uri uri, Map<String, String> headers, String body)>[];
  var response = '[]';

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k] = v.join(','));
      requests.add((req.method, req.uri, headers, body));
      req.response.headers.contentType = ContentType.json;
      req.response.write(req.method == 'GET' ? response : '');
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  SupabaseRemote remote() => SupabaseRemote(SupabaseClient('http://127.0.0.1:${server.port}', 'anon-key'), 'user-1');
  final diary = UserDb.syncTables.firstWhere((t) => t.name == 'diary');
  final notes = UserDb.syncTables.firstWhere((t) => t.name == 'notes');
  final fasts = UserDb.syncTables.firstWhere((t) => t.name == 'fasts');

  test('versturen: upsert met de gebruiker en de juiste conflictsleutel', () async {
    await remote().push(diary, [
      {'id': 'e1', 'grams': 100, 'updated_at': 5},
    ]);
    final (method, uri, headers, body) = requests.single;
    expect(method, 'POST');
    expect(uri.path, '/rest/v1/diary');
    expect(uri.queryParameters['on_conflict'], 'user_id,id');
    expect(headers['prefer'], contains('resolution=merge-duplicates'));
    expect(headers['apikey'], 'anon-key');
    expect(jsonDecode(body), [
      {'id': 'e1', 'grams': 100, 'updated_at': 5, 'user_id': 'user-1'},
    ]);

    await remote().push(notes, [
      {'day': '2026-10-16', 'text': 'x', 'updated_at': 1},
    ]);
    expect(requests.last.$2.queryParameters['on_conflict'], 'user_id,day');

    await remote().push(fasts, [
      {'id': 'f1', 'start': 1, 'end': 2, 'goal_hours': 16, 'updated_at': 1},
    ]);
    expect((jsonDecode(requests.last.$4) as List).single['end'], 2);
  });

  test('ophalen: alles na de cursor, oplopend, met een limiet', () async {
    response = jsonEncode([
      {'user_id': 'user-1', 'id': 'e1', 'server_ts': '2026-10-16T10:00:00.000001+00:00', 'updated_at': 5, 'deleted': 0},
    ]);
    final rows = await remote().pull(diary, '2026-10-16T09:00:00.000Z', 1000);
    final (method, uri, _, _) = requests.single;
    expect(method, 'GET');
    expect(uri.path, '/rest/v1/diary');
    expect(uri.queryParameters['server_ts'], 'gt.2026-10-16T09:00:00.000Z');
    expect(uri.queryParameters['order'], startsWith('server_ts.asc'));
    expect(uri.queryParameters['limit'], '1000');
    expect(rows.single['id'], 'e1');

    await remote().pull(diary, null, 10);
    expect(requests.last.$2.queryParameters.containsKey('server_ts'), isFalse);
  });
}
