import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../nutrition/processing.dart';
import '../theme.dart';
import 'kit.dart';

/// Kleur per NOVA-groep: groen (onbewerkt) tot rood (ultrabewerkt).
Color novaColor(Palette p, Nova n) => switch (n) {
  Nova.unprocessed => p.ok,
  Nova.culinary => Color.lerp(p.ok, p.low, 0.5)!,
  Nova.processed => p.low,
  Nova.ultra => p.high,
};

/// Bewerkingsgraad: welk deel van je energie uit ultrabewerkt eten komt, met de verdeling over de vier NOVA-groepen.
class ProcessingCard extends StatelessWidget {
  const ProcessingCard({super.key, required this.share, this.period = false});
  final ProcessingShare share;

  /// Over meerdere dagen (andere tekst).
  final bool period;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ultra = (share.share(Nova.ultra) * 100).round();
    final verdict = ultra <= 10
        ? tr('Mostly real food. Great!', 'Vooral echt eten. Top!')
        : ultra <= 25
        ? tr('Fine. Less is better.', 'Prima. Minder is beter.')
        : ultra <= 50
        ? tr('Quite a lot. Swap one product for something fresh.', 'Vrij veel. Ruil één product voor iets vers.')
        : tr('More than half. Try cooking from fresh ingredients more often.', 'Meer dan de helft. Kook vaker met verse ingrediënten.');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Processing', 'Bewerkingsgraad'),
            subtitle: period
                ? tr('share of your energy, NOVA', 'deel van je energie, NOVA')
                : tr('share of today\'s energy, NOVA', 'deel van je energie vandaag, NOVA'),
          ),
          const SizedBox(height: 10),
          if (!share.meaningful)
            Text(
              tr('Log a bit more to see how processed your food is.', 'Log wat meer om te zien hoe bewerkt je eten is.'),
              style: TextStyle(fontSize: 13, color: p.ink3),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$ultra%', style: numStyle(26, color: novaColor(p, ultra > 25 ? Nova.ultra : (ultra > 10 ? Nova.processed : Nova.unprocessed)))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ultra-processed', 'ultrabewerkt'), style: TextStyle(fontSize: 13.5, color: p.ink2)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(verdict, style: TextStyle(fontSize: 12.5, color: p.ink3)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final n in Nova.values)
                      if (share.share(n) > 0)
                        Expanded(
                          flex: (share.share(n) * 1000).round().clamp(1, 1000),
                          child: Container(color: novaColor(p, n)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final n in Nova.values)
                  LegendItem(
                    swatch: LegendItem.box(novaColor(p, n), w: 10, h: 10, radius: 2),
                    label: '${n.label} ${(share.share(n) * 100).round()}%',
                  ),
              ],
            ),
            if (share.unknown > 0 && share.unknown >= (share.known + share.unknown) * 0.1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(
                    '${((share.unknown / (share.known + share.unknown)) * 100).round()}% of your energy is from products we cannot classify.',
                    '${((share.unknown / (share.known + share.unknown)) * 100).round()}% van je energie komt uit producten die we niet kunnen indelen.',
                  ),
                  style: TextStyle(fontSize: 11.5, color: p.ink3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
