import 'dart:async';

import 'package:flutter/material.dart';
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
import 'ui/screens/auth_screens.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'nl_BE';
  await initializeDateFormatting(appLocale);

  final (foods, user) = await openDatabases();
  final state = AppState(foods: foods, user: user)..upgradeSavedProducts();
  final account = Account(user, onRemoteChanges: state.reloadFromDisk);
  unawaited(account.init());
  final reminders = Reminders(state);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: account),
        Provider.value(value: reminders),
        // Niet lui: moet vanaf de start je level en score doorsturen, ook als je het vriendenscherm niet opent
        ChangeNotifierProvider(lazy: false, create: (_) => Friends(state, account)),
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
    // Andere taal: alles opnieuw opbouwen
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        locale: Locale(lang.name),
        supportedLocales: const [Locale('en'), Locale('nl')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'MacroMatrix',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: const AuthGate(),
      ),
    );
  }
}
