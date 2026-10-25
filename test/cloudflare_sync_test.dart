// Synchroniseren met de eigen server (lib/sync/api.dart): CloudflareRemote met de sync-engine, tegen een kleine
// nagebootste /v1/sync (zelfde regels als server/src/sync.js: server_seq, oudere versie genegeerd, alleen eigen rijen).
// De echte server zelf wordt getest in server/test/sync.test.mjs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart' show PostgrestException;
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/api.dart';
import 'package:macromatrix/sync/sync_engine.dart';

const _banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90});

/// /v1/sync zoals de Worker het doet, in het geheugen. Per gebruiker (uit de Bearer-token).
class _Server {
  final rows = <String, Map<String, Map<String, Object?>>>{}; // tabel -> 'uid|sleutel' -> rij
  var seq = 0;
  final requests = <http.Request>[];

  static const keys = {'settings': 'key', 'notes': 'day'};

  http.Response handle(http.Request r) {
    requests.add(r);
    final uid = r.headers['authorization']?.replaceFirst('Bearer ', '');
    if (uid == null) return http.Response(jsonEncode({'code': 'PGRST301', 'message': 'not logged in'}), 401);
    if (r.url.path == '/v1/sync/push') {
      final b = jsonDecode(r.body) as Map;
      final table = b['table'] as String, key = keys[table] ?? 'id';
      final t = rows.putIfAbsent(table, () => {});
      final saved = <String, int>{};
      for (final row in (b['rows'] as List).cast<Map>()) {
        if (row['text'] is String && (row['text'] as String).length > 20000) {
          return http.Response(jsonEncode({'code': '23514', 'message': 'CHECK constraint failed'}), 400);
        }
        final id = '$uid|${row[key]}';
        final old = t[id];
        if (old != null && (b['insertOnly'] == true || (old['updated_at'] as int) > (row['updated_at'] as int))) continue;
        t[id] = {...row.cast<String, Object?>(), 'user_id': uid, 'server_seq': ++seq};
        saved['${row[key]}'] = row['updated_at'] as int;
      }
      return http.Response(jsonEncode(saved), 200);
    }
    if (r.url.path == '/v1/sync/pull') {
      final table = r.url.queryParameters['table']!;
      final since = int.parse(r.url.queryParameters['since'] ?? '0');
      final limit = int.parse(r.url.queryParameters['limit']!);
      final out = [
        for (final row in (rows[table] ?? {}).values)
          if (row['user_id'] == uid && (row['server_seq'] as int) > since) row,
      ]..sort((a, b) => (a['server_seq'] as int).compareTo(b['server_seq'] as int));
      return http.Response(jsonEncode(out.take(limit).toList()), 200);
    }
    if (r.url.path == '/v1/sync/fetch') {
      final b = jsonDecode(r.body) as Map;
      final t = rows[b['table']] ?? {};
      return http.Response(jsonEncode([for (final k in b['keys'] as List) ?t['$uid|$k']]), 200);
    }
    return http.Response('{}', 404);
  }

  CloudflareRemote remote(String uid) => CloudflareRemote(CloudflareApi(() => uid, base: 'https://api.example.org', client: MockClient((r) async => handle(r))));
}

void main() {
  late _Server server;
  late UserDb a, b;
  setUp(() {
    server = _Server();
    a = UserDb(sqlite3.openInMemory());
    b = UserDb(sqlite3.openInMemory());
  });

  Future<SyncResult> sync(UserDb db, [String uid = 'u1']) => SyncEngine(db, server.remote(uid), userId: uid).run();

  test('twee toestellen: wat A logt, komt bij B; de cursor is server_seq', () async {
    a.addEntry(day: '2026-10-25', meal: Meal.lunch, food: _banana, grams: 120, quantity: 120);
    await sync(a);
    await sync(b);
    expect(b.entriesFor('2026-10-25').single.grams, 120);
    final cursor = (b.setting('_sync')?['cursors'] as Map)['diary'];
    expect(int.tryParse('$cursor'), isNotNull);
    // Een volgende keer vraagt B alleen wat na die cursor kwam
    server.requests.clear();
    await sync(b);
    expect(server.requests.where((r) => r.url.path == '/v1/sync/pull' && r.url.queryParameters['table'] == 'diary').single.url.queryParameters['since'], '$cursor');
  });

  test('een cursor van Supabase (een tijdstip) telt niet: alles opnieuw ophalen', () async {
    a.addEntry(day: '2026-10-25', meal: Meal.lunch, food: _banana, grams: 120, quantity: 120);
    await sync(a);
    b.setSetting('_sync', {
      'user': 'u1',
      'cursors': {'diary': '2026-10-25T12:00:00.000Z'},
    });
    await sync(b);
    expect(b.entriesFor('2026-10-25'), hasLength(1));
  });

  test('alleen je eigen rijen', () async {
    a.addEntry(day: '2026-10-25', meal: Meal.lunch, food: _banana, grams: 120, quantity: 120);
    await sync(a, 'u1');
    await sync(b, 'u2');
    expect(b.entriesFor('2026-10-25'), isEmpty);
  });

  test('een geweigerde rij (23514) blijft lokaal, de rest gaat mee', () async {
    final raw = sqlite3.openInMemory();
    a = UserDb(raw);
    a.setNote('2026-10-24', 'kort');
    // Rechtstreeks in de database (de app knipt zelf al af): zoals een notitie van vóór die grens
    raw.execute('INSERT INTO notes (day, text, updated_at) VALUES (?,?,?)', ['2026-10-25', 'x' * 20001, DateTime.now().millisecondsSinceEpoch]);
    final r = await sync(a);
    expect(r.rejected, 1);
    await sync(b);
    expect(b.note('2026-10-24'), 'kort');
    expect(b.note('2026-10-25'), '');
  });

  test('fouten van de eigen server worden PostgrestException met dezelfde codes', () async {
    final api = CloudflareApi(() => null, base: 'https://api.example.org', client: MockClient((r) async => server.handle(r)));
    // Niet ingelogd: PGRST301, net als PostgREST met een verlopen sessie
    await expectLater(api.rpc('friend_list'), throwsA(isA<PostgrestException>().having((e) => e.code, 'code', 'PGRST301')));
    // Een antwoord zonder code (bv. van Cloudflare zelf): de HTTP-status als code
    final bare = CloudflareApi(() => 'u1', base: 'https://api.example.org', client: MockClient((_) async => http.Response('', 502)));
    await expectLater(bare.rpc('friend_list'), throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '502')));
    final remote = CloudflareRemote(api);
    expect(remote.classify(const PostgrestException(message: 'x', code: '23514')), SyncErrorKind.row);
    expect(remote.classify(const PostgrestException(message: 'x', code: 'PGRST301')), SyncErrorKind.fatal);
    expect(remote.classify(const PostgrestException(message: 'x', code: '42P01')), SyncErrorKind.table);
  });
}
