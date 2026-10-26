import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../nutrition/processing.dart';
import '../theme.dart';
import 'info_tip.dart';
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
        // Gaat alleen over ultrabewerkt: bij veel 'bewerkt' (NOVA 3) is "vooral echt eten" niet waar (N56)
        ? (ultra == 0
              ? tr('No ultra-processed food. Great!', 'Geen ultrabewerkt eten. Top!')
              : tr('Little ultra-processed food. Great!', 'Weinig ultrabewerkt eten. Top!'))
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
            tr('Processed food', 'Bewerkt eten'),
            subtitle: period
                ? tr('share of your energy, NOVA', 'deel van je energie, NOVA')
                : tr('share of today\'s energy, NOVA', 'deel van je energie vandaag, NOVA'),
            trailing: InfoTip(title: 'NOVA', message: novaInfo()),
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
            if (share.foods.isNotEmpty) _NovaFoods(foods: share.foods),
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

/// Wat je at per groep, van ultrabewerkt naar onbewerkt (en wat niet in te delen is), met de kcal per product. Per
/// groep eerst de zes grootste; de rest op een tik.
class _NovaFoods extends StatefulWidget {
  const _NovaFoods({required this.foods});
  final List<(String name, Nova? nova, double kcal)> foods;

  @override
  State<_NovaFoods> createState() => _NovaFoodsState();
}

class _NovaFoodsState extends State<_NovaFoods> {
  static const _first = 6;
  final _all = <Nova?>{};

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final groups = [
      for (final n in [Nova.ultra, Nova.processed, Nova.culinary, Nova.unprocessed, null])
        if (widget.foods.where((f) => f.$2 == n).toList() case final list when list.isNotEmpty) (n, list),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(tr('What you ate', 'Wat je at'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink)),
        for (final (n, list) in groups) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: n == null ? p.lineStrong : novaColor(p, n), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n?.label ?? tr('Not classified', 'Niet in te delen'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
              ),
              Text(
                '${fmtInt(list.fold(0.0, (a, f) => a + f.$3))} kcal',
                style: numStyle(12, weight: FontWeight.w500, color: p.ink3),
              ),
            ],
          ),
          for (final (name, _, kcal) in _all.contains(n) ? list : list.take(_first))
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.ink)),
                  ),
                  const SizedBox(width: 8),
                  Text(fmtInt(kcal), style: numStyle(12, weight: FontWeight.w400, color: p.ink3)),
                ],
              ),
            ),
          if (list.length > _first && !_all.contains(n))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 18), visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _all.add(n)),
                child: Text(tr('Show ${list.length - _first} more', 'Nog ${list.length - _first} tonen')),
              ),
            ),
        ],
      ],
    );
  }
}

/// Bewerking (NOVA) op een gsm: ingeklapt één regel met het aandeel ultrabewerkt, een tik toont de hele kaart.
class ProcessingFold extends StatefulWidget {
  const ProcessingFold({super.key, required this.share, this.period = false});
  final ProcessingShare share;

  /// Over een week of maand in plaats van één dag (zie [ProcessingCard.period]).
  final bool period;

  @override
  State<ProcessingFold> createState() => _ProcessingFoldState();
}

class _ProcessingFoldState extends State<ProcessingFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProcessingCard(share: widget.share, period: widget.period),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _open = false),
              icon: const Icon(Icons.expand_less_rounded, size: 18),
              label: Text(tr('Hide', 'Verbergen')),
            ),
          ),
        ],
      );
    }
    final ultra = (widget.share.share(Nova.ultra) * 100).round();
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      onTap: () => setState(() => _open = true),
      child: Row(
        children: [
          Icon(Icons.fastfood_outlined, size: 20, color: p.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Processed food', 'Bewerkt eten'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  tr('$ultra% of your energy ultra-processed', '$ultra% van je energie ultrabewerkt'),
                  style: TextStyle(fontSize: 12.5, color: ultra > 10 ? p.low : p.ink3),
                ),
              ],
            ),
          ),
          Icon(Icons.expand_more_rounded, color: p.ink3),
        ],
      ),
    );
  }
}
