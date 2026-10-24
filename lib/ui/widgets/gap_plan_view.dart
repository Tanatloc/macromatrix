import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/gap_plan.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Knop op Vandaag: "What should I still eat?".
class GapPlanButton extends StatelessWidget {
  const GapPlanButton({super.key, this.bare = false});

  /// Zonder eigen kaart (binnen de kaart "Voor vandaag").
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final evening = DateTime.now().hour >= 16;
    Widget wrap(Widget row) => bare
        ? InkWell(
            onTap: () => showGapPlan(context),
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 10, 12), child: row),
          )
        : Panel(
            shadow: false,
            radius: 16,
            color: evening ? p.brandSoft : null,
            borderColor: evening ? p.brandSoft : null,
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            onTap: () => showGapPlan(context),
            child: row,
          );
    return wrap(
      Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('What should I still eat?', 'Wat moet ik nog eten?'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  tr('2 or 3 foods that fill today\'s biggest gaps', '2 à 3 producten die je grootste tekorten van vandaag aanvullen'),
                  style: TextStyle(fontSize: 12, color: p.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.ink3),
        ],
      ),
    );
  }
}

Future<void> showGapPlan(BuildContext context) {
  final plan = context.read<AppState>().gapPlan();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GapPlanSheet(plan: plan),
  );
}

class _GapPlanSheet extends StatefulWidget {
  const _GapPlanSheet({required this.plan});
  final GapPlan? plan;

  @override
  State<_GapPlanSheet> createState() => _GapPlanSheetState();
}

class _GapPlanSheetState extends State<_GapPlanSheet> {
  // De maaltijd die nu komt (niet het ontbijt 's avonds), volgens de logische dag
  late Meal _meal = context.read<AppState>().adviceMeal;
  final _added = <int>{};

  String _amount(PlanItem i) => i.portion == null ? '${fmtInt(i.grams)} g' : '${i.portion!.label} (${fmtInt(i.grams)} g)';

  void _add(PlanItem i, int index) {
    context.read<AppState>().addFood(i.food, meal: _meal, grams: i.grams, quantity: i.portion == null ? i.grams : 1, portionLabel: i.portion?.label);
    setState(() => _added.add(index));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final plan = widget.plan;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(tr('What should I still eat?', 'Wat moet ik nog eten?'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if (plan == null)
              Text(
                tr(
                  'No big gaps left today, or nothing fits within your preferences. Well done!',
                  'Vandaag geen grote tekorten meer, of niets past binnen je voorkeuren. Goed bezig!',
                ),
                style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
              )
            else ...[
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: tr('Nutrient score ', 'Voedingsscore ')),
                    TextSpan(
                      text: '${plan.before} → ${plan.after}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    TextSpan(
                      text: tr(
                        ' with these ${plan.items.length} foods, about ${fmtInt(plan.kcal)} kcal.',
                        ' met deze ${plan.items.length} producten, samen ongeveer ${fmtInt(plan.kcal)} kcal.',
                      ),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
              ),
              const SizedBox(height: 14),
              for (final (i, item) in plan.items.indexed) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.food.name,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                            ),
                            const SizedBox(height: 2),
                            Text('${_amount(item)} · ${fmtInt(item.kcal)} kcal', style: TextStyle(fontSize: 12.5, color: p.ink3)),
                            const SizedBox(height: 6),
                            for (final (n, b, a) in item.fills)
                              Text(
                                '${n.name}: ${fmtPct(b)} → ${a > 2 ? '200%+' : fmtPct(a)}',
                                style: TextStyle(fontSize: 12.5, color: a >= 1 ? p.ok : p.ink2),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _added.contains(i)
                          ? Icon(Icons.check_circle_rounded, color: p.ok)
                          : OutlinedButton(onPressed: () => _add(item, i), child: Text(tr('Add', 'Toevoegen'))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // De percentages tellen op: elk product begint waar het vorige eindigde (NF-5)
              if (plan.items.length > 1)
                Text(
                  tr('Each food builds on the ones above it.', 'Elk product bouwt verder op de producten erboven.'),
                  style: TextStyle(fontSize: 12, color: p.ink3),
                ),
              const SizedBox(height: 6),
              Segmented<Meal>(
                height: 32,
                items: [for (final m in Meal.values) (m, m.label)],
                selected: _meal,
                onChanged: (m) => setState(() => _meal = m),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _added.length == plan.items.length
                    ? () => Navigator.pop(context)
                    : () {
                        for (final (i, item) in plan.items.indexed) {
                          if (!_added.contains(i)) _add(item, i);
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Added to ${_meal.label.toLowerCase()}', 'Toegevoegd aan ${_meal.label.toLowerCase()}'))),
                        );
                      },
                child: Text(
                  _added.length == plan.items.length
                      ? tr('Done', 'Klaar')
                      : tr('Add all to ${_meal.label.toLowerCase()}', 'Alles toevoegen aan ${_meal.label.toLowerCase()}'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Based on your gaps of today, your preferences and what fits in your remaining energy. Not medical advice.',
                  'Op basis van je tekorten van vandaag, je voorkeuren en wat past in je resterende energie. Geen medisch advies.',
                ),
                style: TextStyle(fontSize: 11.5, color: p.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
