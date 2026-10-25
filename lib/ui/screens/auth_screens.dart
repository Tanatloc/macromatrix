/// Welkom, registreren, inloggen, wachtwoord vergeten en je profiel instellen. Als de app met Supabase gebouwd is,
/// kies je op het welkomscherm: een account, of bewust zonder account (ook in de browser); zie [AuthGate].
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase/supabase.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../../data/backup.dart';
import '../../data/export.dart';
import '../../nutrition/targets.dart';
import '../../platform/platform.dart' show askPersistentStorage, reloadApp, saveTextFile;
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../../sync/update_check.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/account_card.dart' show signOutAsking;
import '../widgets/activity_ask.dart';
import '../widgets/kit.dart';
import '../widgets/logo.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';

const siteUrl = 'https://macromatrix.eu';

/// Een pagina van de website openen: op het web in een nieuw tabblad (behalve de homepage), anders in de browser.
Future<void> openPage(String path) => launchUrl(
  Uri.parse(kIsWeb ? path : '$siteUrl$path'),
  webOnlyWindowName: kIsWeb ? (path == '/' ? '_self' : '_blank') : null,
  mode: LaunchMode.externalApplication,
);

/// Draait dit in de browser? kIsWeb is een constante; tests zetten [debugWebOverride] om het webpad na te bootsen.
@visibleForTesting
bool? debugWebOverride;
bool get runsOnWeb => debugWebOverride ?? kIsWeb;

/// "Meer over de app": in de app de homepage zonder downloadknoppen (/about/, zie tool/build_site.sh). Een app uit
/// Google Play wijst niet naar een APK buiten de Play Store (GP-18). Op het web gewoon de homepage.
String get aboutPagePath => runsOnWeb ? '/' : '/about/';

enum GateScreen { updateRequired, loading, welcome, otherAccount, firstSync, profileSetup, app }

/// Wat [AuthGate] toont. Zonder account (bewust gekozen) kom je overal in de app, ook in de browser: je gegevens
/// staan dan in de opslag van de browser (IndexedDB, zie platform_web.dart).
/// [fetching]: net ingelogd op een bestaand account, het profiel kan nog onderweg zijn (GP-11).
/// [otherAccount]: op dit toestel staan nog niet-verstuurde gegevens van een ander account ([Account.otherAccountData]).
/// [firstSync]: ingelogd, maar nog nooit iets van de server opgehaald ([Account.needsFirstSync]). Zonder profiel dan
/// geen "Over jou" (dat zou je echte profiel overschrijven), maar wachten of opnieuw proberen.
/// [updateRequired]: deze versie is te oud ([UpdateCheck.required]); gaat voor alles.
GateScreen gateScreen({
  required bool ready,
  required bool configured,
  required bool signedIn,
  required bool localOnly,
  required bool hasProfile,
  bool fetching = false,
  bool otherAccount = false,
  bool firstSync = false,
  bool updateRequired = false,
}) {
  if (updateRequired) return GateScreen.updateRequired;
  if (!ready) return GateScreen.loading;
  if (configured && !signedIn && !localOnly) return GateScreen.welcome;
  if (configured && signedIn && otherAccount) return GateScreen.otherAccount;
  if (configured && !hasProfile && fetching) return GateScreen.loading;
  if (configured && !hasProfile && signedIn && firstSync) return GateScreen.firstSync;
  if (configured && !hasProfile) return GateScreen.profileSetup;
  return GateScreen.app;
}

/// Kiest wat je ziet: opstarten, welkom (niet ingelogd), profiel instellen (nieuw account) of de app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Account>();
    final s = context.watch<AppState>();
    final update = context.watch<UpdateCheck?>();
    return switch (gateScreen(
      updateRequired: update?.required ?? false,
      ready: a.ready,
      configured: Account.configured,
      signedIn: a.signedIn,
      localOnly: a.localOnly,
      hasProfile: s.hasProfile,
      fetching: a.fetchingAfterLogin,
      otherAccount: a.otherAccountData,
      firstSync: a.needsFirstSync,
    )) {
      GateScreen.updateRequired => UpdateRequiredScreen(url: update!.updateUrl),
      GateScreen.loading => Scaffold(backgroundColor: context.pal.bg, body: const SizedBox.expand()),
      GateScreen.welcome => const WelcomeScreen(),
      GateScreen.otherAccount => const OtherAccountScreen(),
      GateScreen.firstSync => const FirstSyncScreen(),
      GateScreen.profileSetup => const ProfileSetupScreen(),
      GateScreen.app => const Shell(),
    };
  }
}

