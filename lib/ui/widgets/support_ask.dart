// Vriendelijk vragen om Supporter te worden (beslissing 25-10-2026, prijsscenario B): alleen na 7 dagen op rij
// gelogd, hoogstens één keer per 30 dagen, nooit in de eerste 7 dagen op dit toestel (een import kan meteen een
// lange reeks geven), alleen waar je echt kunt kopen, en nooit meer na "Niet meer vragen".
import 'package:flutter/material.dart';

import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../sync/pro.dart';
import 'pro_widgets.dart';

/// Lokale instelling (niet gesynchroniseerd): {first, last, never}.
const supportAskKey = '_support_ask';

const supportAskStreak = 7;
const _quietDays = 30;
const _firstDays = 7;

/// Het begin van de 7 dagen op dit toestel onthouden (bij het opstarten).
void noteFirstUse(UserDb db, {DateTime? now}) {
  final s = db.setting(supportAskKey) ?? const {};
  if (s['first'] == null) db.setSetting(supportAskKey, {...s, 'first': (now ?? DateTime.now()).millisecondsSinceEpoch});
}

/// Mag de app nu vragen? Zet bij de eerste keer ook het begin van de 7 dagen op dit toestel.
bool shouldAskSupport(UserDb db, {required int streak, required bool isPro, required bool canBuy, DateTime? now}) {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final s = db.setting(supportAskKey) ?? const {};
  final first = (s['first'] as num?)?.toInt();
  if (first == null) {
    db.setSetting(supportAskKey, {...s, 'first': t});
    return false;
  }
  if (s['never'] == true || isPro || !canBuy || streak < supportAskStreak) return false;
  if (t - first < const Duration(days: _firstDays).inMilliseconds) return false;
  final last = (s['last'] as num?)?.toInt();
  return last == null || t - last >= const Duration(days: _quietDays).inMilliseconds;
}

/// Het venster. Onthoudt meteen dat er gevraagd werd (ook als je het wegveegt).
Future<void> askSupport(BuildContext context, UserDb db, {required int streak, DateTime? now}) async {
  final s = db.setting(supportAskKey) ?? const {};
  db.setSetting(supportAskKey, {...s, 'last': (now ?? DateTime.now()).millisecondsSinceEpoch});
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('support-ask'),
      icon: const Icon(Icons.favorite_rounded, color: Color(0xFFE0457B)),
      title: Text(tr('$streak days in a row!', '$streak dagen op rij!')),
      content: Text(
        tr(
          'Glad MacroMatrix helps you. It is free and has no ads. Supporters keep it that way, and get extras such as more photo logging.',
          "Fijn dat MacroMatrix je helpt. De app is gratis en zonder reclame. Supporters houden dat zo, en krijgen extra's zoals meer loggen met een foto.",
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('support-ask-never'), onPressed: () => Navigator.pop(ctx, 'never'), child: Text(tr("Don't ask again", 'Niet meer vragen'))),
        TextButton(key: const ValueKey('support-ask-later'), onPressed: () => Navigator.pop(ctx, 'later'), child: Text(tr('Not now', 'Nu niet'))),
        FilledButton(key: const ValueKey('support-ask-see'), onPressed: () => Navigator.pop(ctx, 'see'), child: Text(tr('See Supporter', 'Bekijk Supporter'))),
      ],
    ),
  );
  if (choice == 'never') db.setSetting(supportAskKey, {...?db.setting(supportAskKey), 'never': true});
  if (choice == 'see' && context.mounted) openProScreen(context);
}

/// Na een mijlpaal in je reeks: vragen als het mag (Pro en de winkel uit de context).
void maybeAskSupport(BuildContext context, UserDb db, {required int streak, required Pro? pro}) {
  // Kopen kan alleen als de winkel en de server klaarstaan (zelfde regel als het Supporter-scherm)
  final canBuy = pro != null && pro.available && pro.purchases.available;
  if (shouldAskSupport(db, streak: streak, isPro: pro?.isPro ?? false, canBuy: canBuy)) {
    askSupport(context, db, streak: streak);
  }
}
