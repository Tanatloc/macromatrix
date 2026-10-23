import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, toBeginningOfSentenceCase;
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
import 'oracle_screen.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

/// Eén voedingsstof in detail: stand van de dag, verloop, waar het vandaan kwam, de rijkste bronnen ("Oracle")
/// en je eigen doel. Met [from] en [to] (vanuit het dashboard, week of maand) toont het het daggemiddelde van die
/// periode in plaats van de gekozen dag.
class NutrientDetailScreen extends StatefulWidget {
  const NutrientDetailScreen({super.key, required this.nutrient, this.from, this.to});
  final Nutrient nutrient;
  final DateTime? from, to;

  @override
  State<NutrientDetailScreen> createState() => _NutrientDetailScreenState();
}

class _NutrientDetailScreenState extends State<NutrientDetailScreen> {
  bool _perKcal = false;
  late int _days = _isPeriod && _periodDays <= 7 ? 7 : 30;

  Nutrient get n => widget.nutrient;

  /// Geopend voor een week of maand in plaats van één dag.
  bool get _isPeriod => widget.from != null && widget.to != null;
  int get _periodDays => _isPeriod ? _dateOnly(widget.to!).difference(_dateOnly(widget.from!)).inDays + 1 : 1;
  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Laatste dag van wat je bekijkt: het einde van de periode, of de gekozen dag.
  DateTime _end(AppState s) => _isPeriod ? widget.to! : s.date;