/// Eenvoudig scherm in het midden, voor [FirstSyncScreen] en [OtherAccountScreen].
class _GateMessage extends StatelessWidget {
  const _GateMessage({super.key, required this.icon, required this.title, required this.text, this.busy = false, this.children = const []});
  final IconData icon;
  final String title, text;
  final bool busy;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: busy
                        ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator())
                        : Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(16)),
                            child: Icon(icon, size: 28, color: p.brand),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 10),
                  Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: p.ink2)),
                  if (children.isNotEmpty) const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ingelogd, maar je gegevens kwamen nog niet binnen (de eerste synchronisatie loopt nog of mislukte). Geen "Over
/// jou": wie dat opnieuw invult, overschrijft zijn echte profiel.
class FirstSyncScreen extends StatelessWidget {
  const FirstSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Account>();
    if (a.status == SyncStatus.syncing) {
      return _GateMessage(
        icon: Icons.cloud_download_outlined,
        busy: true,
        title: tr('Fetching your data…', 'Je gegevens ophalen…'),
        text: tr('This only takes a moment.', 'Even geduld.'),
      );
    }
    return _GateMessage(
      key: const ValueKey('first-sync-failed'),
      icon: Icons.cloud_off_outlined,
      title: tr('Your data has not arrived yet', 'Je gegevens zijn nog niet binnen'),
      text: [
        tr(
          'We could not fetch your profile and diary from your account yet. Check your internet connection and try again.',
          'We konden je profiel en dagboek nog niet uit je account ophalen. Controleer je internetverbinding en probeer opnieuw.',
        ),
        ?a.error,
      ].join('\n\n'),
      children: [
        FilledButton(onPressed: a.sync, child: Text(tr('Try again', 'Opnieuw proberen'))),
        const SizedBox(height: 8),
        TextButton(onPressed: () => signOutAsking(context, a), child: Text(tr('Log out', 'Uitloggen'))),
      ],
    );
  }
}

/// Deze versie is te oud ([UpdateCheck]). Je gegevens blijven op dit toestel staan en gaan na de update mee.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return _GateMessage(
      key: const ValueKey('update-required'),
      icon: Icons.system_update_outlined,
      title: tr('Please update MacroMatrix', 'Werk MacroMatrix bij'),
      text: tr(
        'This version no longer works with our server. Your data is safe on this device and will sync again after the update.',
        'Deze versie werkt niet meer met onze server. Je gegevens staan veilig op dit toestel en worden na de update weer gesynchroniseerd.',
      ),
      children: [
        FilledButton(
          onPressed: runsOnWeb ? reloadApp : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(runsOnWeb ? tr('Reload', 'Herladen') : tr('Get the new version', 'Nieuwe versie downloaden')),
        ),
      ],
    );
  }
}

/// Op dit toestel staan nog gegevens van een ander account die niet (allemaal) op de server staan. Die gaan nooit
/// naar het account waarmee je nu inlogde: eerst kiezen.
class OtherAccountScreen extends StatefulWidget {
  const OtherAccountScreen({super.key});

  @override
  State<OtherAccountScreen> createState() => _OtherAccountScreenState();
}

class _OtherAccountScreenState extends State<OtherAccountScreen> {
  bool _busy = false;

