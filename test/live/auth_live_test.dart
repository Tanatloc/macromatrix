// Account-stappen tegen het echte project, via de klasse Account van de app. Alleen met:
//   flutter test --dart-define-from-file=supabase.json test/live/auth_live_test.dart
// en de omgevingsvariabelen LIVE_EMAIL, LIVE_PASSWORD, LIVE_SIGNUP_OTP, LIVE_RECOVERY_OTP (codes zonder mail
// gemaakt met de admin-API: generate_link type "signup" met wachtwoord, en type "recovery").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart';
import 'package:voedingsapp/data/user_db.dart';
import 'package:voedingsapp/sync/account.dart';

void main() {
  final env = Platform.environment;
  final skip = !Account.configured || (env['LIVE_SIGNUP_OTP'] ?? '').isEmpty ? 'geen live-gegevens' : null;

  test('bevestigen met code, inloggen, wachtwoord vergeten, uitloggen', skip: skip, () async {
    final email = env['LIVE_EMAIL']!, password = env['LIVE_PASSWORD']!;
    final db = UserDb(sqlite3.openInMemory());
    db.setSetting('profile', {'weightKg': 70});
    var reloads = 0;
    final a = Account(db, onRemoteChanges: () => reloads++);
    await a.init();
    expect(a.ready, isTrue);
    expect(a.signedIn, isFalse);

    // Bevestigen met de code uit de "mail": ingelogd, en wat al op het toestel stond gaat mee
    await a.confirmSignUp(email, env['LIVE_SIGNUP_OTP']!);
    expect(a.signedIn, isTrue);
    expect(a.email, email);
    expect(db.hasDirtyRows, isFalse);
    expect(db.setting('_session')?['json'], isNotNull);

    // Fout wachtwoord geeft een nette fout
    await a.signOut();
    expect(a.signedIn, isFalse);
    expect(db.setting('profile'), isNull, reason: 'uitloggen wist het toestel');
    await expectLater(a.signIn(email, 'fout-wachtwoord1'), throwsA(isA<AuthException>().having((e) => e.code, 'code', 'invalid_credentials')));

    // Inloggen met het juiste wachtwoord haalt alles terug
    await a.signIn(email, password);
    expect(a.signedIn, isTrue);
    expect(db.setting('profile')?['weightKg'], 70);
    expect(reloads, greaterThan(0));

    // Wachtwoord vergeten: code + nieuw wachtwoord, daarna inloggen met het nieuwe
    await a.signOut();
    await a.resetPassword(email, env['LIVE_RECOVERY_OTP']!, '${password}x9');
    expect(a.signedIn, isTrue);
    await a.signOut();
    await a.signIn(email, '${password}x9');
    expect(a.signedIn, isTrue);

    // Account verwijderen
    await a.deleteAccount();
    expect(a.signedIn, isFalse);
    a.dispose();
  });
}
