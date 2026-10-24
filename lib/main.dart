import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'platform/platform.dart';
import 'platform/reminders.dart';
import 'state/app_state.dart';
import 'sync/account.dart';
import 'i18n.dart';
import 'sync/friends.dart';
import 'sync/pro.dart';
import 'ui/screens/auth_screens.dart';
import 'ui/theme.dart';
import 'ui/widgets/tap_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Een fout in een scherm: een leesbare melding in plaats van een grijs vlak, zodat ze te melden is
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xFFFFF4F2),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'Something went wrong here. Please send a screenshot to privacy@divinenet.online.\n\n${details.exceptionAsString()}',
        style: const TextStyle(color: Color(0xFF9B1C1C), fontSize: 12),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
  Intl.defaultLocale = 'nl_BE';
  await initializeDateFormatting(appLocale);

  final (foods, user) = await openDatabases();
  final state = AppState(foods: foods, user: user)
    ..refreshBuiltinSnapshots()
    ..upgradeSavedProducts();
  // Allereerste start (nog geen taal gekozen en nog geen profiel): de taal van het toestel, en die onthouden. Wie de
  // app al gebruikte zonder ooit een taal te kiezen, houdt Engels (N01).
  if (user.setting('ui')?['lang'] == null && !state.hasProfile) state.setLanguage(deviceLang);
  final account = Account(user, onRemoteChanges: state.reloadFromDisk);
  unawaited(account.init());
  final reminders = Reminders(state);
  // Pro-status en fototeller: meteen gemaakt, zodat de status na het inloggen meteen opgehaald wordt (en de
  // vriendenlijst er de supporterbadges uit kan halen)
  final pro = Pro(account);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: account),
        Provider.value(value: reminders),
        // Niet lui: moet vanaf de start je level en score doorsturen, ook als je het vriendenscherm niet opent
        ChangeNotifierProvider(lazy: false, create: (_) => Friends(state, account, pro: pro)),
        ChangeNotifierProvider.value(value: pro),
      ],
      child: const MacroMatrixApp(),
    ),
  );
  unawaited(reminders.init());
}

class MacroMatrixApp extends StatelessWidget {
  const MacroMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, String>((s) => s.themeMode);
    // Een extra kleur alleen zolang Pro loopt; anders de standaard (de keuze zelf blijft bewaard)
    final chosen = context.select<AppState, String>((s) => s.accent);
    final pro = context.select<Pro?, bool>((p) => p?.isPro ?? false);
    final accent = effectiveAccent(chosen, pro: pro);
    // Andere taal: nieuwe locale, en _LanguageRebuild bouwt alle schermen opnieuw op. Geen nieuwe sleutel meer op
    // MaterialApp: dat gooide alles weg (terug naar het eerste tabblad, open schermen dicht, dag bleef staan) (P15).
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, lang, _) => MaterialApp(
        locale: Locale(lang.name),
        supportedLocales: const [Locale('en'), Locale('nl')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'MacroMatrix',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, accent: accent),
        darkTheme: buildTheme(Brightness.dark, accent: accent),
        themeMode: switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        navigatorObservers: [tapGuard],
        builder: (context, child) => _LanguageRebuild(child: EscapeToClose(child: tapGuard.wrap(child))),
        home: const AuthGate(),
      ),
    );
  }
}

/// Bij een andere taal alles eronder opnieuw laten bouwen, ook schermen en tabbladen die niets van de taal
/// weten (de teksten komen uit tr()). De toestand (tabblad, open schermen, dag, ingevulde velden) blijft.
class _LanguageRebuild extends StatefulWidget {
  const _LanguageRebuild({required this.child});
  final Widget child;

  @override
  State<_LanguageRebuild> createState() => _LanguageRebuildState();
}

class _LanguageRebuildState extends State<_LanguageRebuild> {
  @override
  void initState() {
    super.initState();
    appLang.addListener(_rebuildAll);
  }

  @override
  void dispose() {
    appLang.removeListener(_rebuildAll);
    super.dispose();
  }

  void _rebuildAll() {
    if (!mounted) return;
    // Midden in een bouwbeurt mag niets als vuil gemarkeerd worden: dan na deze frame
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _rebuildAll());
      return;
    }
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Escape sluit het bovenste scherm, onderblad of venster, zoals de terugknop (P132). Standaard doet Escape dat
/// alleen bij vensters die je met een tik ernaast mag sluiten; volledige schermen bleven op een pc gewoon staan.
/// Een navigator die niets meer kan sluiten, laat de toets door (bv. aan een tekstveld).
class EscapeToClose extends StatelessWidget {
  const EscapeToClose({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): _CloseTopIntent()},
    child: Actions(actions: {_CloseTopIntent: _CloseTopAction()}, child: child),
  );
}

class _CloseTopIntent extends Intent {
  const _CloseTopIntent();
}

class _CloseTopAction extends Action<_CloseTopIntent> {
  /// De dichtstbijzijnde navigator (vanaf wat de focus heeft) die nog iets kan sluiten: een geneste navigator
  /// van een tabblad op een pc, anders de hoofdnavigator.
  NavigatorState? _target() {
    final ctx = primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return null;
    NavigatorState? nav = Navigator.maybeOf(ctx);
    while (nav != null) {
      if (nav.canPop()) return nav;
      nav = nav.context.findAncestorStateOfType<NavigatorState>();
    }
    return null;
  }

  @override
  bool isEnabled(_CloseTopIntent intent) => _target() != null;

  @override
  Object? invoke(_CloseTopIntent intent) => _target()?.maybePop();
}