  Future<void> _save(String name, String content, String mime) async {
    final message = await saveTextFile(name, content, mime: mime);
    if (message != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _discard(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete that data?', 'Die gegevens wissen?')),
        content: Text(
          tr(
            'What was not sent yet is lost for good. Export it first if you want to keep it.',
            'Wat nog niet verstuurd was, ben je dan voorgoed kwijt. Exporteer het eerst als je het wilt houden.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.pal.high),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete', 'Wissen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await a.discardOtherAccountData();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Account>();
    final s = context.read<AppState>();
    final other = a.otherAccountEmail;
    final today = dayKey(DateTime.now());
    return _GateMessage(
      key: const ValueKey('other-account'),
      icon: Icons.switch_account_outlined,
      title: tr('This device has data from another account', 'Op dit toestel staan gegevens van een ander account'),
      text: tr(
        'Some changes from ${other ?? 'another account'} were never sent to that account. They will not be added to '
            '${a.email ?? 'this account'}. What would you like to do?',
        'Sommige wijzigingen van ${other ?? 'een ander account'} werden nooit naar dat account verstuurd. Ze komen niet in '
            '${a.email ?? 'dit account'}. Wat wil je doen?',
      ),
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _save('macromatrix-diary-$today.csv', diaryCsv(s.user, values: s.entryValues), 'text/csv'),
          icon: const Icon(Icons.download_rounded),
          label: Text(tr('Export diary (CSV)', 'Dagboek exporteren (CSV)')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _save('macromatrix-backup-$today.json', backupJson(s.user), 'application/json'),
          icon: const Icon(Icons.save_alt_rounded),
          label: Text(tr('Save a full backup', 'Volledige back-up bewaren')),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : a.switchToOtherAccount,
          child: Text(
            other == null
                ? tr('Log in with that account instead', 'Toch met dat account inloggen')
                : tr('Log in as $other instead', 'Toch inloggen als $other'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.pal.high),
          onPressed: _busy ? null : () => _discard(a),
          child: Text(tr('Delete that data and continue', 'Die gegevens wissen en verder')),
        ),
      ],
    );
  }
}

/// Wachtwoordregels, gelijk aan die in Supabase: minstens 8 tekens, met letters en cijfers.
String? passwordProblem(String p) {
  if (p.length < 8) return tr('At least 8 characters.', 'Minstens 8 tekens.');
  if (!RegExp('[A-Za-z]').hasMatch(p) || !RegExp('[0-9]').hasMatch(p)) return tr('Use letters and numbers.', 'Gebruik letters én cijfers.');
  return null;
}

bool validEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

/// Foutmelding van Supabase in gewone taal.
String authMessage(Object e) {
  if (e is AuthException) {
    return switch (e.code) {
      'invalid_credentials' => tr('Email address or password is incorrect.', 'E-mailadres of wachtwoord klopt niet.'),
      'email_not_confirmed' => tr('Your email address has not been confirmed yet.', 'Je e-mailadres is nog niet bevestigd.'),
      'user_already_exists' || 'email_exists' => tr(
        'An account with this email address already exists. Log in or choose "Forgot password".',
        'Er bestaat al een account met dit e-mailadres. Log in of kies "Wachtwoord vergeten".',
      ),
      'weak_password' => tr(
        'This password is too weak: at least 8 characters, with letters and numbers.',
        'Dit wachtwoord is te zwak: minstens 8 tekens, met letters en cijfers.',
      ),
      'wrong_current_password' => tr('Your current password is incorrect.', 'Je huidige wachtwoord klopt niet.'),
      'same_password' => tr('Choose a different password from your current one.', 'Kies een ander wachtwoord dan je huidige.'),
      'otp_expired' => tr('That code is wrong or has expired. Request a new one.', 'Die code klopt niet of is verlopen. Vraag een nieuwe aan.'),
      'over_email_send_rate_limit' || 'over_request_rate_limit' => tr(
        'Too many attempts. Wait a minute and try again.',
        'Even te veel pogingen. Wacht een minuut en probeer opnieuw.',
      ),
      'email_address_invalid' => tr('This email address is not accepted.', 'Dit e-mailadres wordt niet aanvaard.'),
      'signup_disabled' => tr('Signing up is temporarily unavailable.', 'Registreren is tijdelijk niet mogelijk.'),
      // Onze hook: te veel nieuwe accounts vanaf hetzelfde netwerk (zie de migratie signup_ip_limit)
      _ when e.message.contains('new accounts from this network') => tr(
        'Too many new accounts were made from this network. Try again in an hour.',
        'Er werden te veel nieuwe accounts aangemaakt vanaf dit netwerk. Probeer het over een uur opnieuw.',
      ),
      _ =>
        e.statusCode == '429'
            ? tr('Too many attempts. Wait a minute and try again.', 'Even te veel pogingen. Wacht een minuut en probeer opnieuw.')
            : tr('That did not work: ${e.message}', 'Dat lukte niet: ${e.message}'),
    };
  }
  return tr('No connection. Check your internet and try again.', 'Geen verbinding. Controleer je internet en probeer opnieuw.');
}

// ── Welkom ──

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  /// Links van de site naar /app/?start=register of ?start=login openen meteen dat scherm. Gewoon /app/ (de knop
  /// "Open in browser") toont dit welkomscherm, waar je ook zonder account kunt beginnen.
  static bool _handledStart = false;

  @override
  void initState() {
    super.initState();
    final start = kIsWeb ? Uri.base.queryParameters['start'] : null;
    if (!_handledStart && (start == 'register' || start == 'login')) {
      _handledStart = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuthScreen(register: start == 'register')));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pending = context.select<Account, String?>((a) => a.pendingConfirmation);
    Widget point(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: p.brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2)),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const MatrixLogo(size: 36),
                      const SizedBox(width: 10),
                      Text(
                        'MacroMatrix',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text(
                    tr('Know what you really take in.', 'Weet wat je echt binnenkrijgt.'),
                    style: TextStyle(fontSize: 32, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.9, color: p.ink),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      'Log what you eat and instantly see your energy, macros and all vitamins and minerals, with goals based on EFSA.',
                      'Log wat je eet en zie meteen je energie, macro\'s en alle vitaminen en mineralen, met doelen volgens EFSA.',
                    ),
                    style: TextStyle(fontSize: 16, height: 1.5, color: p.ink2),
                  ),
                  const SizedBox(height: 32),
                  point(
                    Icons.science_outlined,
                    tr('69 nutrients per day', '69 voedingsstoffen per dag'),
                    tr(
                      'From vitamin D to zinc, with warnings when you go above a safe limit.',
                      'Van vitamine D tot zink, met waarschuwingen als je boven een veilige grens gaat.',
                    ),
                  ),
                  point(
                    Icons.public_rounded,
                    tr('European data first', 'Europese gegevens eerst'),
                    tr(
                      'Basic foods from seven official European and US databases, branded products via Open Food Facts.',
                      'Basisproducten uit zeven officiële Europese en Amerikaanse databanken, merkproducten via Open Food Facts.',
                    ),
                  ),
                  point(
                    Icons.devices_rounded,
                    tr('On all your devices', 'Op al je toestellen'),
                    tr(
                      'Your account keeps your phone, computer and the web version in sync. Works offline too.',
                      'Je account houdt je gsm, pc en de webversie gelijk. Werkt ook zonder internet.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Een registratie die nog op de code uit de mail wacht: meteen afmaken, niet opnieuw beginnen (NW-6)
                  if (pending != null) ...[
                    Container(
                      key: const ValueKey('pending-confirm'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Code from the email ready?', 'Code uit de mail bij de hand?'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr('Your account for $pending is waiting to be confirmed.', 'Je account voor $pending wacht nog op je bevestiging.'),
                            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuthScreen(register: true, confirmEmail: pending))),
                              child: Text(tr('Confirm your account', 'Bevestig je account')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(register: true))),
                    child: Text(tr('Create account', 'Account aanmaken')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(register: false))),
                    child: Text(tr('Log in', 'Inloggen')),
                  ),
                  // Zonder account: in de app (gsm, pc) en in de browser. Wat dat betekent staat er meteen onder, vóór
                  // je kiest, in plaats van in een apart venster erna (eerste-maaltijdmeting 25-10).
                  const SizedBox(height: 6),
                  TextButton(onPressed: () => withoutAccount(context), child: Text(tr('Use without an account', 'Gebruiken zonder account'))),
                  Text(
                    guestNote,
                    key: const ValueKey('guest-note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink3),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      TextButton(onPressed: () => openPage(aboutPagePath), child: Text(tr('More about the app', 'Meer over de app'))),
                      TextButton(onPressed: () => openPage('/privacy/'), child: const Text('Privacy')),
                      TextButton(onPressed: () => openPage('/terms/'), child: Text(tr('Terms', 'Voorwaarden'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Registreren, inloggen en wachtwoord vergeten ──

enum _Step { register, confirm, login, forgot, reset }

/// Het veld waar een foutmelding bij hoort: de melding staat onder dat veld (of dat vakje) en verdwijnt zodra je het
/// aanpast (NW-5).
enum _Field { email, code, password, password2, terms }

/// Op een gsm-browser stelt Chrome bij een "nieuw wachtwoord"-veld zelf een wachtwoord voor; in de webversie blijft
/// dat voorstel onzichtbaar en verschijnt het toetsenbord niet. Daarom op het web geen hint voor nieuwe wachtwoorden.
const _newPasswordHints = kIsWeb ? null : [AutofillHints.newPassword];

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.register, this.confirmEmail});
  final bool register;

  /// Meteen de code invullen voor dit adres: een registratie die je eerder niet afmaakte (NW-6).
  final String? confirmEmail;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late _Step _step = widget.confirmEmail != null
      ? _Step.confirm
      : widget.register
      ? _Step.register
      : _Step.login;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _code = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _terms = false;
  bool _show = false;
  bool _busy = false;
  String? _error;
  String? _info;
  (String, _Field)? _fieldError;

  /// Terug op het codescherm: naar het formulier waar je vandaan kwam, met alles nog ingevuld (NW-6).
  _Step? _backTo;

  @override
  void initState() {
    super.initState();
    if (widget.confirmEmail case final email?) {
      _email.text = email;
      _info = tr(
        'Enter the 6-digit code we sent to $email. Also check your spam.',
        'Vul de code van 6 cijfers in die we naar $email stuurden. Kijk ook in je spam.',
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _password2, _code]) {
      c.dispose();
    }
    _passwordFocus.dispose();
    super.dispose();
  }

  void _go(_Step s, {String? info}) => setState(() {
    _backTo = s == _Step.confirm && (_step == _Step.register || _step == _Step.login) && widget.confirmEmail == null ? _step : null;
    _step = s;
    _error = null;
    _fieldError = null;
    _info = info;
    _code.clear();
    if (s == _Step.reset || s == _Step.register || s == _Step.login) {
      _password.clear();
      _password2.clear();
    }
  });

  /// Voert een actie uit met een wachtindicator en toont fouten in gewone taal. Geeft true bij succes.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  (String, _Field)? _check({bool email = true, bool password = false, bool twice = false, bool code = false}) {
    if (email && !validEmail(_email.text)) return (tr('Enter a valid email address.', 'Vul een geldig e-mailadres in.'), _Field.email);
    if (code && _code.text.trim().length < 6) {
      return (tr('Enter the 6-digit code from the email.', 'Vul de code van 6 cijfers uit de mail in.'), _Field.code);
    }
    if (password) {
      final p = passwordProblem(_password.text);
      if (p != null) return (p, _Field.password);
    }
    if (twice && _password.text != _password2.text) {
      return (tr('The two passwords do not match.', 'De twee wachtwoorden zijn niet gelijk.'), _Field.password2);
    }
    return null;
  }

  /// De melding bij dit veld, of null.
  String? _errorAt(_Field f) => _fieldError?.$2 == f ? _fieldError!.$1 : null;

  /// Je past een veld aan: de melding bij dat veld en een algemene melding (bv. van de server) verdwijnen.
  void _changed(_Field f) {
    if (_fieldError?.$2 != f && _error == null) return;
    setState(() {
      if (_fieldError?.$2 == f) _fieldError = null;
      _error = null;
    });
  }

  /// Terug op het codescherm: het formulier van daarvoor, met e-mail en wachtwoord nog ingevuld.
  void _back() => setState(() {
    _step = _backTo!;
    _backTo = null;
    _error = null;
    _fieldError = null;
    _info = null;
    _code.clear();
  });

  Future<void> _submit() async {
    final a = context.read<Account>();
    switch (_step) {
      case _Step.register:
        final problem =
            _check(password: true, twice: true) ??
            (_terms
                ? null
                : (
                    tr(
                      'Tick that you agree, otherwise we cannot store your data.',
                      'Vink aan dat je akkoord gaat, anders kunnen we je gegevens niet bewaren.',
                    ),
                    _Field.terms,
                  ));
        if (problem != null) return setState(() => _fieldError = problem);
        var isNew = true;
        if (await _run(() async => isNew = await a.signUp(_email.text, _password.text))) {
          if (isNew) {
            // Onthouden: ga je terug of sluit je de app, dan biedt het welkomscherm aan om de code nog in te vullen
            a.setPendingConfirmation(_email.text);
            _go(
              _Step.confirm,
              info: tr(
                'We sent a 6-digit code to ${_email.text.trim()}. Also check your spam.',
                'We stuurden een code van 6 cijfers naar ${_email.text.trim()}. Kijk ook in je spam.',
              ),
            );
          } else {
            _go(
              _Step.login,
              info: tr(
                'An account with ${_email.text.trim()} already exists. Log in below with your password, or choose "Forgot password".',
                'Er bestaat al een account met ${_email.text.trim()}. Log hieronder in met je wachtwoord, of kies "Wachtwoord vergeten".',
              ),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) => _passwordFocus.requestFocus());
          }
        }
      case _Step.confirm:
        final problem = _check(email: false, code: true);
        if (problem != null) return setState(() => _fieldError = problem);
        if (await _run(() => a.confirmSignUp(_email.text, _code.text))) _done();
      case _Step.login:
        final problem = _check();
        if (problem != null) return setState(() => _fieldError = problem);
        if (_password.text.isEmpty) return setState(() => _fieldError = (tr('Enter your password.', 'Vul je wachtwoord in.'), _Field.password));
        try {
          setState(() => _busy = true);
          await a.signIn(_email.text, _password.text);
          if (mounted) _done();
        } on AuthException catch (e) {
          // Intussen teruggegaan: niets meer tonen op een scherm dat weg is
          if (!mounted) return;
          if (e.code == 'email_not_confirmed') {
            await a.resendConfirmation(_email.text).catchError((_) {});
            a.setPendingConfirmation(_email.text);
            if (!mounted) return;
            _go(
              _Step.confirm,
              info: tr(
                'Your email address has not been confirmed yet. We sent a new code to ${_email.text.trim()}.',
                'Je e-mailadres is nog niet bevestigd. We stuurden een nieuwe code naar ${_email.text.trim()}.',
              ),
            );
          } else {
            setState(() => _error = authMessage(e));
          }
        } catch (e) {
          if (mounted) setState(() => _error = authMessage(e));
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case _Step.forgot:
        final problem = _check();
        if (problem != null) return setState(() => _fieldError = problem);
        if (await _run(() => a.requestPasswordReset(_email.text))) {
          _go(
            _Step.reset,
            info: tr(
              'If an account exists for ${_email.text.trim()}, there is now a 6-digit code in your mailbox.',
              'Als er een account bestaat voor ${_email.text.trim()}, staat er nu een code van 6 cijfers in je mailbox.',
            ),
          );
        }
      case _Step.reset:
        final problem = _check(email: false, code: true, password: true, twice: true);
        if (problem != null) return setState(() => _fieldError = problem);
        if (await _run(() => context.read<Account>().resetPassword(_email.text, _code.text, _password.text))) _done();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (title, button) = switch (_step) {
      _Step.register => (tr('Create account', 'Account aanmaken'), tr('Create account', 'Account aanmaken')),
      _Step.confirm => (tr('Confirm your email address', 'Bevestig je e-mailadres'), tr('Confirm', 'Bevestigen')),
      _Step.login => (tr('Log in', tr('Log in', 'Inloggen')), tr('Log in', tr('Log in', 'Inloggen'))),
      _Step.forgot => (tr('Forgot password', 'Wachtwoord vergeten'), tr('Send me a code', 'Stuur me een code')),
      _Step.reset => (tr('New password', 'Nieuw wachtwoord'), tr('Save password', 'Wachtwoord opslaan')),
    };
    final guest = context.select<Account, bool>((a) => a.localOnly && !a.signedIn);
    final needsEmail = _step == _Step.register || _step == _Step.login || _step == _Step.forgot;
    final needsPassword = _step == _Step.register || _step == _Step.login || _step == _Step.reset;
    final needsTwice = _step == _Step.register || _step == _Step.reset;
    final needsCode = _step == _Step.confirm || _step == _Step.reset;

    InputDecoration pw(String label, _Field field) => InputDecoration(
      labelText: label,
      errorText: _errorAt(field),
      errorMaxLines: 2,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: _show ? tr('Hide', 'Verbergen') : tr('Show', 'Tonen'),
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _show = !_show),
      ),
    );

    final termsError = _errorAt(_Field.terms);
    return PopScope(
      canPop: _backTo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _backTo != null) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug'), onPressed: () => Navigator.of(context).maybePop()),
        ),
        body: SafeArea(
          // Bovenaan, niet in het midden: een foutmelding duwt dan niets omhoog onder je vinger (NW-4)
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _maybeAutofill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      if (_info != null)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 20, color: p.brand),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_info!, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
                              ),
                            ],
                          ),
                        )
                      else if (_step == _Step.register)
                        Text(
                          tr(
                            'With an account your data is stored safely and you see it on all your devices.',
                            'Met een account bewaar je je gegevens veilig en zie je ze op al je toestellen.',
                          ),
                          style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                        )
                      else if (_step == _Step.forgot)
                        Text(
                          tr('We will email you a code to choose a new password.', 'We mailen je een code om een nieuw wachtwoord te kiezen.'),
                          style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                        ),
                      // Eerst zonder account gebruikt: zeggen dat dat niet verloren gaat
                      if (guest && (_step == _Step.register || _step == _Step.login)) ...[
                        const SizedBox(height: 10),
                        Text(
                          _step == _Step.register
                              ? tr(
                                  'Everything you logged so far comes along to your new account.',
                                  'Alles wat je tot nu toe logde, gaat mee naar je nieuwe account.',
                                )
                              : tr(
                                  'What you logged so far is added to your account. If your account already has a profile and goals, those are kept.',
                                  'Wat je tot nu toe logde, komt bij je account. Heeft je account al een profiel en doelen, dan blijven die.',
                                ),
                          key: const ValueKey('guest-upgrade-note'),
                          style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (needsEmail) ...[
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => _changed(_Field.email),
                          decoration: InputDecoration(
                            labelText: tr('Email address', 'E-mailadres'),
                            errorText: _errorAt(_Field.email),
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (needsCode) ...[
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          inputFormatters: wholeInput,
                          autofillHints: kIsWeb ? null : const [AutofillHints.oneTimeCode],
                          maxLength: 6,
                          style: numStyle(22),
                          textInputAction: needsPassword ? TextInputAction.next : TextInputAction.done,
                          onChanged: (_) => _changed(_Field.code),
                          decoration: InputDecoration(
                            labelText: tr('Code from the email', 'Code uit de e-mail'),
                            counterText: '',
                            errorText: _errorAt(_Field.code),
                          ),
                          onSubmitted: needsPassword ? null : (_) => _submit(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (needsPassword) ...[
                        TextField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          obscureText: !_show,
                          autofillHints: _step == _Step.login ? const [AutofillHints.password] : _newPasswordHints,
                          textInputAction: needsTwice ? TextInputAction.next : TextInputAction.done,
                          onChanged: (_) => _changed(_Field.password),
                          decoration: pw(
                            _step == _Step.reset ? tr('New password', 'Nieuw wachtwoord') : tr('Password', 'Wachtwoord'),
                            _Field.password,
                          ),
                          onSubmitted: needsTwice ? null : (_) => _submit(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (needsTwice) ...[
                        TextField(
                          controller: _password2,
                          obscureText: !_show,
                          autofillHints: _newPasswordHints,
                          onChanged: (_) => _changed(_Field.password2),
                          decoration: pw(tr('Repeat the password', 'Herhaal het wachtwoord'), _Field.password2),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('At least 8 characters, with letters and numbers.', 'Minstens 8 tekens, met letters en cijfers.'),
                          style: TextStyle(fontSize: 12, color: p.ink3),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_step == _Step.register)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _tickTerms(!_terms),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(value: _terms, isError: termsError != null, onChanged: (v) => _tickTerms(v ?? false)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: tr('I agree to the ', 'Ik ga akkoord met de ')),
                                          WidgetSpan(
                                            alignment: PlaceholderAlignment.baseline,
                                            baseline: TextBaseline.alphabetic,
                                            child: _Link(tr('terms', 'voorwaarden'), () => openPage('/terms/')),
                                          ),
                                          TextSpan(text: tr(' and the ', ' en het ')),
                                          WidgetSpan(
                                            alignment: PlaceholderAlignment.baseline,
                                            baseline: TextBaseline.alphabetic,
                                            child: _Link(tr('privacy policy', 'privacybeleid'), () => openPage('/privacy/')),
                                          ),
                                          TextSpan(
                                            text: tr(
                                              ', and give permission to store my nutrition and health data so the app can work.',
                                              ', en geef toestemming om mijn voedings- en gezondheidsgegevens te bewaren om de app te laten werken.',
                                            ),
                                          ),
                                        ],
                                      ),
                                      style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (termsError != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Text(
                            termsError,
                            key: const ValueKey('terms-error'),
                            style: TextStyle(fontSize: 12.5, color: p.high),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: p.highSoft, borderRadius: BorderRadius.circular(12)),
                          child: Text(_error!, style: TextStyle(fontSize: 13.5, color: p.high)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.ink3))
                            : Text(button),
                      ),
                      const SizedBox(height: 10),
                      ..._links(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tickTerms(bool on) => setState(() {
    _terms = on;
    if (on && _fieldError?.$2 == _Field.terms) _fieldError = null;
  });

  /// Velden groeperen voor wachtwoordbeheerders, maar op het web alleen bij inloggen (zie [_newPasswordHints]).
  Widget _maybeAutofill({required Widget child}) => !kIsWeb || _step == _Step.login ? AutofillGroup(child: child) : child;

  List<Widget> _links() {
    final a = context.read<Account>();
    Widget link(String text, VoidCallback onTap) => TextButton(onPressed: _busy ? null : onTap, child: Text(text));
    return switch (_step) {
      _Step.register => [link(tr('I already have an account', 'Ik heb al een account'), () => _go(_Step.login))],
      _Step.login => [
        link(tr('Forgot password?', 'Wachtwoord vergeten?'), () => _go(_Step.forgot)),
        link(tr('No account yet? Create one', 'Nog geen account? Maak er een'), () => _go(_Step.register)),
      ],
      _Step.confirm => [
        link(tr('Send the code again', 'Stuur de code opnieuw'), () async {
          if (await _run(() => a.resendConfirmation(_email.text))) {
            setState(() => _info = tr('New code sent to ${_email.text.trim()}.', 'Nieuwe code verstuurd naar ${_email.text.trim()}.'));
          }
        }),
        link(tr('Different email address', 'Ander e-mailadres'), () {
          a.setPendingConfirmation(null);
          _go(_Step.register);
        }),
      ],
      _Step.forgot => [link(tr('Back to log in', 'Terug naar inloggen'), () => _go(_Step.login))],
      _Step.reset => [
        link(tr('Send the code again', 'Stuur de code opnieuw'), () async {
          if (await _run(() => a.requestPasswordReset(_email.text))) {
            setState(() => _info = tr('New code sent to ${_email.text.trim()}.', 'Nieuwe code verstuurd naar ${_email.text.trim()}.'));
          }
        }),
        link(tr('Back to log in', 'Terug naar inloggen'), () => _go(_Step.login)),
      ],
    };
  }
}

class _Link extends StatelessWidget {
  const _Link(this.text, this.onTap);
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(
      text,
      style: TextStyle(fontSize: 13.5, color: context.pal.brand, decoration: TextDecoration.underline, decorationColor: context.pal.brand),
    ),
  );
}

// ── Profiel instellen na het registreren ──

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // Alleen wat nodig is voor je doelen en de 18+-controle. Activiteit (standaard licht actief) vragen we na je eerste
  // maaltijd op Vandaag, allergieën met de kaart onder de maaltijden, en het thema volgt het toestel (zie Instellingen).
  Sex _sex = Sex.male;
  Goal _goal = Goal.maintain;
  final _birth = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _heightFocus = FocusNode(), _weightFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    for (final c in [_birth, _height, _weight]) {
      c.dispose();
    }
    _heightFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  /// Volledig ingevuld (een jaartal van 4 cijfers, een lengte van 3 cijfers in cm): meteen naar het volgende veld,
  /// zonder extra tik. Gewicht heeft geen vaste lengte, dus daar niet.
  void _advance(String v, int digits, FocusNode next, {double? min, double? max}) {
    if (!RegExp('^[0-9]{$digits}\$').hasMatch(v)) return;
    final n = double.parse(v);
    if ((min != null && n < min) || (max != null && n > max)) return;
    next.requestFocus();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final year = DateTime.now().year;
    final birth = _num(_birth)?.round(), height = _num(_height), weight = _num(_weight);
    final problem = birth == null || birth < 1900 || birth > year - 18
        ? tr('Enter your year of birth (you must be at least 18).', 'Vul je geboortejaar in (je moet minstens 18 zijn).')
        : height == null || height < 120 || height > 230
        ? tr('Enter your height in centimetres.', 'Vul je lengte in centimeter in.')
        : weight == null || weight < 35 || weight > 300
        ? tr('Enter your weight in kilograms.', 'Vul je gewicht in kilogram in.')
        : null;
    if (problem != null) return setState(() => _error = problem);
    final s = context.read<AppState>();
    s.saveProfile(Profile(sex: _sex, birthYear: birth!, heightCm: height!, weightKg: weight!, activity: Activity.light, goal: _goal));
    askActivityLater(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget field(String label, TextEditingController c, String suffix, {FocusNode? focus, ValueChanged<String>? onChanged, bool last = false}) =>
        Expanded(
          child: TextField(
            controller: c,
            focusNode: focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalInput,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onTap: selectAllOnTap(c),
            onChanged: onChanged,
            onSubmitted: last ? (_) => _save() : null,
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Geen "stap 2 van 2": de eerste stap (het account) zag je niet als stap (NW-16)
                  Eyebrow(tr('Last step', 'Laatste stap')),
                  const SizedBox(height: 6),
                  Text(tr('About you', 'Over jou'), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'This sets your daily goals (EFSA). You can change everything later.',
                      'Hiermee berekenen we je dagelijkse doelen (EFSA). Je kunt alles later aanpassen.',
                    ),
                    style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                  ),
                  const SizedBox(height: 22),
                  Segmented<Sex>(items: [for (final x in Sex.values) (x, x.label)], selected: _sex, onChanged: (v) => setState(() => _sex = v)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      field(tr('Born in', 'Geboren in'), _birth, '', onChanged: (v) => _advance(v, 4, _heightFocus, min: 1900, max: DateTime.now().year - 18.0)),
                      const SizedBox(width: 10),
                      field(
                        tr('Height', 'Lengte'),
                        _height,
                        'cm',
                        focus: _heightFocus,
                        onChanged: (v) => _advance(v, 3, _weightFocus, min: 120, max: 230),
                      ),
                      const SizedBox(width: 10),
                      field(tr('Weight', 'Gewicht'), _weight, 'kg', focus: _weightFocus, last: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Your goal', 'Je doel'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 8),
                  Segmented<Goal>(items: [for (final g in Goal.values) (g, g.label)], selected: _goal, onChanged: (g) => setState(() => _goal = g)),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.highSoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: TextStyle(fontSize: 13.5, color: p.high)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _save,
                    child: Text(tr('Done, go to the app', 'Klaar, naar de app')),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      'The reference values apply to adults, not during pregnancy or breastfeeding. Not medical advice.',
                      'De richtwaarden gelden voor volwassenen, niet tijdens zwangerschap of borstvoeding. Geen medisch advies.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: p.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wat "zonder account" betekent, onder de knop op het welkomscherm. In de browser eerlijk zeggen dat alles alleen in
/// die browser staat (een privévenster of browsergegevens wissen = weg).
String get guestNote => runsOnWeb
    ? tr(
        'Saved in this browser only: lost in a private window or when you clear browsing data. Add an account anytime; what you logged comes along.',
        'Alleen bewaard in deze browser: weg in een privévenster of als je je browsergegevens wist. Een account kan altijd later; wat je logde, gaat mee.',
      )
    : tr(
        'Saved on this device only. Add an account anytime; what you logged comes along.',
        'Alleen bewaard op dit toestel. Een account kan altijd later; wat je logde, gaat mee.',
      );

/// Bewust zonder account beginnen: de uitleg ([guestNote]) staat al onder de knop, dus meteen verder. Vraag de
/// browser om de gegevens niet zelf op te ruimen. Meer uitleg (geen synchronisatie, vrienden of foto's) staat in
/// Instellingen ([GuestAccountPanel]) en komt na 3 dagen terug ([GuestNudgeCard]).
void withoutAccount(BuildContext context) {
  context.read<Account>().setLocalOnly(true);
  if (runsOnWeb) unawaited(askPersistentStorage());
}
