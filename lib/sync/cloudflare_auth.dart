import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' show AuthException;

import '../data/user_db.dart';

/// Adres van de eigen server (Cloudflare Worker, server/ in deze repo). Leeg: de app gebruikt Supabase.
const apiUrl = String.fromEnvironment('API_URL');

/// Ingelogde gebruiker, los van Supabase of de eigen server.
class AccountUser {
  const AccountUser(this.id, this.email);
  final String id;
  final String? email;
}

/// Inloggen bij de eigen server (Better Auth, server/src/auth.js). Sessie = Bearer-token, bewaard in de lokale
/// instelling `_cf_session` (niet gesynchroniseerd). Fouten komen als [AuthException] met dezelfde codes als bij
/// Supabase, zodat de schermen (authMessage) niets merken.
class CloudflareAuth {
  CloudflareAuth(this.db, {String? base, http.Client? client}) : base = Uri.parse(base ?? apiUrl), _http = client ?? http.Client() {
    final saved = db.setting(_key);
    final u = saved?['user'] as Map?;
    if (saved?['token'] is String && u?['id'] is String) {
      _token = saved!['token'] as String;
      _user = AccountUser(u!['id'] as String, u['email'] as String?);
    }
  }

  final UserDb db;
  final Uri base;
  final http.Client _http;

  static const _key = '_cf_session';

  String? _token;
  AccountUser? _user;

  AccountUser? get user => _user;
  String? get token => _token;

  /// Bij het opstarten: is de bewaarde sessie nog geldig? Zonder internet blijft ze staan (offline werken).
  Future<void> restore() async {
    if (_token == null) return;
    try {
      final r = await _call('GET', '/get-session');
      final u = (r.data as Map?)?['user'] as Map?;
      if (u == null) {
        _clear();
      } else {
        _setSession(_token!, u);
      }
    } on AuthException catch (e) {
      if (e.statusCode == '401') _clear();
    } catch (_) {
      // Geen internet: verder met de bewaarde sessie
    }
  }

  Future<void> signUp(String email, String password, {String? termsVersion}) =>
      _call('POST', '/sign-up/email', {'email': email, 'password': password, 'name': '', 'termsVersion': ?termsVersion});

  /// De code uit de mail; daarna ben je ingelogd.
  Future<void> verifyEmail(String email, String code) async {
    final r = await _call('POST', '/email-otp/verify-email', {'email': email, 'otp': code});
    _fromLogin(r);
  }

  Future<void> resendConfirmation(String email) => _call('POST', '/email-otp/send-verification-otp', {'email': email, 'type': 'email-verification'});

  Future<void> signIn(String email, String password) async {
    final r = await _call('POST', '/sign-in/email', {'email': email, 'password': password});
    _fromLogin(r);
  }

  Future<void> requestPasswordReset(String email) => _call('POST', '/email-otp/request-password-reset', {'email': email});

  /// Nieuw wachtwoord met de code uit de mail. De server logt dan alle toestellen uit; hier meteen opnieuw inloggen.
  Future<void> resetPassword(String email, String code, String newPassword) async {
    await _call('POST', '/email-otp/reset-password', {'email': email, 'otp': code, 'password': newPassword});
    await signIn(email, newPassword);
  }

  Future<void> changePassword(String currentPassword, String newPassword) =>
      _call('POST', '/change-password', {'currentPassword': currentPassword, 'newPassword': newPassword});

  /// Uitloggen op dit toestel; zonder internet alleen lokaal.
  Future<void> signOut() async {
    try {
      if (_token != null) await _call('POST', '/sign-out', {});
    } catch (_) {}
    _clear();
  }

  void _fromLogin(_Reply r) {
    final token = r.token ?? (r.data as Map?)?['token'] as String?;
    final u = (r.data as Map?)?['user'] as Map?;
    if (token == null || u == null) throw const AuthException('No session in the reply', code: 'unexpected');
    _setSession(token, u);
  }

  void _setSession(String token, Map u) {
    _token = token;
    _user = AccountUser(u['id'] as String, u['email'] as String?);
    db.setSetting(_key, {
      'token': token,
      'user': {'id': _user!.id, 'email': _user!.email},
    });
  }

  void _clear() {
    _token = null;
    _user = null;
    db.setSetting(_key, {});
  }

  Future<_Reply> _call(String method, String path, [Map<String, Object?>? body]) async {
    final uri = base.resolve('/auth$path');
    final headers = {'content-type': 'application/json', if (_token != null) 'authorization': 'Bearer $_token'};
    final res = method == 'GET'
        ? await _http.get(uri, headers: headers).timeout(const Duration(seconds: 20))
        : await _http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(const Duration(seconds: 20));
    Object? data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode >= 400) throw authError(res.statusCode, data);
    return _Reply(data, res.headers['set-auth-token']);
  }
}

class _Reply {
  const _Reply(this.data, this.token);
  final Object? data;
  final String? token;
}

/// Foutantwoord van Better Auth -> [AuthException] met de code die de app van Supabase kent.
AuthException authError(int status, Object? data) {
  final code = data is Map ? data['code'] as String? : null;
  final message = (data is Map ? data['message'] as String? : null) ?? 'HTTP $status';
  final mapped = switch (code) {
    'INVALID_EMAIL_OR_PASSWORD' => 'invalid_credentials',
    'INVALID_PASSWORD' => 'wrong_current_password',
    'EMAIL_NOT_VERIFIED' => 'email_not_confirmed',
    'WEAK_PASSWORD' || 'PASSWORD_TOO_SHORT' || 'PASSWORD_TOO_LONG' => 'weak_password',
    'INVALID_OTP' || 'OTP_EXPIRED' || 'TOO_MANY_ATTEMPTS' => 'otp_expired',
    'INVALID_EMAIL' => 'email_address_invalid',
    _ when status == 429 && code != 'SIGNUP_IP_LIMIT' => 'over_request_rate_limit',
    _ => code?.toLowerCase(),
  };
  return AuthException(message, statusCode: '$status', code: mapped);
}
