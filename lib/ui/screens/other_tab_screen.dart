/// In de browser: MacroMatrix staat al open in een ander tabblad. Twee tabbladen tegelijk zouden de database in de
/// browser beschadigen (zie platform_web.dart), dus dit tabblad wacht tot je kiest om het hier te gebruiken.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../theme.dart';
import '../widgets/logo.dart';

/// Een eigen kleine app: de database (en dus je instellingen) is in dit tabblad nog niet open.
class OtherTabApp extends StatelessWidget {
  const OtherTabApp({super.key, required this.onTakeOver});

  /// Het andere tabblad vragen om vrij te geven, en wachten tot dat gebeurd is.
  final Future<void> Function() onTakeOver;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MacroMatrix',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: OtherTabScreen(onTakeOver: onTakeOver),
  );
}

class OtherTabScreen extends StatefulWidget {
  const OtherTabScreen({super.key, required this.onTakeOver});
  final Future<void> Function() onTakeOver;

  @override
  State<OtherTabScreen> createState() => _OtherTabScreenState();
}

class _OtherTabScreenState extends State<OtherTabScreen> {
  bool _waiting = false;

  Future<void> _takeOver() async {
    setState(() => _waiting = true);
    await widget.onTakeOver();
  }

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
                  const Center(child: MatrixLogo(size: 48)),
                  const SizedBox(height: 24),
                  Text(
                    tr('MacroMatrix is already open in another tab', 'MacroMatrix is al open in een ander tabblad'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _waiting
                        ? tr(
                            'Waiting for the other tab to let go… If nothing happens, close the other MacroMatrix tab.',
                            'Wachten tot het andere tabblad loslaat… Gebeurt er niets, sluit dan het andere tabblad met MacroMatrix.',
                          )
                        : tr(
                            'To keep your data safe, MacroMatrix can only be open in one tab at a time. Close the other tab, or use it here instead.',
                            'Om je gegevens veilig te houden, kan MacroMatrix maar in één tabblad tegelijk open staan. Sluit het andere tabblad, of '
                                'gebruik het hier.',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.5, color: p.ink2),
                  ),
                  const SizedBox(height: 24),
                  if (_waiting)
                    const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator()))
                  else
                    FilledButton(
                      key: const ValueKey('use-here'),
                      onPressed: _takeOver,
                      child: Text(tr('Use here instead', 'Hier gebruiken')),
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
