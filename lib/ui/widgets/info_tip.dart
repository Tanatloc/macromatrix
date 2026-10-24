/// Uitleg bij een (i) of een label: een tik opent een kort venster. Een Tooltip deed bij een tik of klik vaak
/// niets (N34, N39), een venster werkt overal en blijft staan tot je het sluit.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../theme.dart';

/// Opent het uitlegvenster.
Future<void> showInfo(BuildContext context, String title, String message) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close', 'Sluiten')))],
  ),
);

/// Een (i) of ander [child] dat bij een tik [message] uitlegt. Het tikvlak is groter dan het icoon.
class InfoTip extends StatelessWidget {
  const InfoTip({super.key, required this.title, required this.message, this.child, this.size = 15});
  final String title, message;

  /// Wat aan te tikken is; standaard een klein (i).
  final Widget? child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = child == null;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showInfo(context, title, message),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            // Links 4 px zoals de vroegere afstand tot de tekst, rechts niets: de rij wordt niet breder
            padding: icon ? const EdgeInsets.fromLTRB(4, 6, 0, 6) : EdgeInsets.zero,
            child: child ?? Icon(Icons.info_outline_rounded, size: size, color: context.pal.ink3),
          ),
        ),
      ),
    );
  }
}

/// Wat de vier NOVA-groepen betekenen, in gewone taal.
String novaInfo() => tr(
  'NOVA sorts food by how much it was processed, not by its nutrients.\n\n'
      '1 Unprocessed: fresh or simply prepared, like fruit, vegetables, eggs, milk, plain meat.\n'
      '2 Cooking ingredients: oil, butter, sugar, salt, flour.\n'
      '3 Processed: simple foods made from 1 and 2, like cheese, bread, canned vegetables.\n'
      '4 Ultra-processed: industrial products with additives, like soda, sweets, ready meals.',
  'NOVA deelt eten in naar hoe sterk het bewerkt is, niet naar de voedingsstoffen.\n\n'
      '1 Onbewerkt: vers of eenvoudig bereid, zoals fruit, groenten, eieren, melk, gewoon vlees.\n'
      '2 Keukeningrediënten: olie, boter, suiker, zout, bloem.\n'
      '3 Bewerkt: eenvoudige producten uit 1 en 2, zoals kaas, brood, groenten in blik.\n'
      '4 Ultrabewerkt: industriële producten met toevoegingen, zoals frisdrank, snoep, kant-en-klare maaltijden.',
);
