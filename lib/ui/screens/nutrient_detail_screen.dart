import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/user_db.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/day_charts.dart';
import '../widgets/kit.dart';
import 'food_detail_screen.dart';
import '../../i18n.dart';

/// Eén voedingsstof in detail: stand van de dag, verloop, waar het vandaan kwam, de rijkste bronnen ("Oracle")
/// en je eigen doel.
class NutrientDetailScreen extends StatefulWidget {
  const NutrientDetailScreen({super.key, required this.nutrient});
  final Nutrient nutrient;

  @override
  State<NutrientDetailScreen> createState() => _NutrientDetailScreenState();
}

class _NutrientDetailScreenState extends State<NutrientDetailScreen> {
  bool _perKcal = false;
  int _days = 30;

  Nutrient get n => widget.nutrient;

  static String _groupLabel(NutrientGroup g) => switch (g) {
    NutrientGroup.vitamins => tr('Vitamin', 'Vitamine'),
    NutrientGroup.minerals => tr('Mineral', 'Mineraal'),
    NutrientGroup.fats => tr('Fats', 'Vetten'),
    NutrientGroup.protein => tr('Protein and amino acids', 'Eiwit en aminozuren'),
    NutrientGroup.carbs => tr('Carbohydrates', 'Koolhydraten'),
    _ => g.label,
  };

  Future<void> _editTarget() async {
    final s = context.read<AppState>();
    final current = s.targets[n.key];
    final standard = s.defaultTargets[n.key];
    final goal = TextEditingController(text: current?.goal == null ? '' : _plain(current!.goal!));
    final upper = TextEditingController(text: current?.upper == null ? '' : _plain(current!.upper!));
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Goal for ${inSentence(n.name)}', 'Doel voor ${inSentence(n.name)}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: goal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('At least (recommended)', 'Minstens (aanbevolen)'),
                suffixText: n.unit,
                helperText: tr('Empty = no minimum', 'Leeg = geen minimum'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: upper,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('At most (upper limit)', 'Hoogstens (bovengrens)'),
                suffixText: n.unit,
                helperText: tr('Empty = no upper limit', 'Leeg = geen bovengrens'),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('Default (EFSA): ${_describe(standard)}', 'Standaard (EFSA): ${_describe(standard)}'), style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (s.settings.overrides.containsKey(n.key))
            TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: Text(tr('Default', 'Standaard'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Save', 'Opslaan'))),
        ],
      ),
    );
    if (result == 'reset') s.setOverride(n.key, null);
    if (result == 'save') s.setOverride(n.key, Target(goal: parse(goal), upper: parse(upper)));
  }

  String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : double.parse(v.toStringAsFixed(3)).toString().dec;

  String _describe(Target? t) {
    if (t == null || (t.goal == null && t.upper == null)) return tr('no reference value', 'geen richtwaarde');
    return [
      if (t.goal != null) tr('at least ${formatAmount(t.goal!, n)} ${n.unit}', 'minstens ${formatAmount(t.goal!, n)} ${n.unit}'),
      if (t.upper != null) tr('at most ${formatAmount(t.upper!, n)} ${n.unit}', 'hoogstens ${formatAmount(t.upper!, n)} ${n.unit}'),
    ].join(', ');
  }

  /// Hoeveelheid per 100 g, of per 100 kcal (0 voor producten met heel weinig energie, zoals water of thee).
  static double _score(NutrientMap per100g, String key, bool perKcal) {
    final v = per100g[key] ?? 0;
    if (!perKcal) return v;
    final kcal = per100g['energy'] ?? 0;
    return kcal < 15 ? 0 : v / kcal * 100;
  }

