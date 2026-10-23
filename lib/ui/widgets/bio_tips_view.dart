import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/bioavailability.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

Widget _tipRow(BuildContext context, BioTip t) {
  final p = context.pal;
  final warn = t.kind == TipKind.warn;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(warn ? Icons.tips_and_updates_outlined : Icons.check_circle_outline_rounded, size: 20, color: warn ? p.carbs : p.ok),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
              ),
              if (t.mealLabel case final m?)
                Text(
                  m,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.ink3),
                ),
              const SizedBox(height: 2),
              Text(t.text, style: TextStyle(fontSize: 12.5, height: 1.45, color: p.ink2)),
            ],
          ),
        ),
      ],
    ),
  );
}

String get _footnote => tr(
  'Absorption depends on combinations: these tips look at what you ate per meal. Not medical advice.',
  'Opname hangt af van combinaties: deze tips kijken naar wat je per maaltijd at. Geen medisch advies.',
);

/// Alle tips van de dag (Dashboard, dagweergave): compact, tik op een tip voor de uitleg.
class BioTipsCard extends StatefulWidget {
  const BioTipsCard({super.key});

  @override
  State<BioTipsCard> createState() => _BioTipsCardState();
}

class _BioTipsCardState extends State<BioTipsCard> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final tips = s.bioTipsToday;
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Absorption', 'Opname'),
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('About absorption tips', 'Over opnametips'),
              icon: Icon(Icons.info_outline_rounded, size: 18, color: p.ink3),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('Absorption', 'Opname')),
                  content: Text(
                    tr(
                      'How much your body absorbs depends on combinations. Tips appear for example for plant iron without vitamin C, coffee or tea with an iron-rich meal, vitamins A, D, E or K without fat, or too much calcium at once. Not medical advice.',
                      'Hoeveel je lichaam opneemt, hangt af van combinaties. Tips verschijnen bijvoorbeeld bij plantaardig ijzer zonder vitamine C, koffie of thee bij een ijzerrijke maaltijd, vitamine A, D, E of K zonder vet, of te veel calcium in één keer. Geen medisch advies.',
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Close', 'Sluiten')))],
                ),
              ),
            ),
          ),
          if (tips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(tr('No tips for this day.', 'Geen tips voor deze dag.'), style: TextStyle(fontSize: 13, color: p.ink3)),
            ),
          for (final t in tips)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _open.contains(t.title) ? _open.remove(t.title) : _open.add(t.title)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      t.kind == TipKind.warn ? Icons.tips_and_updates_outlined : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: t.kind == TipKind.warn ? p.carbs : p.ok,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                          ),
                          // Bij welke maaltijd, zodat bv. "Voeg vitamine C toe" (lunch) en "IJzer + vitamine C"
                          // (avondeten) niet tegenstrijdig lijken.
                          if (t.mealLabel case final m?) Text(m, style: TextStyle(fontSize: 11.5, color: p.ink3)),
                          if (_open.contains(t.title)) ...[
                            const SizedBox(height: 3),
                            Text(t.text, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink2)),
                          ],
                        ],
                      ),
                    ),
                    Icon(_open.contains(t.title) ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Eén regel op Vandaag met de belangrijkste tip; tik voor alle tips.
class BioTipLine extends StatelessWidget {
  const BioTipLine({super.key, this.bare = false});

  /// Zonder eigen kaart (binnen de kaart "Voor vandaag").
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final tips = s.bioTipsToday;
    if (tips.isEmpty) return const SizedBox.shrink();
    final warn = tips.where((t) => t.kind == TipKind.warn).toList();
    final first = warn.isNotEmpty ? warn.first : tips.first;
    void open() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(tr('Absorption tips', 'Tips voor opname'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              for (final t in tips) _tipRow(ctx, t),
              const SizedBox(height: 6),
              Text(_footnote, style: TextStyle(fontSize: 11.5, color: ctx.pal.ink3)),
            ],
          ),
        ),
      ),
    );
    final row = Row(
      children: [
        Icon(
          first.kind == TipKind.warn ? Icons.tips_and_updates_outlined : Icons.check_circle_outline_rounded,
          size: 20,
          color: first.kind == TipKind.warn ? p.carbs : p.ok,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            first.title +
                (first.mealLabel == null ? '' : ' (${first.mealLabel!.toLowerCase()})') +
                (tips.length > 1 ? tr('  ·  ${tips.length} tips', '  ·  ${tips.length} tips') : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: p.ink3),
      ],
    );
    if (bare) {
      return InkWell(
        onTap: open,
        child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 10, 10), child: row),
      );
    }
    return Panel(shadow: false, radius: 16, padding: const EdgeInsets.fromLTRB(14, 10, 10, 10), onTap: open, child: row);
  }
}
