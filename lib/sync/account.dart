/// Account en synchronisatie via Supabase.
///
/// Een account is verplicht zodra de app met Supabase gebouwd is: e-mail en wachtwoord, bevestigd met een code
/// per e-mail (geen links: werkt zo op gsm, pc en web zonder extra koppelingen). Wachtwoord vergeten gaat ook met
/// een code. De verbinding komt uit `--dart-define-from-file=supabase.json` (SUPABASE_URL en SUPABASE_ANON_KEY);
/// zonder die waarden werkt de app lokaal, zonder account.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase/supabase.dart';

import '../data/user_db.dart';
import 'sync_engine.dart';
import '../i18n.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

enum SyncStatus { idle, syncing, error, offline }

/// Supabase als [SyncRemote]: elke tabel heeft dezelfde kolommen als lokaal, plus user_id en server_ts.
class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.client, this.userId);
  final SupabaseClient client;
  final String userId;

  @override
  Future<void> push(SyncTable table, List<Map<String, Object?>> rows) => client.from(table.name).upsert([
    for (final r in rows) {...r, 'user_id': userId},
  ], onConflict: 'user_id,${table.key}');

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    var q = client.from(table.name).select();
    if (since != null) q = q.gt('server_ts', since);
    final rows = await q.order('server_ts', ascending: true).limit(limit);
    return [for (final r in rows) r.cast<String, Object?>()];
  }
}

class Account extends ChangeNotifier {
  Account(this.db, {required this.onRemoteChanges});

  final UserDb db;

  /// Wordt opgeroepen als er wijzigingen van een ander toestel binnenkwamen (de app herlaadt dan).
  final VoidCallback onRemoteChanges;

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Bewust zonder account: alles blijft op dit toestel. Maak je later toch een account, dan gaan de lokale
  /// gegevens mee (ze staan nog als "niet verstuurd").
  bool get localOnly => db.setting('_local_only')?['on'] == true;

  void setLocalOnly(bool on) {
    db.setSetting('_local_only', {'on': on});
    notifyListeners();
  }

  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _dbSub;
  Timer? _debounce;
  Timer? _periodic;
  Timer? _remoteDebounce;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;

  /// Na het versturen even niet reageren op de live meldingen: dat zijn onze eigen wijzigingen.
  DateTime _quietUntil = DateTime(0);

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;
  String? _error;
  String? get error => _error;
  bool _again = false;

  /// Klaar met opstarten (een bewaarde sessie is hersteld of er is er geen).
  bool _ready = !configured;
  bool get ready => _ready;

  /// De verbonden Supabase-client (null zonder configuratie).
  SupabaseClient? get client => _client;

  User? get user => _client?.auth.currentUser;
  bool get signedIn => user != null;
  String? get email => user?.email;

  /// Laatste geslaagde synchronisatie.
  DateTime? get lastSync {
    final u = user;
    if (u == null) return null;
    final ms = SyncEngine(db, SupabaseRemote(_client!, u.id), userId: u.id).lastSync;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> init() async {
    if (!configured) return;
    final client = _client = SupabaseClient(supabaseUrl, supabaseAnonKey, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    _authSub = client.auth.onAuthStateChange.listen((s) {
      final session = s.session;
      if (session != null) {
        db.setSetting('_session', {'json': jsonEncode(session.toJson())});
      }
      notifyListeners();
    });
    var saved = db.setting('_session')?['json'] as String?;
    // Alleen een echte sessie (met een token waarvan de vervaldatum leesbaar is) herstellen
    if (saved != null && !_validSession(saved)) {
      db.setSetting('_session', {});
      saved = null;
    }
    if (saved != null) {
      try {
        await client.auth.recoverSession(saved);
      } on AuthException catch (e) {
        // Sessie verlopen of ingetrokken: opnieuw inloggen nodig. Zonder internet blijft de oude sessie bruikbaar.
        if (e.statusCode == '400' || e.statusCode == '401') db.setSetting('_session', {});
      } catch (_) {
        // Geen internet: met de bewaarde sessie verder, zodat de app offline blijft werken. Het token wordt
        // vernieuwd zodra er weer verbinding is.
        _status = SyncStatus.offline;
        try {
          await client.auth.setInitialSession(saved);
        } catch (_) {}
      }
    }
    _dbSub = db.changes.listen((_) => schedule());
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => sync());
    // Terug naar de app (of het tabblad): meteen bijwerken
    try {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(sync()));
    } catch (_) {
      // Zonder Flutter-binding (tests): niet nodig
    }
    _ready = true;
    notifyListeners();
    if (signedIn) {
      _watchRemote();
      unawaited(sync());
    }
  }

  static bool _validSession(String json) {
    try {
      return Session.fromJson(jsonDecode(json) as Map<String, dynamic>)?.expiresAt != null;
    } catch (_) {
      return false;
    }
  }

  /// Versie van de voorwaarden en het privacybeleid die je aanvaardt bij het registreren.
  static const termsVersion = '2026-10-17';