  String _amount(double v) => '${formatAmount(v, n)} ${n.unit}';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final target = s.targets[n.key];
    final total = s.totals[n.key];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Narrow(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug')),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(_groupLabel(n.group)),
                          Text(n.name, style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Narrow(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(s, p, target, total),
                    const SizedBox(height: 10),
                    _history(s, p, target),
                    const SizedBox(height: 10),
                    _contributors(s, p, total),
                    const SizedBox(height: 10),
                    _sources(s, p),
                    const SizedBox(height: 10),
                    _targetCard(s, p, target),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(AppState s, Palette p, Target? target, double total) {
    final ref = target?.goal ?? target?.upper;
    final level = levelOf(total, target);
    final f = fractionOf(total, target);

    // "Nog X te gaan": met wat je zelf vaak eet, anders met de rijkste bron uit de database
    String? hint;
    if (target?.goal != null && total < target!.goal! && s.isToday) {
      final need = target.goal! - total;
      final candidates = [
        for (final food in s.recentFoods())
          if ((withDerived(food.per100g)[n.key] ?? 0) > 0) food,
        for (final r in s.richestFor(n.key, limit: 10, advice: true)) r.$1,
      ];
      for (final food in candidates) {
        final per100 = withDerived(food.per100g)[n.key] ?? 0;
        final grams = need / per100 * 100;
        if (grams >= 3 && grams <= 300) {
          hint = tr('about ${fmtInt(grams)} g ${food.name}', 'ongeveer ${fmtInt(grams)} g ${food.name}');
          break;
        }
      }
    }

    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 6,
                  children: [
                    Text(formatAmount(total, n), style: numStyle(44, height: 1)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        ref == null ? n.unit : '/ ${target!.isLimit ? 'max ' : ''}${formatAmount(ref, n)} ${n.unit}',
                        style: numStyle(15, weight: FontWeight.w400, color: p.ink3),
                      ),
                    ),
                  ],
                ),
              ),
              if (f != null)
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: p.softOf(level), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusMark(level, size: 8),
                      const SizedBox(width: 6),
                      Text(fmtPct(f), style: numStyle(12.5, color: p.textOf(level))),
                    ],
                  ),
                ),
            ],
          ),
          if (ref != null) ...[
            const SizedBox(height: 16),
            RangeBar(amount: total, target: target, height: 10),
            const SizedBox(height: 4),
            SizedBox(
              height: 15,
              child: LayoutBuilder(
                builder: (context, c) {
                  final style = numStyle(10.5, weight: FontWeight.w400, color: p.ink3);
                  return Stack(
                    children: [
                      Positioned(left: 0, child: Text('0', style: style)),
                      Positioned(
                        left: c.maxWidth / 1.5 - 40,
                        width: 80,
                        child: Text(
                          '${formatAmount(ref, n)} ${target!.isLimit ? 'max' : tr('goal', 'doel')}',
                          textAlign: TextAlign.center,
                          style: style,
                        ),
                      ),
                      Positioned(right: 0, child: Text(formatAmount(ref * 1.5, n), style: style)),
                    ],
                  );
                },
              ),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: tr('Still ', 'Nog ')),
                  TextSpan(
                    text: _amount(target!.goal! - total),
                    style: numStyle(13.5, color: p.ink),
                  ),
                  TextSpan(text: tr(' to go: ', ' te gaan: ')),
                  TextSpan(
                    text: hint,
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
            ),
          ],
          const SizedBox(height: 14),
          _stats(s),
        ],
      ),
    );
  }

  Widget _stats(AppState s) {
    final to = s.date;
    final daily = s.dailyTotals(to.subtract(const Duration(days: 29)), to);
    double? avg(int days) {
      final keys = [for (var i = 0; i < days; i++) dayKey(to.subtract(Duration(days: i)))];
      final vals = [
        for (final k in keys)
          if (daily[k] case final t?) t[n.key],
      ];
      return vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
    }

    final burned = s.user.exerciseKcalBetween(dayKey(to.subtract(const Duration(days: 29))), dayKey(to));
    final ok = daily.entries.where((e) => levelOf(e.value[n.key], _targetOn(s, e.key, burned)) == Level.ok).length;
    final target = s.targetsForDate(to)[n.key];
    return Row(
      children: [
        Expanded(
          child: StatTile(label: tr('7-day avg.', '7-daags gem.'), value: avg(7) == null ? '–' : _amount(avg(7)!)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: StatTile(label: tr('30-day avg.', '30-daags gem.'), value: avg(30) == null ? '–' : _amount(avg(30)!)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: StatTile(label: tr('Days on target', 'Dagen op doel'), value: target == null ? '–' : '$ok / ${daily.length}'),
        ),
      ],
    );
  }

  /// Doel op een dag; voor energie met de beweging van die dag erbij, zoals op Vandaag.
  Target? _targetOn(AppState s, String day, Map<String, double> burned) => s.targetsForDate(parseDay(day), burned: burned[day] ?? 0)[n.key];

  Widget _history(AppState s, Palette p, Target? target) {
    final to = s.date;
    final from = to.subtract(Duration(days: _days - 1));
    final daily = s.dailyTotals(from, to);
    final keys = [for (var i = 0; i < _days; i++) dayKey(from.add(Duration(days: i)))];
    final values = [for (final k in keys) daily[k]?[n.key]];
    final t = s.targetsForDate(to)[n.key];
    final burned = s.user.exerciseKcalBetween(keys.first, keys.last);

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Last $_days days', 'Laatste $_days dagen'),
            trailing: SizedBox(
              width: 150,
              child: Segmented<int>(
                height: 24,
                fontSize: 11.5,
                items: const [(7, '7d'), (30, '30d'), (90, '90d')],
                selected: _days,
                onChanged: (d) => setState(() => _days = d),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (values.every((v) => v == null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr('No data in this period yet.', 'Nog geen gegevens in deze periode.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.ink3),
              ),
            )
          else ...[
            DayBarsChart(
              values: values,
              goal: t?.goal ?? t?.upper,
              highlightLast: s.isToday,
              colorOf: (v, i) => switch (levelOf(v, _targetOn(s, keys[i], burned))) {
                Level.ok => p.okFill,
                Level.high => p.highFill,
                Level.low => p.lowFill.withValues(alpha: 0.55),
                Level.none => p.ink3.withValues(alpha: 0.4),
              },
            ),
            DayAxis(from: from, days: _days),
            ChartLegend(
              items: [
                if (t?.goal != null) (LegendItem.box(p.okFill), tr('on target', 'op doel')),
                if (t?.goal != null) (LegendItem.box(p.lowFill.withValues(alpha: 0.55)), tr('below target', 'onder doel')),
                if (t?.upper != null) (LegendItem.box(p.highFill), tr('above max', 'boven max')),
                (LegendItem.box(p.brand, w: 14, h: 2), tr('7-day average', '7-daags gemiddelde')),
                if (t != null) (LegendItem.box(p.ink, w: 14, h: 1), t.isLimit ? 'maximum' : tr('goal', 'doel')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _contributors(AppState s, Palette p, double total) {
    final rows = [
      for (final e in s.entries)
        if ((withDerived(e.amounts)[n.key] ?? 0) > 0) (e, withDerived(e.amounts)[n.key]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final top = rows.take(5).toList();
    final rest = rows.skip(5).fold<double>(0, (a, r) => a + r.$2);
    final shares = [for (final r in top) total <= 0 ? 0.0 : r.$2 / total, if (rest > 0) rest / total];

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            s.isToday ? tr('Where it came from', 'Waar kwam het vandaan') : tr('Where it came from on this day', 'Waar kwam het vandaan op deze dag'),
            trailing: Text(
              _amount(total),
              style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr('Nothing eaten with ${inSentence(n.name)} yet.', 'Nog niets gegeten met ${inSentence(n.name)}.'),
                style: TextStyle(color: p.ink2),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            ContributorBar(shares: shares),
            const SizedBox(height: 4),
            for (final (i, (e, v)) in top.indexed)
              _contributorRow(p, i, e.name, '${e.meal.label} · ${fmtInt(e.grams)} g', v, total, i == top.length - 1 && rest <= 0),
            if (rest > 0)
              _contributorRow(p, 99, tr('Other', 'Overige'), tr('${rows.length - 5} products', '${rows.length - 5} producten'), rest, total, true),
          ],
        ],
      ),
    );
  }

  Widget _contributorRow(Palette p, int i, String name, String meta, double v, double total, bool last) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last ? null : Border(bottom: BorderSide(color: p.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: ContributorBar.colorAt(p, i), borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
              ),
              Text(
                meta,
                style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3),
              ),
            ],
          ),
        ),
        Text(_amount(v), style: numStyle(13)),
        SizedBox(
          width: 40,
          child: Text(
            total <= 0 ? '' : fmtPct(v / total),
            textAlign: TextAlign.right,
            style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
          ),
        ),
      ],
    ),
  );

  Widget _sources(AppState s, Palette p) {
    final recentRefs = <String>{};
    final mine = <(Food, double)>[];
    for (final f in s.recentFoods()) {
      if (!recentRefs.add(f.ref)) continue;
      final v = _score(withDerived(f.per100g), n.key, _perKcal);
      if (v > 0) mine.add((f, v));
    }
    mine.sort((a, b) => b.$2.compareTo(a.$2));
    final db = s.richestFor(n.key, perKcal: _perKcal, limit: 12);
    final list = [
      ...mine.take(3),
      for (final r in db)
        if (!mine.take(3).any((m) => m.$1.ref == r.$1.ref)) r,
    ];
    final top = list.isEmpty ? 1.0 : list.map((r) => r.$2).reduce(math.max);

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Richest sources', 'Rijkste bronnen'),
            trailing: SizedBox(
              width: 190,
              child: Segmented<bool>(
                height: 24,
                fontSize: 11.5,
                items: const [(false, 'per 100 g'), (true, 'per 100 kcal')],
                selected: _perKcal,
                onChanged: (v) => setState(() => _perKcal = v),
              ),
            ),
          ),
          if (s.preferences.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Matching: ', 'Passend bij: ') + s.preferences.map((e) => e.label.toLowerCase()).join(', '),
                style: TextStyle(fontSize: 11.5, color: p.ink3),
              ),
            ),
          const SizedBox(height: 4),
          for (final (f, v) in list) _sourceRow(p, f, v, top, recentRefs.contains(f.ref)),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('No sources found.', 'Geen bronnen gevonden.'), style: TextStyle(color: p.ink2)),
            ),
        ],
      ),
    );
  }

  Widget _sourceRow(Palette p, Food f, double v, double top, bool mine) {
    final portion = f.portions.where((x) => x.grams >= 5 && x.grams <= 250).firstOrNull;
    final per100 = withDerived(f.per100g)[n.key] ?? 0;
    final portionText = portion == null ? null : '${portion.label} ≈ ${_amount(per100 * portion.grams / 100)}';
    void open() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(food: f, meal: Meal.forHour(DateTime.now().hour)),
      ),
    );
    return InkWell(
      onTap: open,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SourceBadge(f.source),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(999)),
                          child: Text(tr('you eat often', 'eet je vaker'), style: TextStyle(fontSize: 10.5, color: p.brand)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Bar(fraction: top <= 0 ? 0 : v / top, color: p.brand, height: 4),
                  if (portionText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      portionText,
                      style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text(_amount(v), textAlign: TextAlign.right, style: numStyle(13)),
            ),
            const SizedBox(width: 8),
            StepButton(icon: Icons.add_rounded, tooltip: tr('Add', 'Toevoegen'), size: 32, onTap: open),
          ],
        ),
      ),
    );
  }

  Widget _targetCard(AppState s, Palette p, Target? target) {
    final custom = s.settings.overrides.containsKey(n.key);
    final standard = s.defaultTargets[n.key];
    String describe(Target? t) => t == null || (t.goal == null && t.upper == null)
        ? '–'
        : t.goal != null
        ? _amount(t.goal!)
        : 'max ${_amount(t.upper!)}';

    Widget option({required String label, required String value, required bool selected, required VoidCallback onTap, Widget? trailing}) => Material(
      color: selected ? p.brandSoft : p.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? p.brand : p.line, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w500 : null, color: selected ? p.brand : p.ink3),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numStyle(16, color: selected ? p.ink : p.ink2),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Your goal', 'Jouw doel')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: option(
                  label: tr('EFSA advice', 'EFSA-advies'),
                  value: describe(standard),
                  selected: !custom,
                  onTap: () => s.setOverride(n.key, null),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: option(
                  label: tr('Custom goal', 'Eigen doel'),
                  value: custom ? describe(target) : tr('Set', 'Instellen'),
                  selected: custom,
                  onTap: _editTarget,
                  trailing: Icon(Icons.edit_outlined, size: 16, color: custom ? p.brand : p.ink3),
                ),
              ),
            ],
          ),
          if (target?.upper != null && target?.goal != null) ...[
            const SizedBox(height: 12),
            _note(
              p,
              tr(
                'Upper limit ${_amount(target!.upper!)}${custom ? '' : ' (EFSA)'}: above it the bar turns red.',
                'Bovengrens ${_amount(target.upper!)}${custom ? '' : ' (EFSA)'}: daarboven kleurt de balk rood.',
              ),
            ),
          ],
          if (n.key == 'magnesium') ...[
            const SizedBox(height: 12),
            _note(
              p,
              tr(
                'EFSA sets an upper limit of 250 mg only for supplements and fortified products. Magnesium from regular food does not count towards it.',
                'EFSA zet een bovengrens van 250 mg alleen voor supplementen en verrijkte producten. Magnesium uit gewone voeding telt daarvoor niet mee.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(Palette p, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(padding: EdgeInsets.only(top: 3), child: StatusMark(Level.high, size: 9)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 12, height: 1.45, color: p.ink2)),
      ),
    ],
  );
}
