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
import 'cloudflare_auth.dart';
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

  /// Met [insertOnly]: "on conflict do nothing". De server geeft terug wat hij echt opsloeg: een oudere versie laat de
  /// trigger vallen, en de tijd kan begrensd zijn (supabase/migrations/20261107100000_sync_safety.sql).
  @override
  Future<Map<String, int>?> push(SyncTable table, List<Map<String, Object?>> rows, {bool insertOnly = false}) async {
    final saved = await client
        .from(table.name)
        .upsert([for (final r in rows) {...r, 'user_id': userId}], onConflict: 'user_id,${table.key}', ignoreDuplicates: insertOnly)
        .select('${table.key}, updated_at');
    return {for (final r in saved) '${r[table.key]}': (r['updated_at'] as num).toInt()};
  }

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    var q = client.from(table.name).select();
    if (since != null) q = q.gt('server_ts', since);
    final rows = await q.order('server_ts', ascending: true).limit(limit);
    return [for (final r in rows) r.cast<String, Object?>()];
  }

  @override
  Future<List<Map<String, Object?>>> fetch(SyncTable table, List<String> keys) async {
    final out = <Map<String, Object?>>[];
    // In stukken: de sleutels staan in de URL
    for (var i = 0; i < keys.length; i += 100) {
      final part = keys.sublist(i, i + 100 > keys.length ? keys.length : i + 100);
      final rows = await client.from(table.name).select().eq('user_id', userId).inFilter(table.key, part);
      out.addAll([for (final r in rows) r.cast<String, Object?>()]);
    }
    return out;
  }

  @override
  SyncErrorKind classify(Object error) => classifyError(error);

  /// SQLSTATE 22… (ongeldige waarde, bv. te lang), 23… (een regel geschonden, bv. de grootte) en 54… (te veel rijen):
  /// het ligt aan een rij. Sessie (PGRST3…) of geen antwoord van de database (HTTP-status als code): later opnieuw.
  /// De rest (bv. een kolom die op de server nog ontbreekt): alleen die tabel.
  static SyncErrorKind classifyError(Object error) {
    if (error is! PostgrestException) return SyncErrorKind.fatal;
    final code = error.code ?? '';
    if (code == '23503') return SyncErrorKind.table; // verwijzing: het account zelf bestaat niet (meer)
    if (code.length == 5 && (code.startsWith('22') || code.startsWith('23') || code.startsWith('54'))) return SyncErrorKind.row;
    if (code.isEmpty || code.startsWith('PGRST3') || RegExp(r'^\d{3}$').hasMatch(code)) return SyncErrorKind.fatal;
    return SyncErrorKind.table;
  }
}

class Account extends ChangeNotifier {
  Account(this.db, {required this.onRemoteChanges});

  final UserDb db;

  /// Wordt opgeroepen als er wijzigingen van een ander toestel binnenkwamen (de app herlaadt dan).
  final VoidCallback onRemoteChanges;

  static bool get configured => usesOwnServer || (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty);

  /// Gebouwd met `API_URL`: inloggen bij de eigen server (Cloudflare) in plaats van Supabase. Synchroniseren kan
  /// daar nog niet (komt in fase 3 van de overstap); tot dan blijft alles op het toestel.
  static bool get usesOwnServer => apiUrl.isNotEmpty;

  /// Bewust zonder account: alles blijft op dit toestel. Maak je later toch een account, dan gaan de lokale
  /// gegevens mee (ze staan nog als "niet verstuurd").
  bool get localOnly => db.setting('_local_only')?['on'] == true;

  void setLocalOnly(bool on) {
    db.setSetting('_local_only', {'on': on});
    notifyListeners();
  }

  /// Je registreerde, maar vulde de code uit de mail nog niet in: dat e-mailadres, zodat het welkomscherm aanbiedt om
  /// de bevestiging af te maken (NW-6). Hoogstens een week; weg na het bevestigen of inloggen.
  String? get pendingConfirmation {
    final p = db.setting('_pending_confirm');
    final at = p?['at'] as int?;
    if (p?['email'] is! String || at == null) return null;
    return DateTime.now().millisecondsSinceEpoch - at < const Duration(days: 7).inMilliseconds ? p!['email'] as String : null;
  }

