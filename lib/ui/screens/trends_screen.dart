import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../nutrition/health.dart' show isFullDay;
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

  /// Volledig gelogde dagen vóór vandaag: de basis voor alle tellers en gemiddelden (zie [_basis]).
  Set<String> _full = const {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final from = widget.from, to = widget.to;
    final days = DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays + 1;
    final keys = [for (var i = 0; i < days; i++) dayKey(DateTime(from.year, from.month, from.day + i))];
    final daily = s.dailyTotals(from, to);
    // Doelen per dag met de beweging van die dag erbij, zoals op Vandaag: een vroegere dag houdt het doel van toen
    final targets = s.targetsBetween(from, to);
    // Eén basis voor alle tellers en gemiddelden, zoals in het weekrapport: volledig gelogde dagen, nooit vandaag
    // (die loopt nog). Zonder één volledige dag tonen de gemiddelden wat je wel logde.
    final today = dayKey(logicalNow());
    final full = [
      for (final k in keys)
        if (k != today && daily[k] != null && isFullDay(daily[k]!, targets[k]!)) k,
    ];
    final partial = [
      for (final k in keys)
        if (k != today && daily[k] != null && !full.contains(k)) k,
    ];
    _full = full.toSet();

    final processing = ProcessingCard(share: s.processingBetween(from, to), period: true);
    // Suiker per dag alleen in de weekweergave; met "Let op suiker" bovenaan
    final sugar = days <= 7 && daily.isNotEmpty ? _sugar(s, p, keys, daily, targets) : null;
    final sugarFirst = sugar != null && s.sugarFocus;

    final basis = Padding(padding: const EdgeInsets.only(bottom: 8), child: _basis(p, full.length, partial.length, daily.containsKey(today)));

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
                basis,
                _minis(p, keys, daily, targets),
                const SizedBox(height: 12),
                if (sugarFirst) ...[pair(sugar, processing), const SizedBox(height: 12)],
                // Gewicht in de bovenste rij, naast energie: het stond na alle voedingsstoffen (N44)
                pair(_energy(s, p, keys, daily, targets, from), _weight(s, p, keys, from, logged: daily.isNotEmpty)),
                const SizedBox(height: 12),
                pair(_heatmap(p, keys, daily, targets), _macros(s, p, keys, daily, targets)),
                if (!sugarFirst) ...[const SizedBox(height: 12), pair(processing, sugar ?? const SizedBox())],
                const SizedBox(height: 18),
                _averages(s, p, daily, targets, columns: 2),
              ] else ...[
                basis,
                _minis(p, keys, daily, targets),
                const SizedBox(height: 10),
                if (sugarFirst) ...[sugar, const SizedBox(height: 10)],
                _energy(s, p, keys, daily, targets, from),
                const SizedBox(height: 10),
                // Gewicht meteen na energie in plaats van onderaan (N44)
                _weight(s, p, keys, from, logged: daily.isNotEmpty),
                const SizedBox(height: 10),
                _macros(s, p, keys, daily, targets),
                const SizedBox(height: 10),
                _heatmap(p, keys, daily, targets),
                if (sugar != null && !sugarFirst) ...[const SizedBox(height: 10), sugar],
                const SizedBox(height: 10),
                processing,
                const SizedBox(height: 18),
                _averages(s, p, daily, targets),
              ],
              if (daily.isEmpty) ...[const SizedBox(height: 10), _weight(s, p, keys, from, logged: daily.isNotEmpty)],
            ],
          ),
        );
      },
    );
  }

  /// Eén regel bovenaan: op hoeveel dagen de tellers en gemiddelden steunen, met vandaag apart.
  Widget _basis(Palette p, int full, int partial, bool today) {
    // Alleen vandaag gelogd (je eerste dag van de periode): geen rij streepjes zonder uitleg (NW-18)
    final onlyToday = full == 0 && partial == 0 && today;
    final parts = [
      if (onlyToday)
        tr(
          'Today is logged. Averages, the ±10% count and the score start tomorrow, once today is over',
          'Vandaag is gelogd. Gemiddelden, de telling binnen ±10% en de score beginnen morgen, als vandaag voorbij is',
        )
      else ...[
        full == 0
            ? tr(
                'No fully logged days yet: averages use what you logged so far',
                'Nog geen volledig gelogde dagen: gemiddelden over wat je tot nu logde',
              )
            : tr('Based on $full fully logged ${full == 1 ? 'day' : 'days'}', 'Op basis van $full volledig gelogde ${full == 1 ? 'dag' : 'dagen'}'),
        if (today) tr('today counts from tomorrow', 'vandaag telt vanaf morgen'),
        if (partial > 0)
          tr('$partial ${partial == 1 ? 'day' : 'days'} with too little logged', '$partial ${partial == 1 ? 'dag' : 'dagen'} met te weinig gelogd'),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(parts.join(' · '), style: TextStyle(fontSize: 12, color: p.ink3)),
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
    // Alleen volledig gelogde dagen (zie [_basis]): een half gelogde dag of vandaag is nooit "binnen ±10%"
    final done = [
      for (final k in keys)
        if (_full.contains(k)) (daily[k]!['energy'], targets[k]!['energy']?.goal ?? goal),
    ];
    final avg = done.isEmpty ? null : done.map((d) => d.$1).reduce((a, b) => a + b) / done.length;
    final inBand = done.where((d) => withinEnergyMargin(d.$1, d.$2)).length;
    // Veranderde je doel in deze periode, dan het gemiddelde doel van de gelogde dagen (zonder beweging), zodat het
    // naast het gemiddelde past
    final baseGoals = [
      for (final k in keys)
        if (daily[k] != null || k == keys.last) s.targetsForDate(parseDay(k))['energy']?.goal ?? goal,
    ];
    final changed = baseGoals.any((g) => (g - goal).abs() >= 1);
    final shownGoal = changed ? baseGoals.reduce((a, b) => a + b) / baseGoals.length : goal;

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
                child: StatTile(boxed: false, label: changed ? tr('Goal, avg.', 'Doel, gem.') : tr('Goal', 'Doel'), value: fmtInt(shownGoal)),
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

  Widget _macros(AppState s, Palette p, List<String> keys, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets) {
    final splits = [
      for (final k in keys)
        switch (daily[k] == null ? null : macroSplit(daily[k]!.values)) {
          (final pr, final ca, final fa, _) => (pr, ca, fa),
          null => null,
        },
    ];
    final known = splits.whereType<(double, double, double)>().toList();
    double avg(double Function((double, double, double)) pick) => known.isEmpty ? 0 : known.map(pick).reduce((a, b) => a + b) / known.length;
    // Doelverdeling uit de echte grammen van elke dag (het doel van toen), gemiddeld over de gelogde dagen
    final goalDays = [
      for (final k in keys)
        if (daily[k] != null) targets[k]!,
    ];
    double goalShare(String key) {
      final days = goalDays.isEmpty ? [targets[keys.last]!] : goalDays;
      double one(Map<String, Target> t) => macroShare(key, t[key]?.goal ?? t[key]?.upper ?? 0, t['energy']?.goal ?? 0);
      return days.map(one).reduce((a, b) => a + b) / days.length * 100;
    }

    final legend = [
      (tr('Protein', 'Eiwit'), p.protein, avg((x) => x.$1), goalShare('protein')),
      (tr('Carbs', 'Koolhydr.'), p.carbs, avg((x) => x.$2), goalShare('carbs')),
      (tr('Fat', 'Vet'), p.fat, avg((x) => x.$3), goalShare('fat')),
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
          SplitBarsChart(splits: splits, target: (legend[0].$4 / 100, legend[1].$4 / 100)),
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
    // Teller over de volledig gelogde dagen, zoals de rest van het scherm
    final logged = keys.where(_full.contains).length;
    final candidates = [...stripKeys, 'fiber', 'epa_dha'];

    // Categorie per dag: 0 = < 50%, 1 = 50–99%, 2 = op doel, 3 = boven maximum, -1 = telt (nog) niet mee,
    // null = niet gelogd
    int? category(String day, String key) {
      if (daily[day] != null && !_full.contains(day)) return -1;
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
    // Niet alleen wat misloopt: bij veel rijen ook de drie die je het vaakst haalt (onderaan)
    final shown = _allHeat || rows.length <= 12 ? rows : [...rows.take(9), ...rows.sublist(rows.length - 3)];
    final rare = [
      for (final r in rows)
        if (logged >= 5 && r.$2.where((c) => c == 2).length <= logged * 0.25) r.$1,
    ];
    final weekday = weekdayShort;

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
      -1 => tr('not counted: too little logged, or today', 'telt niet mee: te weinig gelogd, of vandaag'),
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        weekday[parseDay(d).weekday - 1],
                        textAlign: TextAlign.center,
                        style: numStyle(
                          9.5,
                          weight: i == keys.length - 1 ? FontWeight.w600 : FontWeight.w400,
                          color: i == keys.length - 1 ? p.ink : p.ink3,
                        ),
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
                          // Alleen bij een bewuste tik of als de muis even blijft staan, niet als je eroverheen
                          // scrolt (N53)
                          Tooltip(
                            triggerMode: TooltipTriggerMode.tap,
                            waitDuration: const Duration(milliseconds: 700),
                            message: '${n.name}, ${DateFormat('EEE d MMM', appLocale).format(parseDay(keys[i]))}: ${cellText(c)}',
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: cellColor(c),
                                borderRadius: BorderRadius.circular(3),
                                border: c == 1
                                    ? Border.all(color: p.lowFill)
                                    : (c == null ? Border.all(color: p.line) : (c == -1 ? Border.all(color: p.lineStrong) : null)),
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
                child: Text(_allHeat ? tr('Show less', 'Minder tonen') : tr('Show all', 'Alles tonen')),
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

  /// Suiker per dag (P184): vrije suikers tegenover je maximum, met alle suikers en koolhydraten erbij, en de
  /// bloedsuikermetingen van die dag ernaast. Een tik opent het verloop van de vrije suikers.
  Widget _sugar(AppState s, Palette p, List<String> keys, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets) {
    final glucose = <String, List<double>>{};
    for (final b in s.user.biometricHistory('glucose', from: keys.first)) {
      if (b.day.compareTo(keys.last) <= 0) glucose.putIfAbsent(b.day, () => []).add(b.value);
    }
    // Met een eigen grens voor alle suikers (bv. bij diabetes) volgt de kaart die grens: één grens, op alle suikers.
    // Anders de WHO-grens op de vrije suikers.
    final own = targets[keys.last]?['sugars']?.upper != null;
    final measured = own ? 'sugars' : 'free_sugars';
    double? max(String d) => targets[d]?[measured]?.upper;
    double value(NutrientTotals t) => own ? math.max(t['sugars'], t['free_sugars']) : t['free_sugars'];
    // Dezelfde basis als de rest van het scherm: volledig gelogde dagen, vandaag niet
    final today = dayKey(logicalNow());
    final done = [
      for (final k in keys)
        if (_full.contains(k)) k,
    ];
    final avg = done.isEmpty ? null : done.map((k) => value(daily[k]!)).reduce((a, b) => a + b) / done.length;
    final over = done.where((k) => max(k) != null && value(daily[k]!) > max(k)!).length;
    final scaleMax = [
      for (final k in keys) ...[daily[k]?['sugars'] ?? 0, max(k) ?? 0],
    ].fold<double>(1, math.max);
    // Kop: één maximum, of het bereik als het doel in deze week veranderde ("38–50 g")
    final limits = [
      for (final k in keys)
        if (daily[k] != null || k == keys.last) ?max(k),
    ];
    final lo = limits.isEmpty ? null : limits.reduce(math.min), hi = limits.isEmpty ? null : limits.reduce(math.max);
    final maxText = lo == null ? '–' : (fmtInt(lo) == fmtInt(hi!) ? '${fmtInt(hi)} g' : '${fmtInt(lo)}–${fmtInt(hi)} g');
    void open() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutrientDetailScreen(nutrient: nutrientByKey[measured]!, from: widget.from, to: widget.to),
      ),
    );

    // Twee balken op één schaal: vrije suikers (dik) en alle suikers (dun eronder). De max-streep staat alleen op de
    // balk waar de grens over gaat, zodat alle suikers niet "over de grens" lijken te gaan als die alleen voor de
    // vrije suikers geldt.
    Widget bar(String d) {
      final t = daily[d];
      if (t == null) return Container(height: 10, decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(4)));
      final f = t['free_sugars'], all = math.max(t['sugars'], f), limit = max(d);
      final tooMuch = limit != null && value(t) > limit;
      Widget one(double amount, double height, Color color, bool withLimit) => LayoutBuilder(
        builder: (context, c) => SizedBox(
          height: height,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(3)),
              ),
              Container(
                width: c.maxWidth * amount / scaleMax,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              if (withLimit && limit != null)
                Positioned(
                  left: (c.maxWidth * limit / scaleMax - 1).clamp(0, c.maxWidth - 2),
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: p.ink),
                ),
            ],
          ),
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          one(f, 7, !own && tooMuch ? p.highFill : p.carbs, !own),
          const SizedBox(height: 2),
          one(all, 4, own && tooMuch ? p.highFill : p.carbs.withValues(alpha: 0.4), own),
        ],
      );
    }

    // Uitleg bij een gewone tik, in een onderblad met een vaste achtergrond (leesbaar in de donkere modus)
    void explain() => showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Sugar per day', 'Suiker per dag'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
              ),
              const SizedBox(height: 8),
              Text(nutrientNote('free_sugars')!, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
              const SizedBox(height: 8),
              Text(
                own
                    ? tr(
                        'Your own maximum applies to all sugars, so the line sits on the thin bar for all sugars.',
                        'Je eigen maximum geldt voor alle suikers, dus de streep staat op de dunne balk van alle suikers.',
                      )
                    : tr(
                        'The maximum applies to free sugars only, so the line sits on the thick bar. The thin bar shows all sugars, including fruit and milk.',
                        'Het maximum geldt alleen voor vrije suikers, dus de streep staat op de dikke balk. De dunne balk toont alle suikers, ook die uit fruit en melk.',
                      ),
                style: TextStyle(fontSize: 13, height: 1.45, color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );

    String extra(String d) => [
      if (daily[d] case final t?) tr('carbs ${fmtInt(t['carbs'])} g', 'koolhydr. ${fmtInt(t['carbs'])} g'),
      if (glucose[d] case final g?) tr('glucose ${g.map(fmtDec).join(' · ')} mmol/L', 'bloedsuiker ${g.map(fmtDec).join(' · ')} mmol/L'),
    ].join('  ·  ');

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Sugar per day', 'Suiker per dag'),
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('About sugar per day', 'Over suiker per dag'),
              icon: Icon(Icons.info_outline_rounded, size: 18, color: p.ink3),
              onPressed: explain,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  boxed: false,
                  label: own ? tr('Sugars, avg.', 'Suikers, gem.') : tr('Free sugars, avg.', 'Vrije suikers, gem.'),
                  value: avg == null ? '–' : '${fmtInt(avg)} g',
                ),
              ),
              Expanded(
                child: StatTile(boxed: false, label: own ? tr('Your maximum', 'Jouw maximum') : tr('Maximum', 'Maximum'), value: maxText),
              ),
              Expanded(
                child: StatTile(boxed: false, label: tr('Days over', 'Dagen erboven'), value: '$over / ${done.length}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 56),
              const Spacer(),
              Text(tr('free / all g', 'vrij / alle g'), style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3)),
            ],
          ),
          for (final d in keys)
            InkWell(
              key: ValueKey('sugar-$d'),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            DateFormat('EEE d', appLocale).format(parseDay(d)),
                            style: TextStyle(fontSize: 12, color: d == today ? p.ink : p.ink2, fontWeight: d == today ? FontWeight.w600 : null),
                          ),
                        ),
                        Expanded(child: bar(d)),
                        SizedBox(
                          width: 74,
                          child: Text(
                            daily[d] == null ? '–' : '${fmtInt(daily[d]!['free_sugars'])} / ${fmtInt(daily[d]!['sugars'])}',
                            textAlign: TextAlign.right,
                            style: numStyle(
                              12,
                              color: max(d) != null && daily[d] != null && value(daily[d]!) > max(d)! ? p.high : p.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (extra(d).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 56, top: 2),
                        child: Text(extra(d), style: numStyle(10.5, weight: FontWeight.w400, color: glucose[d] != null ? p.ink2 : p.ink3)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          ChartLegend(
            items: [
              (LegendItem.box(p.carbs, w: 10, h: 7, radius: 3), tr('free sugars', 'vrije suikers')),
              (
                LegendItem.box(p.carbs.withValues(alpha: 0.4), w: 10, h: 4, radius: 2),
                tr('all sugars, incl. fruit and milk', 'alle suikers, ook fruit en melk'),
              ),
              (
                LegendItem.box(p.ink, w: 2, h: 10),
                own ? tr('your max (all sugars)', 'jouw max (alle suikers)') : tr('max (free sugars)', 'max (vrije suikers)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _joinNames(List<String> names) =>
      names.length <= 1 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} ${tr('and', 'en')} ${inSentence(names.last)}';

  Widget _weight(AppState s, Palette p, List<String> keys, DateTime from, {required bool logged}) {
    final history = {for (final b in s.user.biometricHistory('weight', from: dayKey(from.plusDays(-30)))) b.day: b.value};
    final weights = [for (final k in keys) history[k]];
    // Trend vanaf een maand vóór de periode, zodat de lijn aan het begin al ingelopen is
    final warm = [for (var i = 30; i > 0; i--) dayKey(from.plusDays(-i))];
    final trendAll = weightTrend(history, [...warm, ...keys]);
    final trend = trendAll.sublist(warm.length);
    final known = trend.whereType<double>().toList();
    // De schatting gaat over de laatste 4 weken: alleen tonen bij een periode die daarin valt en waarin je iets
    // logde. Een lege of oude maand krijgt geen getal dat er niets mee te maken heeft.
    final now = logicalNow();
    final window = dayKey(DateTime(now.year, now.month, now.day - 28));
    final showEstimate = logged && keys.last.compareTo(window) >= 0;
    final est = showEstimate ? s.energyEstimate : null;

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
          if (showEstimate) ...[
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
                              : est.reliable
                              ? tr(
                                  'From your weight trend and what you logged, last 4 weeks (${est.loggedDays} days, ${est.weighIns} weigh-ins)',
                                  'Uit je gewichtstrend en wat je logde, laatste 4 weken (${est.loggedDays} dagen, ${est.weighIns} wegingen)',
                                )
                              : tr(
                                  'Rough estimate: only ${est.loggedDays} logged days and ${est.weighIns} weigh-ins in the last 4 weeks',
                                  'Ruwe schatting: maar ${est.loggedDays} gelogde dagen en ${est.weighIns} wegingen in de laatste 4 weken',
                                ),
                          style: TextStyle(fontSize: 11.5, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  if (est != null) Text('${est.reliable ? '' : '≈ '}${fmtInt((est.tdee / 10).round() * 10)} kcal', style: numStyle(17)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _minis(Palette p, List<String> keys, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets) {
    // Eén score voor de periode, met dezelfde regel als het weekrapport: het gemiddelde van de volledig gelogde dagen
    final today = dayKey(logicalNow());
    final scores = [
      for (final k in keys)
        _full.contains(k) ? dayScore(daily[k]!.values, targets[k]!, closed: k.compareTo(today) < 0).toDouble() : null,
    ];
    final known = scores.whereType<double>().toList();
    final avg = known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
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
                Text(tr('Nutrient score', 'Voedingsscore'), style: TextStyle(fontSize: 12, color: p.ink2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(avg == null ? '–' : fmtInt(avg), style: numStyle(22)),
                    const SizedBox(width: 6),
                    Text(
                      tr('average', 'gemiddeld'),
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
                Text(tr('Full days', 'Volledige dagen'), style: TextStyle(fontSize: 12, color: p.ink2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${_full.length}', style: numStyle(22)),
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
                        // Vol = volledige dag, licht = iets gelogd maar telt niet mee (te weinig, of vandaag), leeg = niets
                        for (final k in keys)
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _full.contains(k) ? p.brand : (daily.containsKey(k) ? p.brand.withValues(alpha: 0.3) : Colors.transparent),
                              border: daily.containsKey(k)
                                  ? (k == today ? Border.all(color: p.ink, width: 1.5) : null)
                                  : Border.all(color: p.lineStrong, width: 1.5),
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
  Widget _averages(AppState s, Palette p, Map<String, NutrientTotals> daily, Map<String, Map<String, Target>> targets, {int columns = 1}) {
    // Dezelfde basis als de rest: volledig gelogde dagen; zonder één volledige dag wat je wel logde
    final counted = _full.isEmpty ? daily : {for (final k in _full) k: daily[k]!};
    final logged = counted.length;
    final averages = <String, double>{};
    final incomplete = <String>{};
    for (final t in counted.values) {
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
          trailing: _full.isEmpty
              ? tr('over $logged ${logged == 1 ? 'day' : 'days'}', 'over $logged ${logged == 1 ? 'dag' : 'dagen'}')
              : tr('over $logged full ${logged == 1 ? 'day' : 'days'}', 'over $logged volledige ${logged == 1 ? 'dag' : 'dagen'}'),
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
          // Elke dag met het doel dat toen gold: het gemiddelde doel van de gelogde dagen
          targets: averageTargets([
            for (final k in counted.keys)
              if (targets[k] != null) targets[k]!,
          ]),
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
