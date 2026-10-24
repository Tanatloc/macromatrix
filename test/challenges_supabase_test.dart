import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/nutrition/challenges.dart';
import 'package:macromatrix/sync/challenges.dart';

/// Een server zonder de migratie voor uitdagingen: PostgREST meldt een ontbrekende functie (PGRST202) of tabel
/// (PGRST205), en de app maakt daar [ChallengesMissing] van. Apart bestand: testWidgets vervangt HttpClient.
void main() {
  group('Supabase: ontbrekende functie of tabel wordt ChallengesMissing', () {
    late HttpServer http;
    final paths = <String>[];
    setUp(() async {
      paths.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((req) async {
        await utf8.decodeStream(req);
        paths.add(req.uri.path);
        final fn = req.uri.path.contains('/rpc/');
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode(
            fn
                ? {'code': 'PGRST202', 'message': 'Could not find the function public.challenge_list without parameters in the schema cache'}
                : {'code': 'PGRST205', 'message': "Could not find the table 'public.challenge_days' in the schema cache"},
          ),
        );
        await req.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    test('functies en tabel', () async {
      final r = SupabaseChallengeRemote(SupabaseClient('http://127.0.0.1:${http.port}', 'anon-key'), 'user-1');
      await expectLater(r.list(), throwsA(isA<ChallengesMissing>()));
      await expectLater(r.create(builtinChallenges.first, DateTime(2026, 10, 24), const []), throwsA(isA<ChallengesMissing>()));
      await expectLater(r.pushDays('x', {'2026-10-24': true}), throwsA(isA<ChallengesMissing>()));
      expect(paths, ['/rest/v1/rpc/challenge_list', '/rest/v1/rpc/challenge_create', '/rest/v1/challenge_days']);
      expect(isMissingTable(PostgrestException(message: 'x', code: '42501')), isFalse);
    });
  });
}