  void setPendingConfirmation(String? email) {
    db.setSetting('_pending_confirm', email == null ? {} : {'email': email.trim(), 'at': DateTime.now().millisecondsSinceEpoch});
    notifyListeners();
  }

  /// Deze versie is te oud ([UpdateCheck.required]): niets meer versturen of ophalen. Wat je intussen wijzigt,
  /// blijft lokaal staan als "niet verstuurd" en gaat mee na de update.
  bool get paused => _paused;
  bool _paused = false;
  set paused(bool on) {
    if (on == _paused) return;
    _paused = on;
    if (!on) unawaited(sync());
  }

  SupabaseClient? _client;
  CloudflareAuth? _cf;
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

  /// De synchronisatie die nu loopt (uitloggen wacht erop).
  Future<void>? _running;

  /// Telt op bij uitloggen en account verwijderen: een synchronisatie van daarvoor schrijft dan niets meer.
  int _generation = 0;

  /// Bezig met uitloggen of verwijderen: geen nieuwe synchronisatie starten.
  bool _closing = false;

  /// Rijen die de server weigerde (bijgewerkt na elke synchronisatie).
  int _rejected = 0;

  /// Melding als de server iets weigerde: dat blijft op dit toestel (wijzig het om het opnieuw te proberen).
  String? get rejectedNotice => _rejected == 0
      ? null
      : tr(
          _rejected == 1
              ? '1 change could not be saved on the server (for example a note that is too long). It stays on this device; edit it to try again.'
              : '$_rejected changes could not be saved on the server (for example a note that is too long). They stay on this device; edit them to try again.',
          _rejected == 1
              ? '1 wijziging kon niet op de server bewaard worden (bv. een te lange notitie). Ze blijft op dit toestel; pas ze aan om het opnieuw te proberen.'
              : '$_rejected wijzigingen konden niet op de server bewaard worden (bv. een te lange notitie). Ze blijven op dit toestel; pas ze aan om het opnieuw te proberen.',
        );

  /// Klaar met opstarten (een bewaarde sessie is hersteld of er is er geen).
  bool _ready = !configured;
  bool get ready => _ready;

  /// De verbonden Supabase-client (null zonder configuratie).
  SupabaseClient? get client => _client;

  AccountUser? get user {
    if (_cf != null) return _cf!.user;
    final u = _client?.auth.currentUser;
    return u == null ? null : AccountUser(u.id, u.email);
  }

  /// Token voor onze eigen API's (AI, foto, Google Play): het Supabase-token of de sessie van de eigen server.
  String? get accessToken => _cf != null ? _cf!.token : _client?.auth.currentSession?.accessToken;

  /// Kan dit account synchroniseren? Bij de eigen server nog niet (fase 3).
  bool get canSync => _cf == null;

  /// Bij de eigen server vraagt een nieuw wachtwoord ook het huidige.
  bool get needsCurrentPassword => _cf != null;
  bool get signedIn => user != null;
  String? get email => user?.email;