  /// Registreren. Supabase stuurt een code om het e-mailadres te bevestigen. Geeft false als er al een
  /// (bevestigd) account met dit adres bestaat: Supabase verraadt dat niet als fout, maar zonder "identities".
  Future<bool> signUp(String email, String password) async {
    final r = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'terms_version': termsVersion, 'terms_accepted_at': DateTime.now().toUtc().toIso8601String()},
    );
    return r.user?.identities?.isNotEmpty ?? true;
  }

  /// De bevestigingscode uit de mail controleren; daarna ben je ingelogd en wordt alles gesynchroniseerd.
  Future<void> confirmSignUp(String email, String code) async {
    await _client!.auth.verifyOTP(type: OtpType.signup, email: email.trim(), token: code.trim());
    await _afterLogin();
  }

  /// De bevestigingscode opnieuw sturen.
  Future<void> resendConfirmation(String email) => _client!.auth.resend(type: OtpType.signup, email: email.trim());

  Future<void> signIn(String email, String password) async {
    await _client!.auth.signInWithPassword(email: email.trim(), password: password);
    await _afterLogin();
  }

  /// Wachtwoord vergeten, stap 1: een code mailen.
  Future<void> requestPasswordReset(String email) => _client!.auth.resetPasswordForEmail(email.trim());

  /// Wachtwoord vergeten, stap 2: code controleren en het nieuwe wachtwoord instellen (je bent dan ingelogd).
  Future<void> resetPassword(String email, String code, String newPassword) async {
    await _client!.auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim());
    await _client!.auth.updateUser(UserAttributes(password: newPassword));
    await _afterLogin();
  }

  Future<void> changePassword(String newPassword) => _client!.auth.updateUser(UserAttributes(password: newPassword));

  /// Na het inloggen eerst alles ophalen, zodat bv. je profiel er meteen is op een nieuw toestel.
  Future<void> _afterLogin() async {
    // Een ander account dan de vorige keer op dit toestel: de oude gegevens horen daar niet bij
    final previous = db.setting('_sync')?['user'];
    if (previous != null && previous != user?.id) {
      db.wipeUserData();
      onRemoteChanges();
    }
    notifyListeners();
    _watchRemote();
    await sync();
  }

  /// Live meldingen van de server: zodra een ander toestel iets wijzigt, haalt dit toestel het meteen op.
  void _watchRemote() {
    final u = user;
    if (u == null || _channel != null) return;
    var channel = _client!.channel('wijzigingen-${u.id}');
    for (final t in UserDb.syncTables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t.name,
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u.id),
        callback: (_) => _remoteChanged(),
      );
    }
    _channel = channel..subscribe();
  }

  void _stopWatching() {
    final c = _channel;
    _channel = null;
    if (c != null) unawaited(_client!.removeChannel(c));
  }

  void _remoteChanged() {
    if (_status == SyncStatus.syncing || DateTime.now().isBefore(_quietUntil)) return;
    _remoteDebounce?.cancel();
    _remoteDebounce = Timer(const Duration(milliseconds: 1500), () => unawaited(sync()));
  }

  /// Na een korte pauze synchroniseren (na wijzigingen), zodat niet elke tik een verzoek wordt.
  void schedule() {
    if (!signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      if (db.hasDirtyRows) sync();
    });
  }

  Future<void> sync() async {
    final u = user;
    if (u == null) return;
    if (_status == SyncStatus.syncing) {
      _again = true;
      return;
    }
    _status = SyncStatus.syncing;
    _error = null;
    notifyListeners();
    try {
      final result = await SyncEngine(db, SupabaseRemote(_client!, u.id), userId: u.id).run();
      if (result.pushed > 0) _quietUntil = DateTime.now().add(const Duration(seconds: 3));
      _status = SyncStatus.idle;
      if (result.pulled > 0) onRemoteChanges();
    } on AuthException catch (e) {
      _status = SyncStatus.error;
      _error = tr('Your session has expired. Please log in again. (${e.message})', 'Je sessie is verlopen. Log opnieuw in. (${e.message})');
    } on PostgrestException catch (e) {
      _status = SyncStatus.error;
      _error = tr('The server rejected the data: ${e.message}', 'De server weigerde de gegevens: ${e.message}');
    } catch (e) {
      // Meestal geen internet: later opnieuw, er gaat niets verloren
      _status = SyncStatus.offline;
      _error = null;
    }
    notifyListeners();
    if (_again) {
      _again = false;
      unawaited(sync());
    }
  }

  /// Uitloggen: eerst alles versturen, dan de gegevens van dit toestel wissen (ze staan veilig op de server).
  /// Geeft false als er nog niet-verstuurde wijzigingen zijn en [force] niet gezet is.
  Future<bool> signOut({bool force = false}) async {
    if (!signedIn) return true;
    await sync();
    if (db.hasDirtyRows && !force) return false;
    _stopWatching();
    // Geen battle-meldingen meer naar dit toestel
    final notify = db.setting('_notify')?['token'];
    if (notify != null) {
      try {
        await _client!.rpc('notify_unregister', params: {'p_token': notify});
      } catch (_) {}
      db.deleteSetting('_notify');
    }
    try {
      await _client!.auth.signOut();
    } catch (_) {
      // Ook zonder internet lokaal uitloggen
    }
    db.wipeUserData();
    db.setSetting('_session', {});
    onRemoteChanges();
    notifyListeners();
    return true;
  }

  /// Account en alle gegevens op de server verwijderen, en daarna ook op dit toestel.
  Future<void> deleteAccount() async {
    await _client!.rpc('delete_account');
    _stopWatching();
    db.deleteSetting('_notify');
    try {
      await _client!.auth.signOut();
    } catch (_) {}
    db.wipeUserData();
    db.setSetting('_session', {});
    onRemoteChanges();
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _dbSub?.cancel();
    _debounce?.cancel();
    _periodic?.cancel();
    _remoteDebounce?.cancel();
    _lifecycle?.dispose();
    _stopWatching();
    _client?.dispose();
    super.dispose();
  }
}
