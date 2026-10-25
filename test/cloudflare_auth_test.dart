// Inloggen bij de eigen server (lib/sync/cloudflare_auth.dart) tegen een nagebootste Better Auth.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart' show AuthException;
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/cloudflare_auth.dart';

void main() {
  late UserDb db;
  late List<http.Request> sent;
  setUp(() {
    db = UserDb(sqlite3.openInMemory());
    sent = [];
  });

  CloudflareAuth auth(http.Response Function(http.Request r) reply) => CloudflareAuth(
    db,
    base: 'https://api.example.org',
    client: MockClient((r) async {
      sent.add(r);
      return reply(r);
    }),
  );
  http.Response ok(Object body, {String? token}) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json', 'set-auth-token': ?token});
  http.Response bad(int status, String code, [String message = 'x']) => http.Response(jsonEncode({'code': code, 'message': message}), status);
  const user = {'id': 'u-1', 'email': 'a@example.org', 'emailVerified': true};

  test('inloggen: token uit set-auth-token, bewaard over een herstart', () async {
    final a = auth((_) => ok({'user': user, 'token': 'ruw'}, token: 'getekend'));
    await a.signIn('a@example.org', 'geheim123');
    expect(sent.single.url.toString(), 'https://api.example.org/auth/sign-in/email');
    expect(jsonDecode(sent.single.body), {'email': 'a@example.org', 'password': 'geheim123'});
    expect(a.token, 'getekend');
    final again = CloudflareAuth(db, base: 'https://api.example.org');
    expect(again.user?.id, 'u-1');
    expect(again.token, 'getekend');
  });

  test('registreren stuurt de versie van de voorwaarden mee, geen sessie', () async {
    final a = auth((_) => ok({'user': user, 'token': null}));
    await a.signUp('a@example.org', 'geheim123', termsVersion: '2026-10-17');
    expect(jsonDecode(sent.single.body), {'email': 'a@example.org', 'password': 'geheim123', 'name': '', 'termsVersion': '2026-10-17'});
    expect(a.user, isNull);
  });

  test('code bevestigen logt in (token in de body als de header ontbreekt)', () async {
    final a = auth((_) => ok({'status': true, 'token': 'tok', 'user': user}));
    await a.verifyEmail('a@example.org', '123456');
    expect(a.token, 'tok');
    expect(a.user?.email, 'a@example.org');
  });

  test('herstart: verlopen sessie (geen user) wist de sessie; zonder internet blijft ze', () async {
    await auth((_) => ok({'user': user}, token: 't')).signIn('a@example.org', 'x');
    await auth((_) => throw http.ClientException('offline')).restore();
    expect(CloudflareAuth(db, base: 'https://x').token, 't');
    final expired = auth((_) => http.Response('null', 200));
    await expired.restore();
    expect(expired.user, isNull);
    expect(CloudflareAuth(db, base: 'https://x').token, isNull);
  });

  test('wachtwoord vergeten: nieuw wachtwoord en daarna opnieuw ingelogd', () async {
    final a = auth((r) => r.url.path.endsWith('/sign-in/email') ? ok({'user': user}, token: 'nieuw') : ok({'status': true}));
    await a.resetPassword('a@example.org', '654321', 'herstel2468');
    expect(sent.map((r) => r.url.path), ['/auth/email-otp/reset-password', '/auth/sign-in/email']);
    expect(a.token, 'nieuw');
  });

  test('uitloggen: ook zonder internet lokaal', () async {
    await auth((_) => ok({'user': user}, token: 't')).signIn('a@example.org', 'x');
    final a = auth((_) => throw http.ClientException('offline'));
    await a.signOut();
    expect(a.user, isNull);
    expect(CloudflareAuth(db, base: 'https://x').user, isNull);
  });

  test('de Bearer-token gaat mee na het inloggen', () async {
    final a = auth((_) => ok({'user': user}, token: 't'));
    await a.signIn('a@example.org', 'x');
    await a.changePassword('oud', 'nieuw123');
    expect(sent.last.headers['authorization'], 'Bearer t');
    expect(jsonDecode(sent.last.body), {'currentPassword': 'oud', 'newPassword': 'nieuw123'});
  });

  test('foutcodes zoals bij Supabase (voor authMessage)', () async {
    Future<AuthException> err(http.Response r) async {
      try {
        await auth((_) => r).signIn('a@example.org', 'x');
      } on AuthException catch (e) {
        return e;
      }
      throw StateError('geen fout');
    }

    expect((await err(bad(401, 'INVALID_EMAIL_OR_PASSWORD'))).code, 'invalid_credentials');
    expect((await err(bad(403, 'EMAIL_NOT_VERIFIED'))).code, 'email_not_confirmed');
    expect((await err(bad(400, 'WEAK_PASSWORD'))).code, 'weak_password');
    expect((await err(bad(400, 'INVALID_OTP'))).code, 'otp_expired');
    expect((await err(bad(403, 'TOO_MANY_ATTEMPTS'))).code, 'otp_expired');
    expect((await err(bad(400, 'INVALID_PASSWORD'))).code, 'wrong_current_password');
    expect((await err(http.Response('{"message":"Too many requests"}', 429))).code, 'over_request_rate_limit');
    final ip = await err(bad(429, 'SIGNUP_IP_LIMIT', 'Too many new accounts from this network. Try again later.'));
    expect(ip.message, contains('new accounts from this network'));
    expect(ip.statusCode, '429');
  });
}