  /// Laatste geslaagde synchronisatie.
  DateTime? get lastSync {
    final u = user;
    if (u == null || _client == null) return null;
    final ms = SyncEngine(db, SupabaseRemote(_client!, u.id), userId: u.id).lastSync;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Ingelogd, maar voor dit account kwam er nog nooit iets van de server binnen (bv. de eerste synchronisatie
  /// mislukte). Je profiel kan dan nog op de server staan: de app toont geen "Over jou" maar wacht (of laat opnieuw
  /// proberen), zodat je je echte profiel niet overschrijft.
  bool get needsFirstSync => signedIn && canSync && lastSync == null;

  // ── Van wie zijn de gegevens op dit toestel? ──

  /// Het account waarvan de gegevens op dit toestel zijn (laatst ingelogd of gesynchroniseerd), of null: van
  /// niemand (zonder account gebruikt, of na uitloggen gewist).
  String? get _ownerId => db.setting('_owner')?['id'] as String? ?? db.setting('_sync')?['user'] as String?;

  void _setOwner(AccountUser u) => db.setSetting('_owner', {'id': u.id, 'email': u.email});

  /// Ingelogd met een ander account dan dat van de gegevens op dit toestel, terwijl er daarvan nog iets niet op de
  /// server staat: eerst kiezen wat ermee gebeurt (zie [discardOtherAccountData] en [switchToOtherAccount]). Tot dan
  /// synchroniseert de app niets: die gegevens mogen nooit in dit account terechtkomen.
  bool get otherAccountData => signedIn && _otherPending;
  bool _otherPending = false;

  /// E-mailadres van het account van die gegevens (als het bekend is).
  String? get otherAccountEmail => otherAccountData ? (db.setting('_owner')?['email'] as String?) : null;

  /// De gegevens van het andere account wissen en verder met dit account.
  Future<void> discardOtherAccountData() async {
    final u = user;
    if (u == null) return;
    db.wipeUserData();
    _setOwner(u);
    _otherPending = false;
    onRemoteChanges();
    notifyListeners();
    _watchRemote();
    await sync();
  }

  /// Toch met het andere account verder: dit account uitloggen zonder iets te wissen, zodat je met dat account kunt
  /// inloggen (de gegevens gaan dan gewoon naar dat account).
  Future<void> switchToOtherAccount() async {
    _stopWatching();
    try {
      await _authSignOut();
    } catch (_) {}
    db.setSetting('_session', {});
    _otherPending = false;
    notifyListeners();
  }

  /// Na het inloggen (en bij het opstarten): horen de gegevens op dit toestel bij dit account? False: ze zijn van
  /// een ander account en nog niet allemaal verstuurd, dan eerst vragen ([otherAccountData]).
  bool _claimData(AccountUser u, {bool newAccount = false, bool atStart = false}) {
    final owner = _ownerId;
    if (owner == u.id) return true;
    if (owner != null) {
      // Een ander account dan de vorige keer op dit toestel: de oude gegevens horen daar niet bij
      if (db.hasUnsentRows) {
        _otherPending = true;
        return false;
      }
      db.wipeUserData();
      onRemoteChanges();
    } else if (newAccount) {
      // Een nieuw account: wat hier staat (ook het profiel) is van dat account
      db.claimUnsentSettings();
    } else if (!atStart) {
      // Nog nooit gesynchroniseerd (meestal: eerst zonder account gebruikt). Alles van hier gaat mee naar het
      // account, maar een bestaand profiel in het account wordt niet overschreven door dat van dit toestel.
      db.yieldUnsentSettings();
    }
    _setOwner(u);
    return true;
  }

  /// Voor tests: een client met een (lokale) sessie en een nagebootste server, zonder live meldingen.
  SyncRemote Function(String userId)? _debugRemote;

  @visibleForTesting
  void debugConnect(SupabaseClient client, SyncRemote Function(String userId) remote) {
    _client = client;
    _debugRemote = remote;
    _ready = true;
  }

  @visibleForTesting
  Future<void> debugAfterLogin({bool newAccount = false}) => _afterLogin(newAccount: newAccount);

  /// Uitloggen bij de server waar je ingelogd bent (Supabase of de eigen server).
  Future<void> _authSignOut() async {
    if (_cf != null) return _cf!.signOut();
    await _client?.auth.signOut();
  }

  Future<void> init() async {
    if (!configured) return;
    if (usesOwnServer) {
      final cf = _cf = CloudflareAuth(db);
      await cf.restore();
      _ready = true;
      final u = user;
      if (u != null) _claimData(u, atStart: true);
      notifyListeners();
      return;
    }
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
    final u = user;
    // Ook bij het opstarten: gegevens van een ander account gaan nooit mee (bv. de app werd gesloten tijdens de vraag)
    if (u != null && !_claimData(u, atStart: true)) {
      notifyListeners();
      return;
    }
    _rejected = db.rejectedCount;
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
    // De eigen server zegt nooit of een adres al een account heeft: die persoon krijgt een mail
    if (_cf != null) {
      await _cf!.signUp(email.trim(), password, termsVersion: termsVersion);
      return true;
    }
    final r = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'terms_version': termsVersion, 'terms_accepted_at': DateTime.now().toUtc().toIso8601String()},
    );
    return r.user?.identities?.isNotEmpty ?? true;
  }

