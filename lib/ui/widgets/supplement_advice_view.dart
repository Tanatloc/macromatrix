import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../labs/supplement_advice.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/supplements.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Waarschuwing = driehoek, tekort = ring, in orde = stip (zelfde vormen als elders in de app).
Level _level(AdviceKind k) => switch (k) {
  AdviceKind.warning => Level.high,
  AdviceKind.suggest => Level.low,
  AdviceKind.fine => Level.ok,
};

/// Supplementen afgestemd op je bloedwaarden: één regel per punt, open te klappen. Niets te melden: niets getoond.
class SupplementAdvicePanel extends StatelessWidget {
  const SupplementAdvicePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final advice = s.supplementAdviceList;
    if (advice.isEmpty) return const SizedBox.shrink();
    final days = [for (final a in advice) ?a.labDay]..sort();
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Zonder bloedwaarden gaat het alleen over de bovengrenzen: dan niet "je bloed" in de kop (N71)
              Icon(days.isEmpty ? Icons.health_and_safety_rounded : Icons.bloodtype_rounded, size: 18, color: p.high),
              const SizedBox(width: 8),
              Expanded(
                child: PanelTitle(
                  days.isEmpty ? tr('Safe use', 'Veilig gebruik') : tr('Supplements and your blood', 'Supplementen en je bloed'),
                  subtitle: days.isEmpty
                      ? tr('Safe upper limits', 'Veilige bovengrenzen')
                      : tr('Blood test of ${days.last.split('-').reversed.join('/')}', 'Bloedafname van ${days.last.split('-').reversed.join('/')}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final a in advice) _AdviceRow(a),
        ],
      ),
    );
  }
}

class _AdviceRow extends StatefulWidget {
  const _AdviceRow(this.a);
  final SupplementAdvice a;

  @override
  State<_AdviceRow> createState() => _AdviceRowState();
}

class _AdviceRowState extends State<_AdviceRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = widget.a;
    final level = _level(a.kind);
    final sup = localizedCatalog.where((x) => x.id == a.catalogId).firstOrNull;
    final s = context.read<AppState>();
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusMark(level, size: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
              ],
            ),
            if (_open) ...[
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6),
                child: Text(a.text, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink)),
              ),
              if (sup != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('Add ${sup.name}', '${sup.name} toevoegen')),
                      onPressed: () {
                        s.addSupplement(sup);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('${sup.name} added to your supplements', '${sup.name} toegevoegd aan je supplementen'))),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
