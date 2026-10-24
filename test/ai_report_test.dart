import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/sync/ai_report.dart';

/// Een AI-tekst melden tegen een kleine nagebootste PostgREST-server: met de migratie ai_reports (de functie
/// antwoordt) en zonder (PGRST202: niet gelukt, zonder te crashen).
void main() {
  late HttpServer http;
  Map<String, dynamic>? sent;
  String? fn;
  Object answer = 'reported';
  var missing = false;

  setUp(() async {
    sent = null;
    fn = null;
    answer = 'reported';
    missing = false;
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await utf8.decodeStream(req);
      fn = req.uri.path.replaceFirst('/rest/v1/rpc/', '');
      sent = (jsonDecode(body) as Map).cast<String, dynamic>();
      req.response.headers.contentType = ContentType.json;
      if (missing) {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.ai_report'}));
      } else {
        req.response.write(jsonEncode(answer));
      }
      await req.response.close();
    });
  });
  tearDown(() => http.close(force: true));

  SupabaseClient client() => SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key');

  test('ai_report met soort, tekst en notitie; te lange tekst ingekort', () async {
    final r = await const AiReporter().report(client(), kind: 'coach', text: 'x' * 5000, note: 'week 2026-10-19 · model m');
    expect(r, AiReportResult.reported);
    expect(fn, 'ai_report');
    expect(sent!['p_kind'], 'coach');
    expect((sent!['p_text'] as String).length, aiReportMaxText);
    expect(sent!['p_note'], 'week 2026-10-19 · model m');
  });

  test('te veel meldingen: limit', () async {
    answer = 'limit';
    expect(await const AiReporter().report(client(), kind: 'photo', text: 'A plate of pasta'), AiReportResult.limit);
    expect(sent!['p_kind'], 'photo');
  });

  test('zonder migratie of zonder account: failed', () async {
    missing = true;
    expect(await const AiReporter().report(client(), kind: 'coach', text: 'Hi'), AiReportResult.failed);
    expect(await const AiReporter().report(null, kind: 'coach', text: 'Hi'), AiReportResult.failed);
  });
}
