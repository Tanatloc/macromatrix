/// Welkom, registreren, inloggen, wachtwoord vergeten en je profiel instellen. Als de app met Supabase gebouwd is,
/// kies je op het welkomscherm: een account, of bewust zonder account (ook in de browser); zie [AuthGate].
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase/supabase.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../../nutrition/targets.dart';
import '../../platform/platform.dart' show askPersistentStorage;
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/kit.dart';
import '../widgets/logo.dart';
import '../../i18n.dart';
import '../../nutrition/allergens.dart';
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

enum GateScreen { loading, welcome, profileSetup, app }

/// Wat [AuthGate] toont. Zonder account (bewust gekozen) kom je overal in de app, ook in de browser: je gegevens
/// staan dan in de opslag van de browser (IndexedDB, zie platform_web.dart).
/// [fetching]: net ingelogd op een bestaand account, het profiel kan nog onderweg zijn (GP-11).
GateScreen gateScreen({
  required bool ready,
  required bool configured,
  required bool signedIn,
  required bool localOnly,
  required bool hasProfile,
  bool fetching = false,
}) {
  if (!ready) return GateScreen.loading;
  if (configured && !signedIn && !localOnly) return GateScreen.welcome;
  if (configured && !hasProfile && fetching) return GateScreen.loading;
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
    return switch (gateScreen(
      ready: a.ready,
      configured: Account.configured,
      signedIn: a.signedIn,
      localOnly: a.localOnly,
      hasProfile: s.hasProfile,
      fetching: a.fetchingAfterLogin,
    )) {
      GateScreen.loading => Scaffold(backgroundColor: context.pal.bg, body: const SizedBox.expand()),
      GateScreen.welcome => const WelcomeScreen(),
      GateScreen.profileSetup => const ProfileSetupScreen(),
      GateScreen.app => const Shell(),
    };
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
                  // Zonder account: in de app (gsm, pc) en in de browser
                  const SizedBox(height: 6),
                  TextButton(onPressed: () => withoutAccount(context), child: Text(tr('Use without an account', 'Gebruiken zonder account'))),
                  if (runsOnWeb)
                    Text(
                      tr('Your data is then kept in this browser only.', 'Je gegevens blijven dan alleen in deze browser.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: p.ink3),
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

/// Op een gsm-browser stelt Chrome bij een "nieuw wachtwoord"-veld zelf een wachtwoord voor; in de webversie blijft
/// dat voorstel onzichtbaar en verschijnt het toetsenbord niet. Daarom op het web geen hint voor nieuwe wachtwoorden.
const _newPasswordHints = kIsWeb ? null : [AutofillHints.newPassword];

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.register});
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late _Step _step = widget.register ? _Step.register : _Step.login;
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

  @override
  void dispose() {
    for (final c in [_email, _password, _password2, _code]) {
      c.dispose();
    }
    _passwordFocus.dispose();
    super.dispose();
  }

  void _go(_Step s, {String? info}) => setState(() {
    _step = s;
    _error = null;
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

  String? _check({bool email = true, bool password = false, bool twice = false, bool code = false}) {
    if (email && !validEmail(_email.text)) return tr('Enter a valid email address.', 'Vul een geldig e-mailadres in.');
    if (password) {
      final p = passwordProblem(_password.text);
      if (p != null) return p;
    }
    if (twice && _password.text != _password2.text) return tr('The two passwords do not match.', 'De twee wachtwoorden zijn niet gelijk.');
    if (code && _code.text.trim().length < 6) return tr('Enter the 6-digit code from the email.', 'Vul de code van 6 cijfers uit de mail in.');
    return null;
  }

  Future<void> _submit() async {
    final a = context.read<Account>();
    switch (_step) {
      case _Step.register:
        final problem =
            _check(password: true, twice: true) ??
            (_terms
                ? null
                : tr(
                    'Tick that you agree, otherwise we cannot store your data.',
                    'Vink aan dat je akkoord gaat, anders kunnen we je gegevens niet bewaren.',
                  ));
        if (problem != null) return setState(() => _error = problem);
        var isNew = true;
        if (await _run(() async => isNew = await a.signUp(_email.text, _password.text))) {
          if (isNew) {
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
        final problem = _check(code: true);
        if (problem != null) return setState(() => _error = problem);
        if (await _run(() => a.confirmSignUp(_email.text, _code.text))) _done();
      case _Step.login:
        final problem = _check();
        if (problem != null) return setState(() => _error = problem);
        if (_password.text.isEmpty) return setState(() => _error = tr('Enter your password.', 'Vul je wachtwoord in.'));
        try {
          setState(() => _busy = true);
          await a.signIn(_email.text, _password.text);
          _done();
        } on AuthException catch (e) {
          if (e.code == 'email_not_confirmed') {
            await a.resendConfirmation(_email.text).catchError((_) {});
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
          setState(() => _error = authMessage(e));
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case _Step.forgot:
        final problem = _check();
        if (problem != null) return setState(() => _error = problem);
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
        final problem = _check(code: true, password: true, twice: true);
        if (problem != null) return setState(() => _error = problem);
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

    InputDecoration pw(String label) => InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: _show ? tr('Hide', 'Verbergen') : tr('Show', 'Tonen'),
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _show = !_show),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug'), onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                        decoration: InputDecoration(labelText: tr('Email address', 'E-mailadres'), prefixIcon: Icon(Icons.mail_outline_rounded)),
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
                        decoration: InputDecoration(labelText: tr('Code from the email', 'Code uit de e-mail'), counterText: ''),
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
                        decoration: pw(_step == _Step.reset ? tr('New password', 'Nieuw wachtwoord') : tr('Password', 'Wachtwoord')),
                        onSubmitted: needsTwice ? null : (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (needsTwice) ...[
                      TextField(
                        controller: _password2,
                        obscureText: !_show,
                        autofillHints: _newPasswordHints,
                        decoration: pw(tr('Repeat the password', 'Herhaal het wachtwoord')),
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
                        onTap: () => setState(() => _terms = !_terms),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
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
    );
  }

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
        link(tr('Different email address', 'Ander e-mailadres'), () => _go(_Step.register)),
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
  Sex _sex = Sex.male;
  Activity _activity = Activity.light;
  Goal _goal = Goal.maintain;
  Set<Allergen> _allergies = {};
  final _birth = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_birth, _height, _weight]) {
      c.dispose();
    }
    super.dispose();
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
    context.read<AppState>().setAllergies(_allergies);
    context.read<AppState>().saveProfile(
      Profile(sex: _sex, birthYear: birth!, heightCm: height!, weightKg: weight!, activity: _activity, goal: _goal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget field(String label, TextEditingController c, String suffix) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: decimalInput,
        onTap: selectAllOnTap(c),
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
                  Eyebrow(tr('Step 2 of 2', 'Stap 2 van 2')),
                  const SizedBox(height: 6),
                  Text(tr('About you', 'Over jou'), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'We use this to calculate your goals for energy, protein, vitamins and minerals (EFSA). You can change everything later.',
                      'Hiermee berekenen we je doelen voor energie, eiwit, vitaminen en mineralen (EFSA). Je kunt alles later aanpassen.',
                    ),
                    style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                  ),
                  const SizedBox(height: 22),
                  Segmented<Sex>(items: [for (final x in Sex.values) (x, x.label)], selected: _sex, onChanged: (v) => setState(() => _sex = v)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      field(tr('Born in', 'Geboren in'), _birth, ''),
                      const SizedBox(width: 10),
                      field(tr('Height', 'Lengte'), _height, 'cm'),
                      const SizedBox(width: 10),
                      field(tr('Weight', 'Gewicht'), _weight, 'kg'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    tr('How active are you?', 'Hoe actief ben je?'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 8),
                  for (final a in Activity.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: _activity == a ? p.brandSoft : p.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _activity == a ? p.brand : p.line, width: _activity == a ? 1.5 : 1),
                        ),
                        child: InkWell(
                          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () => setState(() => _activity = a),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.label,
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                                      ),
                                      Text(a.description, style: TextStyle(fontSize: 12, color: p.ink3)),
                                    ],
                                  ),
                                ),
                                if (_activity == a) Icon(Icons.check_rounded, size: 18, color: p.brand),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Your goal', 'Je doel'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 8),
                  Segmented<Goal>(items: [for (final g in Goal.values) (g, g.label)], selected: _goal, onChanged: (g) => setState(() => _goal = g)),
                  const SizedBox(height: 18),
                  Text(
                    tr('Appearance', 'Weergave'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Light or dark? You can change it later in the settings.', 'Licht of donker? Je kunt het later wijzigen in de instellingen.'),
                    style: TextStyle(fontSize: 12.5, color: p.ink3),
                  ),
                  const SizedBox(height: 8),
                  Segmented<String>(
                    items: [('light', tr('Light', 'Licht')), ('dark', tr('Dark', 'Donker')), ('system', tr('Like my device', 'Zoals toestel'))],
                    selected: context.watch<AppState>().themeMode,
                    onChanged: context.read<AppState>().setThemeMode,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    tr('Allergies (optional)', 'Allergieën (optioneel)'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Select only what you react to, e.g. just peanuts.', 'Duid alleen aan waarop je reageert, bv. enkel pinda.'),
                    style: TextStyle(fontSize: 12.5, color: p.ink3),
                  ),
                  const SizedBox(height: 8),
                  AllergenPicker(selected: _allergies, onChanged: (v) => setState(() => _allergies = v)),
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

/// Zonder account verder: eerst uitleggen wat je dan mist.
/// Bewust zonder account beginnen, na uitleg wat dat betekent. In de browser eerlijk zeggen dat alles alleen in
/// die browser staat (browsergegevens wissen of een privévenster = weg), en de browser vragen het niet zelf op te
/// ruimen.
Future<void> withoutAccount(BuildContext context) async {
  final web = runsOnWeb;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Use without an account?', 'Zonder account gebruiken?')),
      content: Text(
        web
            ? tr(
                'Your data is kept in this browser only. If you clear your browsing data, use a private window or switch to another browser or device, you start over.\n\n'
                    'Without an account there is no sync, no friends or battles, and logging with a photo is not available.\n\n'
                    'Create a free account later in Settings to keep your data safe and use it on your phone. What you logged here comes along.',
                'Je gegevens blijven alleen in deze browser. Wis je je browsergegevens, gebruik je een privévenster of stap je over naar een andere browser of toestel, dan begin je opnieuw.\n\n'
                    'Zonder account is er geen synchronisatie, geen vrienden of battles, en loggen met een foto kan niet.\n\n'
                    'Maak later in de Instellingen een gratis account om je gegevens veilig te bewaren en ze op je gsm te gebruiken. Wat je hier logde, gaat mee.',
              )
            : tr(
                'Everything stays on this device only. Without an account there is no sync between devices, no friends or battles, '
                    'and voice logging only works if your phone has its own speech recognition. If you lose or reset this device, your data is gone.\n\n'
                    'You can create an account later in the settings; your data then comes along.',
                'Alles blijft alleen op dit toestel. Zonder account is er geen synchronisatie tussen toestellen, geen vrienden of battles, '
                    'en spraak werkt alleen als je gsm zelf spraakherkenning heeft. Verlies of reset je dit toestel, dan zijn je gegevens weg.\n\n'
                    'Je kunt later in de instellingen alsnog een account maken; je gegevens gaan dan mee.',
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Continue without account', 'Verder zonder account'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  context.read<Account>().setLocalOnly(true);
  if (web) unawaited(askPersistentStorage());
}