  /// De bevestigingscode uit de mail controleren; daarna ben je ingelogd en wordt alles gesynchroniseerd.
  Future<void> confirmSignUp(String email, String code) async {
    if (_cf != null) {
      await _cf!.verifyEmail(email.trim(), code.trim());
    } else {
      await _client!.auth.verifyOTP(type: OtpType.signup, email: email.trim(), token: code.trim());
    }
    await _afterLogin(newAccount: true);
  }

  /// De bevestigingscode opnieuw sturen.
  Future<void> resendConfirmation(String email) =>
      _cf?.resendConfirmation(email.trim()) ?? _client!.auth.resend(type: OtpType.signup, email: email.trim());

  /// Net ingelogd op een bestaand account en de eerste synchronisatie loopt nog: je profiel kan nog onderweg zijn.
  /// Zolang toont de app nog geen "Over jou" (dat flitste even voor het profiel binnenkwam, GP-11).
  bool get fetchingAfterLogin => _fetching;
  bool _fetching = false;

  Future<void> _existingLogin(Future<void> Function() auth) async {
    _fetching = true;
    try {
      await auth();
      await _afterLogin();
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) =>
      _existingLogin(() async {
        if (_cf != null) return _cf!.signIn(email.trim(), password);
        await _client!.auth.signInWithPassword(email: email.trim(), password: password);
      });

  /// Wachtwoord vergeten, stap 1: een code mailen.
  Future<void> requestPasswordReset(String email) => _cf?.requestPasswordReset(email.trim()) ?? _client!.auth.resetPasswordForEmail(email.trim());

  /// Wachtwoord vergeten, stap 2: code controleren en het nieuwe wachtwoord instellen (je bent dan ingelogd).
  Future<void> resetPassword(String email, String code, String newPassword) => _existingLogin(() async {
    if (_cf != null) return _cf!.resetPassword(email.trim(), code.trim(), newPassword);
    await _client!.auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim());
    await _client!.auth.updateUser(UserAttributes(password: newPassword));
  });

  /// [currentPassword]: alleen bij de eigen server nodig ([needsCurrentPassword]).
  Future<void> changePassword(String newPassword, {String? currentPassword}) async {
    if (_cf != null) return _cf!.changePassword(currentPassword ?? '', newPassword);
    await _client!.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Na het inloggen eerst alles ophalen, zodat bv. je profiel er meteen is op een nieuw toestel.
  /// [newAccount]: net geregistreerd en bevestigd; wat op dit toestel staat, is dan van dat account.
  Future<void> _afterLogin({bool newAccount = false}) async {
    if (pendingConfirmation != null) db.setSetting('_pending_confirm', {});
    final u = user;
    if (u == null) return;
    if (!_claimData(u, newAccount: newAccount)) {
      // Eerst kiezen wat er met de gegevens van het andere account gebeurt (zie [otherAccountData])
      notifyListeners();
      return;
    }
    notifyListeners();
    _watchRemote();
    await sync();
  }

  /// Live meldingen van de server: zodra een ander toestel iets wijzigt, haalt dit toestel het meteen op.
  void _watchRemote() {
    final u = user;
    if (u == null || !canSync || _channel != null || _debugRemote != null) return;
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
    if (!signedIn || _paused || !canSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      if (db.hasDirtyRows) sync();
    });
  }

