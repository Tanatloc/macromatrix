import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/processing_card.dart';
import '../widgets/day_charts.dart';
import '../widgets/kit.dart';
import '../widgets/nutrient_row.dart';
import 'nutrient_detail_screen.dart';
import '../../i18n.dart';

/// Trends: energie tegenover je doel, macroverdeling, welke vitaminen en mineralen je structureel mist,
/// je trendgewicht met het geschatte verbruik, en het daggemiddelde van alle voedingsstoffen.
class PeriodTrends extends StatefulWidget {
  const PeriodTrends({super.key, required this.from, required this.to});
  final DateTime from, to;

  @override
  State<PeriodTrends> createState() => _PeriodTrendsState();
}

class _PeriodTrendsState extends State<PeriodTrends> {
  bool _allHeat = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final from = widget.from, to = widget.to;
    final days = DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays + 1;
    final keys = [for (var i = 0; i < days; i++) dayKey(DateTime(from.year, from.month, from.day + i))];
    final daily = s.dailyTotals(from, to);
    // Doelen per dag met de beweging van die dag erbij, zoals op Vandaag
    final burned = s.user.exerciseKcalBetween(keys.first, keys.last);
    final targets = {for (final k in keys) k: s.targetsForDate(parseDay(k), burned: burned[k] ?? 0)};

