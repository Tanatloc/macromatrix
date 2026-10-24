/// Kleine onderdelen voor Pro: het Supporter-badge, het Pro-label bij iets wat bij Pro hoort, en de stand van de
/// fototeller in Snel loggen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../sync/pro.dart';
import '../screens/pro_screen.dart';
import '../theme.dart';
import 'kit.dart';

/// Pro, als het er is. Schermen die zonder (bv. in tests) gebouwd worden, krijgen null en gedragen zich als gratis.
Pro? proOf(BuildContext context, {bool listen = true}) => listen ? context.watch<Pro?>() : context.read<Pro?>();

void openProScreen(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProScreen()));

/// Warm goud voor supporters, los van de merkkleur (die kan zelf een andere kleur zijn).
(Color, Color) _gold(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? (const Color(0xFFE5B85C), const Color(0xFF2E2510))
    : (const Color(0xFF835C00), const Color(0xFFF6EDD6));

/// "Supporter" naast een naam. Met [compact] alleen het hartje (met uitleg bij lang indrukken), voor smalle rijen.
class SupporterBadge extends StatelessWidget {
  const SupporterBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _gold(context);
    final label = tr('Supporter', 'Supporter');
    if (compact) {
      return Tooltip(
        message: tr('Supporter: helps keep MacroMatrix free', 'Supporter: helpt MacroMatrix gratis te houden'),
        child: Semantics(
          label: label,
          child: Container(
            key: const ValueKey('supporter-badge'),
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.favorite_rounded, size: 12, color: fg),
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('supporter-badge'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Klein "Pro"-label bij iets wat alleen met Pro kan.
class ProTag extends StatelessWidget {
  const ProTag({super.key});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _gold(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        'Pro',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Onder de fotoknop in Snel loggen: hoeveel gratis foto's je vandaag nog hebt, of een vriendelijke uitleg als ze op
/// zijn (met een knop naar Pro). Toont niets als de stand onbekend is (geen account, offline of geen migratie).
class PhotoQuotaNote extends StatelessWidget {
  const PhotoQuotaNote({super.key, required this.quota, required this.pro});
  final PhotoQuota? quota;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final q = quota;
    final p = context.pal;
    if (q == null) return const SizedBox.shrink();
    if (q.allowed) {
      // Met Pro is de rem van 50 per dag ruim genoeg: niets tonen
      if (pro) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          key: const ValueKey('photo-quota-left'),
          tr('${q.left} of ${q.limit} free ${q.limit == 1 ? 'photo' : 'photos'} left today', "Nog ${q.left} van ${q.limit} gratis foto's vandaag"),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, color: p.ink3),
        ),
      );
    }
    final text = pro
        ? tr(
            "That's ${q.limit} photos today, the most we allow in one day. You can log with a photo again tomorrow; typing or speaking works as always.",
            "Dat zijn ${q.limit} foto's vandaag, het maximum voor één dag. Morgen kan het weer; typen of inspreken werkt gewoon.",
          )
        : tr(
            "You've used your ${q.limit} free photos for today. They're back tomorrow. You can still type or say what you ate, "
                'or get unlimited photos with Pro.',
            "Je ${q.limit} gratis foto's van vandaag zijn op. Morgen heb je er weer ${q.limit}. Je kunt nog altijd typen of zeggen wat je at, "
                "of onbeperkt foto's gebruiken met Pro.",
          );
    return Container(
      key: const ValueKey('photo-quota-out'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.photo_camera_outlined, size: 18, color: p.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: p.ink2, height: 1.3)),
          ),
          if (!pro) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(key: const ValueKey('photo-quota-pro'), onPressed: () => openProScreen(context), child: const Text('Pro')),
          ],
        ],
      ),
    );
  }
}

/// Naar het Pro-scherm, met je status in één regel (in Instellingen en in het Profiel).
class ProTile extends StatelessWidget {
  const ProTile({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final pro = proOf(context);
    final isPro = pro?.isPro ?? false;
    return Panel(
      key: const ValueKey('pro-tile'),
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => openProScreen(context),
      child: Row(
        children: [
          Icon(isPro ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: pal.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MacroMatrix Pro',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                Text(
                  isPro
                      ? tr('Thank you for supporting MacroMatrix', 'Bedankt om MacroMatrix te steunen')
                      : tr(
                          'Unlimited photo logging and supporter extras. Everything else stays free.',
                          "Onbeperkt loggen met foto's en extra's voor supporters. Al de rest blijft gratis.",
                        ),
                  style: TextStyle(fontSize: 12.5, color: pal.ink2),
                ),
              ],
            ),
          ),
          if (pro?.supporter ?? false) const SupporterBadge(compact: true),
          Icon(Icons.chevron_right_rounded, color: pal.ink3),
        ],
      ),
    );
  }
}