  /// Synchroniseren. Loopt er al een, dan volgt er daarna nog een, en wacht dit op allebei.
  Future<void> sync() {
    final u = user;
    // Nooit gegevens van een ander account versturen (zie [otherAccountData])
    if (u == null || _paused || !canSync || _closing || _otherPending || _ownerId != u.id) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _running = _syncLoop(u.id, _generation);
    return run.whenComplete(() {
      if (!identical(_running, run)) return;
      _running = null;
      // Net na de laatste ronde nog een wijziging: die niet laten liggen tot de volgende keer
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    });
  }

  Future<void> _syncLoop(String uid, int generation) async {
    bool active() => generation == _generation && !_closing && user?.id == uid;
    do {
      _again = false;
      await _syncOnce(uid, active);
    } while (_again && active());
  }

  Future<void> _syncOnce(String uid, bool Function() active) async {
    _status = SyncStatus.syncing;
    _error = null;
    notifyListeners();
    try {
      final result = await SyncEngine(db, _debugRemote?.call(uid) ?? SupabaseRemote(_client!, uid), userId: uid, active: active).run();
      if (result.pushed > 0) _quietUntil = DateTime.now().add(const Duration(seconds: 3));
      if (result.rejected > 0 || _rejected > 0) _rejected = db.rejectedCount;
      if (result.errors.isEmpty) {
        _status = SyncStatus.idle;
      } else {
        // Andere tabellen zijn wel gelukt; deze volgende keer opnieuw
        _status = SyncStatus.error;
        final MapEntry(key: table, value: e) = result.errors.entries.first;
        final why = e is PostgrestException ? e.message : '$e';
        _error = tr('Not everything could be synced ($table): $why', 'Niet alles kon gesynchroniseerd worden ($table): $why');
      }
      if (result.pulled > 0) onRemoteChanges();
    } on SyncCancelled {
      // Uitgelogd of een ander account: niets meer melden
      _status = SyncStatus.idle;
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
  }

  /// Wachten tot een synchronisatie die nog loopt, gestopt is.
  Future<void> _settle() async {
    try {
      await _running;
    } catch (_) {}
  }

  /// Uitloggen: eerst alles versturen, dan de gegevens van dit toestel wissen (ze staan veilig op de server).
  /// Geeft false als er nog niet-verstuurde wijzigingen zijn en [force] niet gezet is.
  Future<bool> signOut({bool force = false}) async {
    if (!signedIn) return true;
    await sync();
    // Ook wat de server weigerde, staat alleen hier
    if (db.hasUnsentRows && !force) return false;
    // Een synchronisatie die nog loopt, schrijft niets meer (anders kwamen haar rijen na het wissen terug)
    _closing = true;
    _generation++;
    try {
      await _settle();
      await _signOutAndWipe();
    } finally {
      _closing = false;
    }
    return true;
  }

  Future<void> _signOutAndWipe() async {
    _stopWatching();
    // Geen battle-meldingen meer naar dit toestel
    final notify = db.setting('_notify')?['token'];
    if (notify != null && _client != null) {
      try {
        await _client!.rpc('notify_unregister', params: {'p_token': notify});
      } catch (_) {}
      db.deleteSetting('_notify');
    }
    try {
      await _authSignOut();
    } catch (_) {
      // Ook zonder internet lokaal uitloggen
    }
    db.wipeUserData();
    db.setSetting('_session', {});
    _otherPending = false;
    _rejected = 0;
    onRemoteChanges();
    notifyListeners();
  }

  /// Account en alle gegevens op de server verwijderen, en daarna ook op dit toestel.
  Future<void> deleteAccount() async {
    // Eerst een lopende synchronisatie stoppen: die zou anders na het verwijderen nog rijen versturen of schrijven
    _closing = true;
    _generation++;
    try {
      await _settle();
      if (_client == null) throw const AuthException('Deleting an account is not available on this server yet', code: 'not_available');
      await _client!.rpc('delete_account');
      _stopWatching();
      db.deleteSetting('_notify');
      try {
        await _authSignOut();
      } catch (_) {}
      db.wipeUserData();
      db.setSetting('_session', {});
      _otherPending = false;
      _rejected = 0;
      onRemoteChanges();
      notifyListeners();
    } finally {
      _closing = false;
    }
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
