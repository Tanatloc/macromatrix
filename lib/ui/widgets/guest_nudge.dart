/// Eén vriendelijke herinnering voor wie zonder account werkt: na 3 gelogde dagen, één keer. Tik je op "Not now"
/// of op de knop, dan komt ze niet terug (in Instellingen staat dezelfde uitleg altijd, zie [GuestAccountPanel]).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../screens/auth_screens.dart';
import '../theme.dart';
import 'kit.dart';

class GuestNudgeCard extends StatefulWidget {
  const GuestNudgeCard({super.key});

  /// Instelling die onthoudt dat de herinnering al getoond (en weggetikt) is. Begint met "_": blijft op dit toestel.
  static const seenKey = '_guest_nudge';

  /// Vanaf hoeveel gelogde dagen.
  static const minDays = 3;

  /// Tonen? Los van de widget, zodat het zonder Supabase-configuratie te testen is.
  static bool due({required bool configured, required bool signedIn, required bool localOnly, required int loggedDays, required bool seen}) =>
      configured && !signedIn && localOnly && !seen && loggedDays >= minDays;

  /// Voor het dagboek: werkt ook in schermen (tests) zonder [Account].
  static bool shouldShow(BuildContext context, AppState s) {
    final a = context.watch<Account?>();
    if (a == null || !a.localOnly || a.signedIn) return false;
    return due(
      configured: Account.configured,
      signedIn: a.signedIn,
      localOnly: a.localOnly,
      loggedDays: s.user.loggedDays().length,
      seen: s.user.setting(seenKey)?['seen'] == true,
    );
  }

  @override
  State<GuestNudgeCard> createState() => _GuestNudgeCardState();
}

class _GuestNudgeCardState extends State<GuestNudgeCard> {
  bool _hidden = false;

  void _markSeen() {
    context.read<AppState>().user.setSetting(GuestNudgeCard.seenKey, {'seen': true});
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final p = context.pal;
    return Panel(
      key: const ValueKey('guest-nudge'),
      shadow: false,
      radius: 16,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_upload_outlined, color: p.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  runsOnWeb
                      ? tr(
                          'Create a free account to keep your data. Right now it is only in this browser. What you logged comes along.',
                          'Maak een gratis account om je gegevens te bewaren. Nu staan ze alleen in deze browser. Wat je logde, gaat mee.',
                        )
                      : tr(
                          'Create a free account to keep your data. Right now it is only on this device. What you logged comes along.',
                          'Maak een gratis account om je gegevens te bewaren. Nu staan ze alleen op dit toestel. Wat je logde, gaat mee.',
                        ),
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _markSeen, child: Text(tr('Not now', 'Niet nu'))),
              TextButton(
                onPressed: () {
                  _markSeen();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(register: true)));
                },
                child: Text(tr('Create account', 'Account maken')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