  bool _isTodayDate(DateTime d) {
    final now = logicalNow();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Gemiddelde per gelogde dag in de periode, en het aantal gelogde dagen.
  (double, int) _periodAverage(AppState s) {
    final daily = s.dailyTotals(widget.from!, widget.to!);
    if (daily.isEmpty) return (0, 0);
    return (daily.values.fold<double>(0, (a, t) => a + t[n.key]) / daily.length, daily.length);
  }

  /// Welke dag of periode je ziet, bovenaan de grote kaart.
  String _viewLabel(AppState s) {
    if (_isPeriod) {
      final f = DateFormat('d MMM', appLocale);
      final from = widget.from!, to = widget.to!;
      final range = from.year == to.year && from.month == to.month && from.day == to.day ? f.format(from) : '${f.format(from)} – ${f.format(to)}';
      return tr('Average per day · $range', 'Gemiddeld per dag · $range');
    }
    final now = logicalNow();
    final diff = (s.date.difference(DateTime(now.year, now.month, now.day)).inHours / 24).round();
    return switch (diff) {
      0 => tr('Today', 'Vandaag'),
      -1 => tr('Yesterday', 'Gisteren'),
      _ => toBeginningOfSentenceCase(DateFormat(s.date.year == now.year ? 'EEEE d MMMM' : 'EEEE d MMMM yyyy', appLocale).format(s.date)),
    };
  }

  /// Energie en macro's volgen je eigen verdeling (profiel), de rest de EFSA-richtwaarden.
  bool get _fromPlan => const {'energy', 'protein', 'carbs', 'fat'}.contains(n.key);
  String get _sourceLabel => _fromPlan ? tr('From your plan', 'Uit je plan') : tr('EFSA advice', 'EFSA-advies');

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
    double? parse(TextEditingController c) => parseNum(c.text);
    String? goalError, upperError;
    // Leeg mag (geen grens), maar geen tekst, geen negatief getal en geen minimum boven het maximum
    bool validate() {
      String? check(TextEditingController c) => c.text.trim().isEmpty ? null : rangeError(c.text, 0, 1e6, unit: n.unit);
      goalError = check(goal);
      upperError = check(upper);
      final g = parse(goal), u = parse(upper);
      if (goalError == null && upperError == null && g != null && u != null && g > u) {
        upperError = tr('Must be at least the minimum (${_plain(g)} ${n.unit})', 'Moet minstens het minimum zijn (${_plain(g)} ${n.unit})');
      }
      return goalError == null && upperError == null;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Goal for ${inSentence(n.name)}', 'Doel voor ${inSentence(n.name)}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: goal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalInput,
                onTap: selectAllOnTap(goal),
                decoration: InputDecoration(
                  labelText: tr('At least (recommended)', 'Minstens (aanbevolen)'),
                  suffixText: n.unit,
                  helperText: tr('Empty = no minimum', 'Leeg = geen minimum'),
                  errorText: goalError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: upper,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalInput,
                onTap: selectAllOnTap(upper),
                decoration: InputDecoration(
                  labelText: tr('At most (upper limit)', 'Hoogstens (bovengrens)'),
                  suffixText: n.unit,
                  helperText: tr('Empty = no upper limit', 'Leeg = geen bovengrens'),
                  errorText: upperError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _fromPlan
                    ? tr('Default (from your plan): ${_describe(standard)}', 'Standaard (uit je plan): ${_describe(standard)}')
                    : tr('Default (EFSA): ${_describe(standard)}', 'Standaard (EFSA): ${_describe(standard)}'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            if (s.settings.overrides.containsKey(n.key))
              TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: Text(tr('Default', 'Standaard'))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(
              onPressed: () {
                var ok = false;
                setD(() => ok = validate());
                if (ok) Navigator.pop(ctx, 'save');
              },
              child: Text(tr('Save', 'Opslaan')),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    // Een eigen grens is werk: wie per ongeluk op Standaard tikt, kan terug
    final before = s.settings.overrides[n.key];
    s.setOverride(n.key, result == 'reset' ? null : Target(goal: parse(goal), upper: parse(upper)));
    showUndo(context, tr('Goal for ${inSentence(n.name)} changed', 'Doel voor ${inSentence(n.name)} aangepast'), () => s.setOverride(n.key, before));
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
    final target = _isPeriod ? s.targetsForDate(widget.to!)[n.key] : s.targets[n.key];
    final (total, logged) = _isPeriod ? _periodAverage(s) : (s.totals[n.key], 1);

    return Scaffold(
      body: SafeArea(
        // De kop met terug-knop blijft staan, de rest scrolt eronder (zoals de dagbalk in het dagboek)
        child: Column(
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Narrow(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _hero(s, p, target, total, logged),
                          const SizedBox(height: 10),
                          _history(s, p, target),
                          const SizedBox(height: 10),
                          _isPeriod ? _periodContributors(s, p, total, logged) : _contributors(s, p, total),
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
          ],
        ),
      ),
    );
  }

  Widget _hero(AppState s, Palette p, Target? target, double total, int logged) {
    final ref = target?.goal ?? target?.upper;
    final level = levelOf(total, target);
    final f = fractionOf(total, target);

    // "Nog X te gaan": met wat je zelf vaak eet, anders met de rijkste bron uit de database
    String? hint;
    if (!_isPeriod && target?.goal != null && total < target!.goal! && s.isToday) {
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
          // Welke dag (of periode) dit is: vanuit het dashboard kan dat een andere dag zijn dan vandaag
          Row(
            children: [
              Expanded(child: Eyebrow(_viewLabel(s))),
              if (_isPeriod)
                Text(
                  tr(
                    '$logged of $_periodDays ${_periodDays == 1 ? 'day' : 'days'} logged',
                    '$logged van $_periodDays ${_periodDays == 1 ? 'dag' : 'dagen'} gelogd',
                  ),
                  style: numStyle(11, weight: FontWeight.w400, color: p.ink3),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
    final to = _end(s);
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
    final to = _end(s);
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
              highlightLast: _isTodayDate(to),
              colorOf: (v, i) => switch (levelOf(v, _targetOn(s, keys[i], burned))) {
                Level.ok => p.okFill,
                Level.high => p.highFill,
                Level.low => p.lowFill.withValues(alpha: 0.55),
                Level.none => p.ink3.withValues(alpha: 0.4),
              },
            ),
            // Bij 7 dagen passen de getallen onder de staven
            if (_days <= 7)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    for (final v in values)
                      Expanded(
                        child: Text(
                          v == null ? '–' : formatAmount(v, n),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: numStyle(10.5, color: p.ink2),
                        ),
                      ),
                  ],
                ),
              ),
            if (_days <= 7) DayLabels(days: [for (var i = 0; i < _days; i++) from.add(Duration(days: i))]) else DayAxis(from: from, days: _days),
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
        if ((s.entryValues(e)[n.key] ?? 0) > 0) (e, s.entryValues(e)[n.key]!),
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

  /// Waar het vandaan kwam over de hele periode: per product, gemiddeld per gelogde dag.
  Widget _periodContributors(AppState s, Palette p, double total, int logged) {
    final sums = <String, (String, double, int)>{};
    for (final e in s.user.entriesBetween(dayKey(widget.from!), dayKey(widget.to!))) {
      final v = s.entryValues(e)[n.key] ?? 0;
      if (v <= 0) continue;
      final key = '${e.foodRef}|${e.name}';
      final prev = sums[key];
      sums[key] = (e.name, (prev?.$2 ?? 0) + v, (prev?.$3 ?? 0) + 1);
    }
    final rows = [for (final (name, sum, count) in sums.values) (name, logged == 0 ? 0.0 : sum / logged, count)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final top = rows.take(5).toList();
    final rest = rows.skip(5).fold<double>(0, (a, r) => a + r.$2);
    final shares = [for (final r in top) total <= 0 ? 0.0 : r.$2 / total, if (rest > 0 && total > 0) rest / total];

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Where it came from in this period', 'Waar kwam het vandaan in deze periode'),
            subtitle: tr('Average per logged day', 'Gemiddeld per gelogde dag'),
            trailing: Text(
              _amount(total),
              style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr('Nothing eaten with ${inSentence(n.name)} in this period.', 'Niets gegeten met ${inSentence(n.name)} in deze periode.'),
                style: TextStyle(color: p.ink2),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            ContributorBar(shares: shares),
            const SizedBox(height: 4),
            for (final (i, (name, v, count)) in top.indexed)
              _contributorRow(p, i, name, tr('$count× logged', '$count× gelogd'), v, total, i == top.length - 1 && rest <= 0),
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
    // Vrije suiker wordt per gelogd product geschat, niet in de databank bewaard: geen lijst, wel uitleg
    if (n.key == 'free_sugars') {
      return Panel(
        child: Text(
          tr(
            'Free sugar is mostly in soft drinks, fruit juice, sweets, biscuits, cake and sweetened yoghurt or cereals. Sugar in whole fruit, vegetables and plain milk does not count.',
            'Vrije suiker zit vooral in frisdrank, fruitsap, snoep, koeken, gebak en gezoete yoghurt of ontbijtgranen. Suiker in heel fruit, groenten en gewone melk telt niet mee.',
          ),
          style: TextStyle(fontSize: 13.5, color: p.ink2, height: 1.4),
        ),
      );
    }
    final isLimit = s.targets[n.key]?.isLimit ?? false;
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
            // Bij een stof waarvan minder beter is (zout, suiker, verzadigd vet) is dit geen aanrader maar een waarschuwing
            isLimit ? tr('Highest in ${inSentence(n.name)}', 'Meeste ${inSentence(n.name)}') : tr('Richest sources', 'Rijkste bronnen'),
            subtitle: isLimit
                ? tr('Less of this is better — these foods have the most.', 'Minder hiervan is beter — deze producten bevatten het meest.')
                : null,
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(tr('More in the Oracle', 'Meer in het Orakel')),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OracleScreen(nutrient: n.key))),
            ),
          ),
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
                child: option(label: _sourceLabel, value: describe(standard), selected: !custom, onTap: () => s.setOverride(n.key, null)),
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
                'Upper limit ${_amount(target!.upper!)}${custom || _fromPlan ? '' : ' (EFSA)'}: above it the bar turns red.',
                'Bovengrens ${_amount(target.upper!)}${custom || _fromPlan ? '' : ' (EFSA)'}: daarboven kleurt de balk rood.',
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
