/// De stand van de AI-tellers (etiket lezen, recept importeren) en de uitleg met een knop naar Pro.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../sync/pro.dart';
import '../theme.dart';
import 'pro_widgets.dart';

/// Een etiket lezen: "gratis scan van vandaag gebruikt" met de Pro-knop, of hoeveel er nog over zijn. Een recept
/// importeren: zonder Pro de uitleg met de Pro-knop. Toont niets als er niets te zeggen is.
class AiQuotaNote extends StatelessWidget {
  const AiQuotaNote({super.key, required this.kind, required this.quota, required this.pro});
  final AiKind kind;
  final PhotoQuota? quota;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final q = quota;
    final String? text;
    var upsell = false;
    if (kind.proOnly && !pro) {
      upsell = true;
      text = tr(
        'Importing recipes from a link or a photo is part of Pro. You can still make a recipe yourself, for free.',
        'Recepten importeren uit een link of een foto hoort bij Pro. Zelf een recept maken blijft gratis.',
      );
    } else if (q != null && !q.allowed) {
      upsell = !pro;
      text = switch (kind) {
        AiKind.label when !pro => tr(
          'Free label scan used today, back tomorrow, or go Pro.',
          'Gratis etiketscan van vandaag gebruikt. Morgen kan het weer, of neem Pro.',
        ),
        AiKind.label => tr(
          "That's ${q.limit} label scans today, the most we allow in one day. Tomorrow you can scan again; you can still enter it yourself.",
          'Dat zijn ${q.limit} etiketscans vandaag, het maximum voor één dag. Morgen kan het weer; zelf invullen kan altijd.',
        ),
        AiKind.recipe => tr(
          "That's ${q.limit} recipe imports today, the most we allow in one day. Try again tomorrow.",
          'Dat zijn ${q.limit} geïmporteerde recepten vandaag, het maximum voor één dag. Morgen kan het weer.',
        ),
      };
    } else if (q != null && !pro && kind == AiKind.label) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          key: const ValueKey('ai-quota-left'),
          tr('${q.left} of ${q.limit} free label ${q.limit == 1 ? 'scan' : 'scans'} left today', 'Nog ${q.left} van ${q.limit} gratis etiketscans vandaag'),
          style: TextStyle(fontSize: 12, color: p.ink3),
        ),
      );
    } else {
      text = null;
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      key: ValueKey('ai-quota-out-${kind.name}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(kind == AiKind.label ? Icons.document_scanner_outlined : Icons.menu_book_outlined, size: 18, color: p.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: p.ink2, height: 1.3)),
          ),
          if (upsell) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(key: ValueKey('ai-quota-pro-${kind.name}'), onPressed: () => openProScreen(context), child: const Text('Pro')),
          ],
        ],
      ),
    );
  }
}

/// Tekst bij een fout van /api/label of /api/recipe.
String aiErrorText(String code, {AiKind kind = AiKind.label}) => switch (code) {
  'login' => tr('This needs an account. Log in under Profile → Account.', 'Dit kan alleen met een account. Log in via Profiel → Account.'),
  'not_configured' => tr('This is not available yet.', 'Dit is nog niet beschikbaar.'),
  'pro_required' => tr(
    "Importing recipes is part of Pro, and we couldn't confirm Pro for this account right now.",
    'Recepten importeren hoort bij Pro, en we konden Pro voor dit account nu niet bevestigen.',
  ),
  'quota' =>
    kind == AiKind.label
        ? tr('Free label scan used today, back tomorrow, or go Pro.', 'Gratis etiketscan van vandaag gebruikt. Morgen kan het weer, of neem Pro.')
        : tr('You have imported the most recipes for today. Try again tomorrow.', 'Je hebt vandaag het maximum aan recepten geïmporteerd. Morgen kan het weer.'),
  'too_many' => tr('You have done this a lot this hour. Try again later.', 'Je hebt dit uur al vaak gedaan. Probeer later opnieuw.'),
  'network' || 'timeout' => tr('No connection. Check your internet and try again.', 'Geen verbinding. Kijk je internet na en probeer opnieuw.'),
  'bad_image' || 'too_big' => tr('That photo could not be opened. Try a JPG or PNG.', 'Die foto kon niet geopend worden. Probeer een JPG of PNG.'),
  'unreadable' || 'implausible' => tr(
    "Couldn't read the nutrition table. Try a sharper photo, straight on and well lit, or enter it yourself.",
    'De voedingswaardetabel kon niet gelezen worden. Probeer een scherpere foto, recht van voren en goed belicht, of vul het zelf in.',
  ),
  'no_per100' => tr(
    'The label only shows values per serving, without the serving weight. Enter it yourself.',
    'Het etiket toont alleen waarden per portie, zonder het gewicht van de portie. Vul het zelf in.',
  ),
  'bad_url' => tr('That link does not work. Use a normal web address (https://…).', 'Die link werkt niet. Gebruik een gewoon webadres (https://…).'),
  'not_html' || 'fetch_failed' => tr("Couldn't open that page. Check the link.", 'Die pagina kon niet geopend worden. Kijk de link na.'),
  'no_recipe' => tr('No recipe found there. Try another link or a photo.', 'Daar staat geen recept. Probeer een andere link of een foto.'),
  _ => tr('That did not work. Try again.', 'Dat lukte niet. Probeer opnieuw.'),
};
