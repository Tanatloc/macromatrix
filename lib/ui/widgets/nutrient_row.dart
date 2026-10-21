import 'package:flutter/material.dart';

import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../theme.dart';
import 'kit.dart';
import '../../i18n.dart';

export '../../nutrition/insights.dart' show Level, levelOf;

/// Eén regel in een overzicht van voedingsstoffen: naam met hoeveelheid / doel, een bereikbalk,
/// het percentage en de status als vorm.
class NutrientRow extends StatelessWidget {
  const NutrientRow({
    super.key,
    this.estimate,
    required this.nutrient,
    required this.amount,
    this.target,
    this.complete = true,
    this.single = false,
    this.onTap,
    this.first = false,
  });

  final Nutrient nutrient;

  /// Tik op de regel (bv. naar het detailscherm van de voedingsstof).
  final VoidCallback? onTap;
  final double? amount;
  final Target? target;

  /// false = sommige producten hadden geen gegevens voor deze stof; het echte totaal ligt waarschijnlijk hoger.
  final bool complete;

  /// Eén product in plaats van een hele dag: "nog niet gehaald" is dan geen probleem en krijgt geen waarschuwing.
  final bool single;

  /// Uitleg als de waarde geschat is (aangevuld uit een andere databank); null = gemeten waarde van de bron.
  final String? estimate;

  /// Eerste regel van een groep: geen lijn erboven.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final value = amount;
    final t = target;
    final ref = t?.goal ?? t?.upper;
    final level = value == null || ref == null ? Level.none : levelOf(value, t);
    final shownLevel = single && level == Level.low ? Level.none : level;
    final pct = (value != null && ref != null && ref > 0) ? value / ref : null;
    final sub = nutrient.indent > 0;

    final amountText = value == null ? '–' : '${estimate == null ? '' : '≈ '}${formatAmount(value, nutrient)}';
    final refText = ref == null ? '' : ' / ${t!.isLimit ? 'max ' : ''}${formatAmount(ref, nutrient)}';

    final detail = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: amountText,
            style: TextStyle(fontStyle: estimate == null ? null : FontStyle.italic, color: estimate == null ? p.ink2 : p.ink),
          ),
          TextSpan(text: '$refText ${nutrient.unit}'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: Padding(
              padding: EdgeInsets.only(left: (nutrient.indent.clamp(0, 3)) * 9.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nutrient.name,
                    // Twee regels: "Enkelvoudig onverzadigd" past niet op één
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: sub ? FontWeight.w400 : FontWeight.w500, color: sub ? p.ink2 : p.ink),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: estimate == null ? detail : Tooltip(message: estimate!, triggerMode: TooltipTriggerMode.tap, child: detail),
                      ),
                      if (!complete && value != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: tr(
                            'For part of what you ate there is no data on ${nutrient.name}. The real total is probably higher.',
                            'Voor een deel van wat je at, zijn er geen gegevens over ${nutrient.name}. Het echte totaal ligt waarschijnlijk hoger.',
                          ),
                          triggerMode: TooltipTriggerMode.tap,
                          child: Icon(Icons.info_outline_rounded, size: 12, color: p.ink3),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ref == null || value == null ? const SizedBox(height: 8) : RangeBar(amount: value, target: t, neutral: single),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    pct == null ? '' : (pct >= 10 ? '>999%' : fmtPct(pct)),
                    maxLines: 1,
                    style: numStyle(12.5, color: shownLevel == Level.ok || shownLevel == Level.none ? p.ink : p.textOf(shownLevel)),
                  ),
                ),
                const SizedBox(width: 6),
                if (pct != null) StatusMark(shownLevel) else const SizedBox(width: 9),
              ],
            ),
          ),
        ],
      ),
    );
    final framed = DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: p.line)),
      ),
      child: row,
    );
    return onTap == null ? framed : InkWell(onTap: onTap, child: framed);
  }
}

