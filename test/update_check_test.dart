// Update-controle (v1.17.4): app-version.json op de website bepaalt de laagste versie die nog met de server mag praten.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/app_version.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/update_check.dart';

void main() {
  late UserDb db;
  setUp(() => db = UserDb(sqlite3.openInMemory()));

  UpdateCheck check(String version, Future<http.Response> Function() reply) =>
      UpdateCheck(db, current: version, client: MockClient((_) => reply()));

  test('versies vergelijken', () {
    expect(compareVersions('1.17.4', '1.18.0'), lessThan(0));
    expect(compareVersions('1.18.0', '1.18'), 0);
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.17.4+50', '1.17.4'), 0);
  });

  test('onder min_version: update nodig, met de link uit het bestand', () async {
    final u = check('1.17.4', () async => http.Response('{"min_version":"1.18.0","android_url":"https://example.org/x","desktop_url":"https://example.org/x"}', 200));
    expect(u.required, isFalse);
    var told = 0;
    u.addListener(() => told++);
    await u.check();
    expect(u.required, isTrue);
    expect(told, 1);
    expect(u.updateUrl, 'https://example.org/x');
  });

  test('gelijk of hoger: geen melding', () async {
    final u = check('1.18.0', () async => http.Response('{"min_version":"1.18.0"}', 200));
    await u.check();
    expect(u.required, isFalse);
  });

  test('offline of kapot bestand: de laatst gekende waarde blijft, ook na een herstart', () async {
    await check('1.17.4', () async => http.Response('{"min_version":"1.18.0"}', 200)).check();
    final offline = check('1.17.4', () async => throw Exception('geen internet'));
    expect(offline.required, isTrue);
    await offline.check();
    expect(offline.required, isTrue);
    for (final body in ['niet json', '{"min_version": 5}', '{"min_version": "1.x"}', '[]']) {
      final u = check('1.17.4', () async => http.Response(body, 200));
      await u.check();
      expect(u.required, isTrue, reason: body);
    }
  });

  test('nog nooit iets gekend en geen internet: niets blokkeren', () async {
    final u = check('1.17.4', () async => http.Response('', 503));
    await u.check();
    expect(u.required, isFalse);
  });

  test('een link die niet met https begint, wordt niet gebruikt', () async {
    final u = check('1.0.0', () async => http.Response('{"min_version":"2.0.0","desktop_url":"javascript:alert(1)","android_url":"http://x"}', 200));
    await u.check();
    expect(u.updateUrl, startsWith('https://github.com/Tanatloc/macromatrix-releases'));
  });

  test('de instelling blijft lokaal (wordt niet gesynchroniseerd)', () async {
    await check('1.0.0', () async => http.Response('{"min_version":"1.0.0"}', 200)).check();
    expect(db.setting('_update_check'), isNotNull);
    expect([for (final t in UserDb.syncTables) ...db.dirtyRows(t)].where((r) => r['key'] == '_update_check'), isEmpty);
  });

  test('de website heeft een geldig app-version.json, dat de huidige versie niet blokkeert', () async {
    final body = await File('site/app-version.json').readAsString();
    // De versie van deze build mag nooit geblokkeerd zijn (anders blokkeert de nieuwe release zichzelf)
    final u = check(appVersion, () async => http.Response(body, 200));
    await u.check();
    expect(u.minVersion, isNotNull);
    expect(u.required, isFalse);
  });
}