    final processing = ProcessingCard(share: s.processingBetween(from, to), period: true);

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Op een pc: kaarten twee aan twee, en de gemiddelden in twee kolommen
        final wide = c.maxWidth >= twoColumnWidth;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (daily.isEmpty)
                Panel(
                  child: Text(
                    tr(
                      'Nothing logged in this period yet. Once you track a few days, you will see your progress here.',
                      'Nog niets gelogd in deze periode. Zodra je een paar dagen bijhoudt, zie je hier je verloop.',
                    ),
                    style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                  ),
                )
              else if (wide) ...[
                _minis(p, keys, daily, targets),
                const SizedBox(height: 12),
                pair(_energy(s, p, keys, daily, targets, from), _macros(s, p, keys, daily, from)),
                const SizedBox(height: 12),
                pair(_heatmap(p, keys, daily, targets), _weight(s, p, keys, from)),
                const SizedBox(height: 12),
                pair(processing, const SizedBox()),
                const SizedBox(height: 18),
                _averages(s, p, daily, columns: 2),
              ] else ...[
                _minis(p, keys, daily, targets),
                const SizedBox(height: 10),
                _energy(s, p, keys, daily, targets, from),
                const SizedBox(height: 10),
                _macros(s, p, keys, daily, from),
                const SizedBox(height: 10),
                _heatmap(p, keys, daily, targets),
                const SizedBox(height: 10),
                processing,
                const SizedBox(height: 18),
                _averages(s, p, daily),
              ],
              if (daily.isEmpty || !wide) ...[const SizedBox(height: 10), _weight(s, p, keys, from)],
            ],
          ),
        );
      },
    );
  }

  Widget _energy(
    AppState s,
    Palette p,
    List<String> keys,
    Map<String, NutrientTotals> daily,
    Map<String, Map<String, Target>> targets,
    DateTime from,
  ) {
    final values = [for (final k in keys) daily[k]?['energy']];
    // Basisdoel zonder beweging; dagen met beweging hebben hun eigen, hoger doel
    final goal = s.targetsForDate(parseDay(keys.last))['energy']?.goal ?? 2000;
    // Vandaag is nog bezig: telt niet mee in het gemiddelde
    final today = dayKey(logicalNow());
    final done = [
      for (final k in keys)
        if (k != today && daily[k] != null) (daily[k]!['energy'], targets[k]!['energy']?.goal ?? goal),
    ];
    final avg = done.isEmpty ? null : done.map((d) => d.$1).reduce((a, b) => a + b) / done.length;
    final inBand = done.where((d) => (d.$1 - d.$2).abs() <= d.$2 * 0.1).length;

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Energy', 'Energie')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(boxed: false, label: tr('Average', 'Gemiddeld'), value: avg == null ? '–' : fmtInt(avg)),
              ),
              Expanded(
                child: StatTile(boxed: false, label: tr('Goal', 'Doel'), value: fmtInt(goal)),
              ),
              Expanded(
                child: StatTile(boxed: false, label: tr('Within ±10%', 'Binnen ±10%'), value: '$inBand / ${done.length}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EnergyBars(
            days: [for (final k in keys) parseDay(k)],
            values: values,
            goal: goal,
            goals: [for (final k in keys) targets[k]!['energy']?.goal ?? goal],
          ),
        ],
      ),
    );
  }

  Widget _macros(AppState s, Palette p, List<String> keys, Map<String, NutrientTotals> daily, DateTime from) {
    final splits = [
      for (final k in keys)
        switch (daily[k] == null ? null : macroSplit(daily[k]!.values)) {
          (final pr, final ca, final fa, _) => (pr, ca, fa),
          null => null,
        },
    ];
    final known = splits.whereType<(double, double, double)>().toList();
    double avg(double Function((double, double, double)) pick) => known.isEmpty ? 0 : known.map(pick).reduce((a, b) => a + b) / known.length;
    final prof = s.profileFor(DateTime.now());
    final legend = [
      (tr('Protein', 'Eiwit'), p.protein, avg((x) => x.$1), prof.proteinPct),
      (tr('Carbs', 'Koolhydr.'), p.carbs, avg((x) => x.$2), prof.carbsPct),
      (tr('Fat', 'Vet'), p.fat, avg((x) => x.$3), prof.fatPct),
    ];
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Macro split', 'Macroverdeling'),
            trailing: Text(tr('% of your energy', '% van je energie'), style: TextStyle(fontSize: 11.5, color: p.ink3)),
          ),
          const SizedBox(height: 12),
          SplitBarsChart(splits: splits, target: (prof.proteinPct / 100, prof.carbsPct / 100)),
          DayLabels(days: [for (final k in keys) parseDay(k)]),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, (label, color, a, goal)) in legend.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: p.surface2,
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            LegendItem.box(color),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: p.ink2),
                              ),
                            ),
                          ],
                        ),
                        Text(fmtPct(a), style: numStyle(16)),
                        Text(
                          tr('goal ${goal.round()}%', 'doel ${goal.round()}%'),
                          style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatmap(Palette p, List<String> allKeys, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets) {
    final keys = allKeys.length > 14 ? allKeys.sublist(allKeys.length - 14) : allKeys;
    final logged = keys.where(daily.containsKey).length;
    final candidates = [...stripKeys, 'fiber', 'epa_dha'];

    // Categorie per dag: 0 = < 50%, 1 = 50–99%, 2 = op doel, 3 = boven maximum, null = niet gelogd
    int? category(String day, String key) {
      final t = daily[day];
      final target = targets[day]![key];
      if (t == null || target == null) return null;
      final v = t[key];
      final level = levelOf(v, target);
      if (level == Level.high) return 3;
      if (level == Level.ok) return 2;
      return (fractionOf(v, target) ?? 0) < 0.5 ? 0 : 1;
    }

    final rows = [
      for (final k in candidates)
        if (targets[keys.last]![k] != null) (nutrientByKey[k]!, [for (final d in keys) category(d, k)]),
    ]..sort((a, b) => a.$2.where((c) => c == 2).length.compareTo(b.$2.where((c) => c == 2).length));
    final shown = _allHeat ? rows : rows.take(12).toList();
    final rare = [
      for (final r in rows)
        if (logged >= 5 && r.$2.where((c) => c == 2).length <= logged * 0.25) r.$1,
    ];
    final weekday = isNl ? const ['M', 'D', 'W', 'D', 'V', 'Z', 'Z'] : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    Color cellColor(int? c) => switch (c) {
      0 => p.lowFill,
      1 => p.lowSoft,
      2 => p.okFill,
      3 => p.highFill,
      _ => Colors.transparent,
    };
    String cellText(int? c) => switch (c) {
      0 => tr('less than 50%', 'minder dan 50%'),
      1 => '50–99%',
      2 => tr('on target', 'op doel'),
      3 => tr('above maximum', 'boven maximum'),
      _ => tr('not logged', 'niet gelogd'),
    };

    Widget grid(List<Widget> cells) => Row(
      children: [
        for (final (i, c) in cells.indexed) ...[if (i > 0) const SizedBox(width: 2), Expanded(child: c)],
      ],
    );

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('What you reach, day by day', 'Wat haal je, dag na dag'),
            trailing: Text(tr('last ${keys.length} days', 'laatste ${keys.length} dagen'), style: TextStyle(fontSize: 11.5, color: p.ink3)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 92),
              Expanded(
                child: grid([
                  for (final (i, d) in keys.indexed)
                    Text(
                      weekday[parseDay(d).weekday - 1],
                      textAlign: TextAlign.center,
                      style: numStyle(
                        9.5,
                        weight: i == keys.length - 1 ? FontWeight.w600 : FontWeight.w400,
                        color: i == keys.length - 1 ? p.ink : p.ink3,
                      ),
                    ),
                ]),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  tr('on target', 'op doel'),
                  textAlign: TextAlign.right,
                  style: numStyle(9.5, weight: FontWeight.w400, color: p.ink3),
                ),
              ),
            ],
          ),
          for (final (n, cats) in shown)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NutrientDetailScreen(nutrient: n, from: widget.from, to: widget.to),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        n.key == 'sodium' ? tr('Sodium (max)', 'Natrium (max)') : n.name.replaceAll(RegExp(r'\s*\(.*\)'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.ink),
                      ),
                    ),
                    Expanded(
                      child: grid([
                        for (final (i, c) in cats.indexed)
                          Tooltip(
                            message: '${n.name}, ${DateFormat('EEE d MMM', appLocale).format(parseDay(keys[i]))}: ${cellText(c)}',
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: cellColor(c),
                                borderRadius: BorderRadius.circular(3),
                                border: c == 1 ? Border.all(color: p.lowFill) : (c == null ? Border.all(color: p.line) : null),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    SizedBox(
                      width: 44,
                      child: Builder(
                        builder: (context) {
                          final ok = cats.where((c) => c == 2).length;
                          return Text(
                            '$ok/$logged',
                            textAlign: TextAlign.right,
                            style: numStyle(11.5, color: ok >= logged * 0.7 ? p.ok : (ok >= logged * 0.35 ? p.ink2 : p.low)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (rows.length > 12)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _allHeat = !_allHeat),
                child: Text(_allHeat ? tr('Show less', 'Minder tonen') : tr('Show all ${rows.length}', 'Alle ${rows.length} tonen')),
              ),
            ),
          ChartLegend(
            items: [
              (LegendItem.box(p.lowFill, w: 10, h: 10, radius: 3), '< 50%'),
              (LegendItem.box(p.lowSoft, w: 10, h: 10, radius: 3, border: p.lowFill), '50–99%'),
              (LegendItem.box(p.okFill, w: 10, h: 10, radius: 3), tr('on target', 'op doel')),
              (LegendItem.box(p.highFill, w: 10, h: 10, radius: 3), tr('above max', 'boven max')),
            ],
          ),
          if (rare.isNotEmpty) ...[
            const SizedBox(height: 12),
            Material(
              color: p.lowSoft,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NutrientDetailScreen(nutrient: rare.first, from: widget.from, to: widget.to),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _joinNames(rare.take(3).map((n) => n.name.replaceAll(RegExp(r'\s*\(.*\)'), '')).toList()),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: tr(' you rarely reach. See where to find them.', ' haal je zelden. Bekijk waar je ze vindt.')),
                            ],
                          ),
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: p.ink),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _joinNames(List<String> names) =>
      names.length <= 1 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} ${tr('and', 'en')} ${inSentence(names.last)}';

  Widget _weight(AppState s, Palette p, List<String> keys, DateTime from) {
    final history = {for (final b in s.user.biometricHistory('weight', from: dayKey(from.subtract(const Duration(days: 30))))) b.day: b.value};
    final weights = [for (final k in keys) history[k]];
    // Trend vanaf een maand vóór de periode, zodat de lijn aan het begin al ingelopen is
    final warm = [for (var i = 30; i > 0; i--) dayKey(from.subtract(Duration(days: i)))];
    final trendAll = weightTrend(history, [...warm, ...keys]);
    final trend = trendAll.sublist(warm.length);
    final known = trend.whereType<double>().toList();
    final est = s.energyEstimate;

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Weight', 'Gewicht'),
            trailing: known.length >= 2
                ? Text(
                    '${known.last - known.first < 0 ? '−' : '+'}${fmtDec((known.last - known.first).abs())} kg ${tr('in ${keys.length} days', 'in ${keys.length} dagen')}',
                    style: numStyle(11.5, weight: FontWeight.w400, color: p.ink2),
                  )
                : null,
          ),
          if (weights.every((w) => w == null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr('No weigh-ins in this period yet. Add them under Body.', 'Nog geen wegingen in deze periode. Voeg ze toe bij Lichaam.'),
                style: TextStyle(color: p.ink2),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(known.isEmpty ? '–' : fmtDec(known.last), style: numStyle(30, height: 1.1)),
                const SizedBox(width: 6),
                Text(
                  tr('kg trend weight', 'kg trendgewicht'),
                  style: numStyle(13, weight: FontWeight.w400, color: p.ink3),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message: tr(
                    'A smoothed average of your weigh-ins: fluctuations from water and food drop out, so you see the real direction.',
                    'Een afgevlakt gemiddelde van je wegingen: schommelingen door vocht en eten vallen weg, zodat je de echte richting ziet.',
                  ),
                  child: Icon(Icons.info_outline_rounded, size: 14, color: p.ink3),
                ),
              ],
            ),
            const SizedBox(height: 10),
            WeightChart(weights: weights, trend: trend),
            DayAxis(from: from, days: keys.length),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.surface2,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Estimated expenditure', 'Geschat verbruik'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.ink),
                      ),
                      Text(
                        est == null
                            ? tr(
                                'Not enough data yet: weigh yourself at least 5 times and log 10 complete days within 4 weeks.',
                                'Nog te weinig gegevens: weeg je minstens 5 keer en log 10 volledige dagen binnen 4 weken.',
                              )
                            : tr('From your weight trend and what you logged, last 4 weeks', 'Uit je gewichtstrend en wat je logde, laatste 4 weken'),
                        style: TextStyle(fontSize: 11.5, color: p.ink3),
                      ),
                    ],
                  ),
                ),
                if (est != null) Text('${fmtInt((est.tdee / 10).round() * 10)} kcal', style: numStyle(17)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _minis(Palette p, List<String> keys, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets) {
    final scores = [for (final k in keys) daily[k] == null ? null : completenessScore(daily[k]!.values, targets[k]!).toDouble()];
    final known = scores.whereType<double>().toList();
    final avg = known.isEmpty ? 0 : known.reduce((a, b) => a + b) / known.length;
    final logged = keys.where(daily.containsKey).length;
    final perRow = keys.length <= 7 ? 7 : 16;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Panel(
            shadow: false,
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nutrient score', style: TextStyle(fontSize: 12, color: p.ink2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(known.isEmpty ? '–' : fmtInt(known.last), style: numStyle(22)),
                    const SizedBox(width: 6),
                    Text(
                      tr('avg. ${fmtInt(avg)}', 'gem. ${fmtInt(avg)}'),
                      style: numStyle(11, weight: FontWeight.w400, color: p.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                MiniLine(values: scores, color: p.okFill),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Panel(
            shadow: false,
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Days logged', 'Gelogde dagen'), style: TextStyle(fontSize: 12, color: p.ink2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$logged', style: numStyle(22)),
                    const SizedBox(width: 6),
                    Text(
                      tr('of ${keys.length}', 'van ${keys.length}'),
                      style: numStyle(11, weight: FontWeight.w400, color: p.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, c) {
                    final size = math.min(22.0, (c.maxWidth - (perRow - 1) * 3) / perRow);
                    return Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: [
                        for (final k in keys)
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: daily.containsKey(k) ? (k == dayKey(logicalNow()) ? p.ink : p.brand) : Colors.transparent,
                              border: daily.containsKey(k) ? null : Border.all(color: p.lineStrong, width: 1.5),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Daggemiddelde van alle voedingsstoffen over de gelogde dagen.
  Widget _averages(AppState s, Palette p, Map<String, NutrientTotals> daily, {int columns = 1}) {
    final logged = daily.length;
    final averages = <String, double>{};
    final incomplete = <String>{};
    for (final t in daily.values) {
      for (final e in t.values.entries) {
        averages[e.key] = (averages[e.key] ?? 0) + e.value / logged;
      }
      incomplete.addAll(t.incomplete);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr('Average per day', 'Gemiddeld per dag'),
          trailing: tr('over $logged ${logged == 1 ? 'day' : 'days'}', 'over $logged ${logged == 1 ? 'dag' : 'dagen'}'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            tr(
              'One day low in vitamin C is not a problem; the average over a week or month says more.',
              'Eén dag weinig vitamine C is geen probleem; het gemiddelde over een week of maand zegt meer.',
            ),
            style: TextStyle(fontSize: 12, color: p.ink3),
          ),
        ),
        NutrientPanel(
          values: averages,
          targets: s.targetsForDate(logicalNow()),
          incomplete: incomplete,
          hidden: s.hiddenNutrients,
          columns: columns,
          onTapNutrient: (n) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutrientDetailScreen(nutrient: n, from: widget.from, to: widget.to),
            ),
          ),
        ),
      ],
    );
  }
}