/// Volledige lijst per groep (vitaminen, mineralen, ...), voor een dag of voor één product.
class NutrientPanel extends StatelessWidget {
  const NutrientPanel({
    super.key,
    required this.values,
    required this.targets,
    this.incomplete = const {},
    this.estimates = const {},
    this.onlyWithData = false,
    this.single = false,
    this.groups,
    this.onTapNutrient,
    this.hidden = const {},
    this.collapseAmino = true,
  });

  final NutrientMap values;
  final Map<String, Target> targets;

  /// Stoffen waarvan het totaal onvolledig is (zie [NutrientTotals.incomplete]).
  final Set<String> incomplete;

  /// Geschatte waarden: sleutel -> uitleg waar de waarde vandaan komt (zie [NutrientRow.estimate]).
  final Map<String, String> estimates;

  /// Verberg stoffen waarvoor geen enkele waarde bekend is.
  final bool onlyWithData;

  /// Waarden van één product (zie [NutrientRow.single]).
  final bool single;
  final List<NutrientGroup>? groups;

  /// Tik op een voedingsstof.
  final void Function(Nutrient)? onTapNutrient;

  /// Niet tonen (bv. water als je dat niet bijhoudt).
  final Set<String> hidden;

  /// Aminozuren inklappen tot één regel zolang ze allemaal op doel zitten (bijna altijd, en dan is het ruis).
  final bool collapseAmino;

  Widget row(int i, Nutrient n) => NutrientRow(
    first: i == 0,
    nutrient: n,
    amount: values[n.key],
    target: targets[n.key],
    complete: !incomplete.contains(n.key),
    estimate: estimates[n.key],
    single: single,
    onTap: onTapNutrient == null ? null : () => onTapNutrient!(n),
  );

  /// Aminozuren met een doel (de groep eiwit zonder eiwit zelf).
  List<Nutrient> _amino(List<Nutrient> list) => [
    for (final n in list)
      if (n.key != 'protein' && targets[n.key]?.goal != null) n,
  ];

  bool _aminoCollapsed(NutrientGroup g, List<Nutrient> list) {
    if (!collapseAmino || single || g != NutrientGroup.protein || list.first.key != 'protein') return false;
    final amino = _amino(list);
    return amino.isNotEmpty && amino.every((n) => (values[n.key] ?? 0) >= targets[n.key]!.goal!);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups ?? NutrientGroup.values)
          if (nutrients
                  .where((n) => n.group == g && n.key != 'energy' && !hidden.contains(n.key) && (!onlyWithData || values.containsKey(n.key)))
                  .toList()
              case final list when list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                shadow: false,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: PanelTitle(
                        g.label,
                        trailing: single
                            ? null
                            : Text(
                                _summary(list),
                                style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                              ),
                      ),
                    ),
                    if (_aminoCollapsed(g, list)) ...[
                      row(0, list.first),
                      _Collapsed(
                        label: tr(
                          'All ${_amino(list).length} essential amino acids on target',
                          'Alle ${_amino(list).length} essentiële aminozuren op doel',
                        ),
                        children: [for (final (i, n) in list.skip(1).indexed) row(i + 1, n)],
                      ),
                    ] else
                      for (final (i, n) in list.indexed) row(i, n),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  String _summary(List<Nutrient> list) {
    var ok = 0, total = 0;
    for (final n in list) {
      final t = targets[n.key];
      if (t == null || (t.goal == null && t.upper == null)) continue;
      total++;
      if (levelOf(values[n.key] ?? 0, t) == Level.ok) ok++;
    }
    return total == 0 ? '' : tr('$ok / $total on target', '$ok / $total op doel');
  }
}

/// Eén regel die openklapt (bv. de aminozuren als ze allemaal op doel zitten).
class _Collapsed extends StatefulWidget {
  const _Collapsed({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  State<_Collapsed> createState() => _CollapsedState();
}

class _CollapsedState extends State<_Collapsed> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const StatusMark(Level.ok),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.label, style: TextStyle(fontSize: 13, color: p.ink2)),
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
