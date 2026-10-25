import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../data/user_db.dart';
import 'cloudflare_auth.dart';
import 'sync_engine.dart';

/// Functies op de server aanroepen (vrienden, battles, Supporter, ...): dezelfde vorm als `SupabaseClient.rpc`, zodat
/// de rest van de app niet weet of het Supabase of de eigen server is. Fouten zijn [PostgrestException] met de codes
/// van Postgres (P0001 voor een eigen melding, PGRST202 voor een onbekende functie, ...).
abstract class Rpc {
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params});
}

/// Supabase (tot de overstap).
class SupabaseRpc implements Rpc {
  SupabaseRpc(this.client);
  final SupabaseClient client;

  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async => await client.rpc(fn, params: params);
}

/// De eigen server (server/ in deze repo): `/v1/rpc/<naam>` en `/v1/sync/*`, met de sessie van [CloudflareAuth].
class CloudflareApi implements Rpc {
  CloudflareApi(this.token, {String? base, http.Client? client}) : base = Uri.parse(base ?? apiUrl), _http = client ?? http.Client();

  final String? Function() token;
  final Uri base;
  final http.Client _http;

  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) => _post('/v1/rpc/$fn', params ?? const {});

  /// Kort ticket voor de WebSocket met live meldingen.
  Future<String> liveTicket() async => (await _post('/v1/live/ticket', const {}) as Map)['ticket'] as String;

  /// WebSocket-adres voor live meldingen met dit ticket.
  Uri liveUri(String ticket) => base.replace(scheme: base.scheme == 'http' ? 'ws' : 'wss', path: '/v1/live', queryParameters: {'ticket': ticket});

  Future<dynamic> get(String path, Map<String, String> query) => _send(() => _http.get(base.replace(path: path, queryParameters: query), headers: _headers()));

  Future<dynamic> _post(String path, Object body) =>
      _send(() => _http.post(base.replace(path: path), headers: _headers(), body: jsonEncode(body)));

  Map<String, String> _headers() {
    final t = token();
    return {'content-type': 'application/json', if (t != null) 'authorization': 'Bearer $t'};
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final res = await request().timeout(const Duration(seconds: 30));
    Object? data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      if (res.statusCode < 400) throw PostgrestException(message: 'invalid response', code: '${res.statusCode}');
    }
    if (res.statusCode >= 400) {
      final m = data is Map ? data : const {};
      throw PostgrestException(
        message: m['message'] as String? ?? 'HTTP ${res.statusCode}',
        // Geen code (bv. een fout van Cloudflare zelf): de HTTP-status, zoals postgrest-dart dat ook doet
        code: m['code'] as String? ?? '${res.statusCode}',
        details: m['details'],
        hint: m['hint'] as String?,
      );
    }
    return data;
  }
}

/// Een [SyncRemote] waarvan de cursor een oplopend getal is (server_seq) in plaats van een tijdstip: geen overlap
/// nodig, en een cursor van Supabase (een tijdstip) telt niet (dan alles opnieuw ophalen).
abstract class SequenceRemote implements SyncRemote {
  /// Cursor van een opgehaalde rij.
  String cursorOf(Map<String, Object?> row);
}

/// De eigen server als [SyncRemote].
class CloudflareRemote implements SequenceRemote {
  CloudflareRemote(this.api);
  final CloudflareApi api;

  @override
  Future<Map<String, int>?> push(SyncTable table, List<Map<String, Object?>> rows, {bool insertOnly = false}) async {
    final saved = await api._post('/v1/sync/push', {'table': table.name, 'rows': rows, 'insertOnly': insertOnly}) as Map;
    return {for (final e in saved.entries) '${e.key}': (e.value as num).toInt()};
  }

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    final rows = await api.get('/v1/sync/pull', {'table': table.name, 'since': ?since, 'limit': '$limit'}) as List;
    return [for (final r in rows) (r as Map).cast<String, Object?>()];
  }

  @override
  Future<List<Map<String, Object?>>> fetch(SyncTable table, List<String> keys) async {
    final rows = await api._post('/v1/sync/fetch', {'table': table.name, 'keys': keys}) as List;
    return [for (final r in rows) (r as Map).cast<String, Object?>()];
  }

  @override
  String cursorOf(Map<String, Object?> row) => '${row['server_seq']}';

  /// Zelfde indeling als bij Supabase: een fout aan één rij, aan één tabel, of alles later opnieuw.
  @override
  SyncErrorKind classify(Object error) {
    if (error is! PostgrestException) return SyncErrorKind.fatal;
    final code = error.code ?? '';
    if (code == '23503') return SyncErrorKind.table;
    if (code.length == 5 && (code.startsWith('22') || code.startsWith('23') || code.startsWith('54'))) return SyncErrorKind.row;
    if (code.isEmpty || code.startsWith('PGRST3') || RegExp(r'^\d{3}$').hasMatch(code)) return SyncErrorKind.fatal;
    return SyncErrorKind.table;
  }
}

/// Bij de eerste start met de eigen server: rijen die de bevroren Supabase nog weigerde (synced = 2), opnieuw
/// proberen. Eén keer per toestel.
void retryRejectedOnce(UserDb db) {
  if (db.setting('_cf_retried')?['done'] == true) return;
  db.retryRejected();
  db.setSetting('_cf_retried', {'done': true});
}
