import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/plan.dart';
import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/nutrient_row.dart';
import 'add_food_screen.dart';
import 'nutrient_detail_screen.dart';
import 'nutrients_screen.dart';
import 'shopping_screen.dart';

/// Maaltijdplanner: zet vooraf klaar wat je (morgen) eet, zie meteen je Voedingsscore en wat er nog ontbreekt,
/// en zet het daarna met één tik in je dagboek.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key, this.day});

  /// Dag om mee te openen; standaard morgen.
  final DateTime? day;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  static DateTime get _today {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day);
  }

  /// Standaard morgen: daarvoor plan je.
  late DateTime _day = widget.day == null
      ? DateTime(_today.year, _today.month, _today.day + 1)
      : DateTime(widget.day!.year, widget.day!.month, widget.day!.day);

  String get _key => dayKey(_day);

  Future<void> _add(Meal meal) async {
    final s = context.read<AppState>();
    final t = await Navigator.of(context)
        .push<ItemTemplate>(MaterialPageRoute(builder: (_) => AddFoodScreen(meal: meal, pickOnly: true, forPlan: true)));
    if (t != null) s.addToPlan(_key, meal, t);
  }

  Future<void> _log() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Put in diary?', 'In je dagboek zetten?')),
        content: Text(
          tr(
            'Everything in this plan goes into your diary for ${_dayLabel(_day)}. You can still change it there.',
            'Alles uit dit plan komt in je dagboek van ${_dayLabel(_day)}. Je kunt het daar nog aanpassen.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Put in diary', 'In dagboek zetten'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = s.logPlan(_key);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$n items added to your diary.', '$n items in je dagboek gezet.'))));
  }

  void _toShopping() {
    final s = context.read<AppState>();
    final n = s.shoppingFromPlans([_key]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('$n products on your shopping list.', '$n producten op je boodschappenlijst.')),
        action: SnackBarAction(
          label: tr('Open', 'Openen'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShoppingScreen())),
        ),
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final diff = daysBetween(_today, d);
    if (diff == 0) return tr('today', 'vandaag');
    if (diff == 1) return tr('tomorrow', 'morgen');
    return DateFormat('EEEE d MMMM', appLocale).format(d);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final items = s.planFor(_key);
    final planned = s.plannedDays.toSet();

    final days = SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 8; i++)
            () {
              final d = DateTime(_today.year, _today.month, _today.day + i);
              final selected = dayKey(d) == _key;
              final label = i == 0 ? tr('Today', 'Vandaag') : (i == 1 ? tr('Tomorrow', 'Morgen') : DateFormat('EEE d', appLocale).format(d));
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _day = d),
                  child: Container(
                    width: 84,
                    decoration: BoxDecoration(
                      color: selected ? p.ink : p.surface,
                      border: Border.all(color: selected ? p.ink : p.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? p.bg : p.ink),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: planned.contains(dayKey(d)) ? (selected ? p.bg : p.brand) : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );

    final meals = [
      for (final meal in Meal.values) ...[
        _mealPanel(p, s, meal, [
          for (final (i, x) in items.indexed)
            if (x.meal == meal) (i, x),
        ]),
        const SizedBox(height: 10),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Meal planner', 'Maaltijdplanner'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            maxWidth: isDesktop(context) ? wideMaxWidth : 760,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Plan what you will eat and see your Nutrient score before you eat it. Then put it in your diary with one tap.',
                      'Plan wat je gaat eten en zie je Voedingsscore nog voor je het eet. Daarna zet je het met één tik in je dagboek.',
                    ),
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                  ),
                  const SizedBox(height: 12),
                  days,
                  const SizedBox(height: 12),
                  SplitColumns(leftFlex: 6, rightFlex: 5, left: meals, right: [_summary(p, s, items)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealPanel(Palette p, AppState s, Meal meal, List<(int, PlannedItem)> list) {
    final kcal = list.fold(0.0, (a, x) => a + x.$2.item.kcal);
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              if (kcal > 0)
                Text(
                  '${fmtInt(kcal)} kcal',
                  style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
                ),
              const SizedBox(width: 4),
              TextButton.icon(onPressed: () => _add(meal), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add', 'Toevoegen'))),
            ],
          ),
          for (final (i, x) in list)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.ink),
                        ),
                        Text(
                          x.item.portionLabel == null
                              ? '${fmtInt(x.item.grams)} g'
                              : '${fmtDec(x.item.quantity, x.item.quantity == x.item.quantity.roundToDouble() ? 0 : 1)} × ${x.item.portionLabel}',
                          style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${fmtInt(x.item.kcal)} kcal',
                    style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
                  ),
                  IconButton(
                    tooltip: tr('Remove', 'Verwijderen'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
                    onPressed: () => s.removeFromPlan(_key, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(Palette p, AppState s, List<PlannedItem> items) {
    final targets = s.targetsForDate(_day);
    final totals = s.planTotals(_key);
    final v = totals.values;
    final score = completenessScore(v, targets);
    final kcal = v['energy'] ?? 0;
    final goal = targets['energy']?.goal ?? 0;
    final low = KeyNutrients.shortfalls(v, targets, limit: 8);
    final fill = items.isEmpty ? null : s.gapPlanFor(v, targets);

    Widget macro(String key, String label, Color c) {
      final g = targets[key]?.goal ?? 0;
      final have = v[key] ?? 0;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: p.ink2)),
            const SizedBox(height: 2),
            Text('${fmtInt(have)} / ${fmtInt(g)} g', style: numStyle(13, color: p.ink)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: g <= 0 ? 0 : (have / g).clamp(0, 1), minHeight: 5, color: c, backgroundColor: p.track),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(
                tr('Plan for ${_dayLabel(_day)}', 'Plan voor ${_dayLabel(_day)}'),
                trailing: Text(
                  'Nutrient score $score',
                  style: numStyle(13, weight: FontWeight.w600, color: p.ink),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(fmtInt(kcal), style: numStyle(26, color: p.ink)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('of ${fmtInt(goal)} kcal', 'van ${fmtInt(goal)} kcal'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.ink2),
                    ),
                  ),
                  if (goal > 0)
                    Text(
                      kcal > goal
                          ? tr('${fmtInt(kcal - goal)} over', '${fmtInt(kcal - goal)} te veel')
                          : tr('${fmtInt(goal - kcal)} left', 'nog ${fmtInt(goal - kcal)}'),
                      style: numStyle(12.5, weight: FontWeight.w500, color: kcal > goal * 1.05 ? p.high : p.ink2),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: goal <= 0 ? 0 : (kcal / goal).clamp(0, 1),
                  minHeight: 7,
                  color: kcal > goal * 1.05 ? p.high : p.brand,
                  backgroundColor: p.track,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  macro('protein', tr('Protein', 'Eiwit'), p.protein),
                  const SizedBox(width: 12),
                  macro('carbs', tr('Carbs', 'Koolhydraten'), p.carbs),
                  const SizedBox(width: 12),
                  macro('fat', tr('Fat', 'Vet'), p.fat),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: items.isEmpty ? null : _log,
                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                    label: Text(tr('Put in diary', 'In dagboek zetten')),
                  ),
                  OutlinedButton.icon(
                    onPressed: items.isEmpty ? null : _toShopping,
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: Text(tr('To shopping list', 'Op boodschappenlijst')),
                  ),
                  if (items.isNotEmpty) TextButton(onPressed: () => s.clearPlan(_key), child: Text(tr('Clear plan', 'Plan wissen'))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Panel(
          shadow: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(tr('Still short in this plan', 'Nog te weinig in dit plan')),
              const SizedBox(height: 4),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    tr('Add something to a meal to see what is still missing.', 'Zet iets bij een maaltijd om te zien wat er nog ontbreekt.'),
                    style: TextStyle(fontSize: 13.5, color: p.ink2),
                  ),
                )
              else if (low.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    tr('This plan reaches all your vitamins and minerals.', 'Met dit plan haal je al je vitaminen en mineralen.'),
                    style: TextStyle(fontSize: 13.5, color: p.ink2),
                  ),
                )
              else
                for (final (i, k) in low.indexed)
                  NutrientRow(
                    first: i == 0,
                    nutrient: nutrientByKey[k]!,
                    amount: v[k],
                    target: targets[k],
                    complete: !totals.incomplete.contains(k),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: nutrientByKey[k]!))),
                  ),
            ],
          ),
        ),
        if (fill != null && fill.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Panel(
            shadow: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelTitle(
                  tr('Fill the gaps', 'Vul je tekorten aan'),
                  subtitle: tr('Nutrient score ${fill.before} → ${fill.after}', 'Voedingsscore ${fill.before} → ${fill.after}'),
                ),
                const SizedBox(height: 4),
                for (final it in fill.items)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.food.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: p.ink),
                            ),
                            Text(
                              '${it.portion?.label ?? '${fmtInt(it.grams)} g'} · ${it.fills.map((f) => f.$1.name.toLowerCase()).take(3).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: p.ink3),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Add to snack', 'Bij snack zetten'),
                        icon: Icon(Icons.add_circle_outline_rounded, color: p.brand),
                        onPressed: () => s.addToPlan(
                          _key,
                          Meal.snacks,
                          ItemTemplate(
                            foodRef: it.food.ref,
                            name: it.food.name,
                            brand: it.food.brand,
                            grams: it.grams,
                            quantity: it.portion == null ? it.grams : it.grams / it.portion!.grams,
                            portionLabel: it.portion?.label,
                            per100g: it.food.per100g,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
