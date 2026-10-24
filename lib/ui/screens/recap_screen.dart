import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/report.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/kit.dart';
import '../widgets/pro_widgets.dart';
import '../widgets/share_actions.dart';

/// Maand- of jaaroverzicht, in dezelfde rustige stijl als het weekrapport.
class RecapScreen extends StatelessWidget {
  const RecapScreen({super.key, required this.from, required this.year});
  final DateTime from;
  final bool year;

  DateTime get to => year ? DateTime(from.year, 12, 31) : DateTime(from.year, from.month + 1, 0);

  String get title => year
      ? tr('Your ${from.year}', 'Jouw ${from.year}')
      : tr('Your ${DateFormat('MMMM', appLocale).format(from)}', 'Jouw ${DateFormat('MMMM', appLocale).format(from)}');

  String shareText(Recap r) => [
    tr('$title on MacroMatrix', '$title op MacroMatrix'),
    tr('${r.daysLogged} days logged, ${r.distinctFoods} different foods', '${r.daysLogged} dagen gelogd, ${r.distinctFoods} verschillende producten'),
    tr('Average Nutrient score: ${r.avgScore}', 'Gemiddelde Voedingsscore: ${r.avgScore}'),
    tr('Longest streak: ${r.longestStreak} days · ${fmtInt(r.xp)} XP', 'Langste reeks: ${r.longestStreak} dagen · ${fmtInt(r.xp)} XP'),
    if (r.topFoods.isNotEmpty) tr('Most logged: ${r.topFoods.first.$1}', 'Meest gelogd: ${r.topFoods.first.$1}'),
    'app.divinenet.online',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final r = s.recap(from, to, year: year);
    // Uitgebreid jaaroverzicht alleen met Pro; zonder Pro blijft alles precies zoals het was
    final extras = year && r != null && (proOf(context)?.isPro ?? false) ? s.recapExtras(from.year) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(year ? tr('Year in review', 'Jaaroverzicht') : tr('Monthly recap', 'Maandoverzicht')),
        actions: [
          if (r != null)
            IconButton(
              tooltip: tr('Share', 'Delen'),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => shareRecap(context, r, copyText: shareText(r)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Narrow(
            child: r == null
                // Lege periode: dezelfde nette lege kaart als op het Dashboard, met uitleg
                ? Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_note_rounded, color: p.ink3),
                        const SizedBox(height: 10),
                        Text(
                          year ? tr('Nothing logged this year', 'Niets gelogd dit jaar') : tr('Nothing logged this month', 'Niets gelogd deze maand'),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            'Your recap fills itself once you log a few days: your calendar, energy, most eaten foods and highlights.',
                            'Je overzicht vult zich zodra je een paar dagen logt: je kalender, energie, wat je het vaakst at en je hoogtepunten.',
                          ),
                          style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Hero(
                        r: r,
                        avatar: LevelAvatar(avatar: s.avatar, level: s.level.level, size: 44, frame: myFrameOf(context)),
                      ),
                      const SizedBox(height: 12),
                      if (!year) _Calendar(r: r) else _MonthBars(r: r),
                      const SizedBox(height: 12),
                      _Energy(r: r),
                      if (r.split != null) ...[const SizedBox(height: 12), _Macros(r: r)],
                      if (r.topFoods.isNotEmpty) ...[const SizedBox(height: 12), _TopFoods(r: r, foods: extras?.topFoods)],
                      const SizedBox(height: 12),
                      _Highlights(r: r),
                      if (extras != null) ...[
                        const SizedBox(height: 12),
                        _NutrientHeatmap(x: extras),
                        if (extras.records.isNotEmpty) ...[const SizedBox(height: 12), _Records(x: extras)],
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.tonalIcon(
                          key: const Key('recap-share'),
                          onPressed: () => shareRecap(context, r, copyText: shareText(r)),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(tr('Share as image', 'Delen als afbeelding')),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// ▲ 3 / ▼ 2 tegenover de vorige periode, of niets als die er niet is.
String? _delta(num now, num? before, {String unit = ''}) {
  if (before == null) return null;
  final d = (now - before).round();
  if (d == 0) return '=';
  return '${d > 0 ? '▲' : '▼'} ${fmtInt(d.abs())}$unit';
}

/// Opening: de maand groot in de merkkleur, de scorering en je kerncijfers tegenover vorige maand.
class _Hero extends StatelessWidget {
  const _Hero({required this.r, required this.avatar});
  final Recap r;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = p.onBrand;
    final prev = r.previous;
    final name = r.year ? '${r.from.year}' : DateFormat('MMMM', appLocale).format(r.from);
    Widget stat(String label, String value, String? delta) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5, color: on.withValues(alpha: 0.8))),
          ),
          Text(value, style: numStyle(17, color: on)),
          if (delta != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 52,
              child: Text(delta, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontSize: 11, color: on.withValues(alpha: 0.75))),
            ),
          ],
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(r.year ? tr('Your year', 'Jouw jaar') : '${tr('Your month', 'Jouw maand')} · ${r.from.year}', color: on.withValues(alpha: 0.8)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name[0].toUpperCase() + name.substring(1),
                        style: TextStyle(fontSize: 44, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: on),
                      ),
                    ),
                    Text(
                      r.daysInPeriod <= 31
                          ? tr('${r.daysLogged} of ${r.daysInPeriod} days logged', '${r.daysLogged} van ${r.daysInPeriod} dagen gelogd')
                          : tr('${r.daysLogged} ${r.daysLogged == 1 ? 'day' : 'days'} logged', '${r.daysLogged} ${r.daysLogged == 1 ? 'dag' : 'dagen'} gelogd'),
                      style: TextStyle(fontSize: 13.5, color: on.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              avatar,
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 104,
                height: 104,
                child: CustomPaint(
                  painter: _Ring(r.avgScore / 100, track: on.withValues(alpha: 0.22), fill: on),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${r.avgScore}', style: numStyle(32, color: on, height: 1)),
                        Text(
                          _delta(r.avgScore, prev?.avgScore) ?? tr('score', 'score'),
                          style: TextStyle(fontSize: 11, color: on.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    stat(tr('Items logged', 'Regels gelogd'), fmtInt(r.entries), _delta(r.entries, prev?.entries)),
                    stat(tr('Different foods', 'Verschillende producten'), '${r.distinctFoods}', _delta(r.distinctFoods, prev?.distinctFoods)),
                    stat(tr('Best streak', 'Beste reeks'), '${r.longestStreak}', null),
                    stat(tr('XP earned', 'XP verdiend'), fmtInt(r.xp), _delta(r.xp, prev?.xp)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.fraction, {required this.track, required this.fill});
  final double fraction;
  final Color track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.283, false, paint..color = track);
    if (fraction > 0) canvas.drawArc(rect, -1.5708, 6.283 * fraction.clamp(0.0, 1.0), false, paint..color = fill);
  }

  @override
  bool shouldRepaint(_Ring old) => old.fraction != fraction || old.fill != fill || old.track != track;
}

/// Kleur voor een score: één tint, van licht (laag) naar de volle merkkleur (hoog).
Color _scoreColor(Palette p, int score) => Color.lerp(p.brandSoft, p.brand, (score / 100).clamp(0.08, 1.0))!;

/// De maand dag per dag: een vakje per dag, hoe donkerder hoe hoger je Voedingsscore.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final first = DateTime(r.from.year, r.from.month);
    final days = DateTime(r.from.year, r.from.month + 1, 0).day;
    final lead = first.weekday - 1; // maandag eerst
    final weeks = ((lead + days) / 7).ceil();
    final best = r.bestDay?.$1;
    final weekdays = weekdayShort;

    Widget cell(int day) {
      final d = DateTime(r.from.year, r.from.month, day);
      final key = dayKey(d);
      final score = r.dayScores[key];
      final future = d.isAfter(r.to);
      final isBest = best != null && dayKey(best) == key;
      final color = score == null ? (future ? Colors.transparent : p.track) : _scoreColor(p, score);
      final dark = score != null && score >= 45;
      final box = Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: isBest ? Border.all(color: p.ink, width: 1.6) : (future ? Border.all(color: p.line) : null),
        ),
        alignment: Alignment.center,
        child: Text('$day', style: numStyle(11, color: dark ? p.onBrand : (future ? p.ink3 : p.ink2))),
      );
      return AspectRatio(
        aspectRatio: 1,
        child: score == null
            ? box
            : Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: tr(
                  '${DateFormat('EEE d MMM', appLocale).format(d)} · score $score · ${fmtInt(r.dayKcal[key] ?? 0)} kcal',
                  '${DateFormat('EEE d MMM', appLocale).format(d)} · score $score · ${fmtInt(r.dayKcal[key] ?? 0)} kcal',
                ),
                child: box,
              ),
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Day by day', 'Dag per dag'),
            subtitle: tr('Darker means a higher Nutrient score · tap a day', 'Hoe donkerder, hoe hoger je Voedingsscore · tik op een dag'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Center(child: Text(w, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink3))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: switch (w * 7 + i - lead + 1) {
                      final day when day >= 1 && day <= days => cell(day),
                      _ => const AspectRatio(aspectRatio: 1, child: SizedBox()),
                    },
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(tr('Low', 'Laag'), style: TextStyle(fontSize: 11, color: p.ink3)),
              const SizedBox(width: 6),
              for (final v in [10, 30, 50, 70, 90])
                Container(
                  width: 18,
                  height: 10,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(color: _scoreColor(p, v), borderRadius: BorderRadius.circular(3)),
                ),
              const SizedBox(width: 4),
              Text(tr('High', 'Hoog'), style: TextStyle(fontSize: 11, color: p.ink3)),
              const Spacer(),
              if (best != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(border: Border.all(color: p.ink, width: 1.6), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 5),
                Text(tr('Best day', 'Beste dag'), style: TextStyle(fontSize: 11, color: p.ink3)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Jaar: de gemiddelde score per maand als staafjes.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final byMonth = <int, List<int>>{};
    for (final e in r.dayScores.entries) {
      byMonth.putIfAbsent(DateTime.parse(e.key).month, () => []).add(e.value);
    }
    int? avg(int m) => byMonth[m] == null ? null : (byMonth[m]!.reduce((a, b) => a + b) / byMonth[m]!.length).round();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Month by month', 'Maand per maand'), subtitle: tr('Average Nutrient score', 'Gemiddelde Voedingsscore')),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var m = 1; m <= 12; m++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (avg(m) != null) Text('${avg(m)}', style: numStyle(10, color: p.ink2)),
                          const SizedBox(height: 3),
                          Container(
                            height: avg(m) == null ? 3 : 4 + 76 * avg(m)! / 100,
                            decoration: BoxDecoration(
                              color: avg(m) == null ? p.track : _scoreColor(p, avg(m)!),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(DateFormat('MMMMM', appLocale).format(DateTime(2024, m)), style: TextStyle(fontSize: 10.5, color: p.ink3)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Energie: het gemiddelde groot, met per dag een staafje en je doel als lijn.
class _Energy extends StatelessWidget {
  const _Energy({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final days = [
      for (var d = r.from; !d.isAfter(r.to); d = DateTime(d.year, d.month, d.day + 1)) r.dayKcal[dayKey(d)],
    ];
    final delta = _delta(r.avgKcal, r.previous?.avgKcal, unit: ' kcal');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Energy', 'Energie')),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtInt(r.avgKcal), style: numStyle(36, color: p.ink)),
              const SizedBox(width: 6),
              Flexible(child: Text(tr('kcal per logged day', 'kcal per gelogde dag'), style: TextStyle(fontSize: 13, color: p.ink2))),
            ],
          ),
          Text(
            [
              if (r.kcalGoal > 0) tr('goal ${fmtInt(r.kcalGoal)}', 'doel ${fmtInt(r.kcalGoal)}'),
              ?delta == null ? null : '$delta ${tr('vs last ${r.year ? 'year' : 'month'}', 't.o.v. vorige ${r.year ? 'jaar' : 'maand'}')}',
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: p.ink3),
          ),
          if (!r.year && days.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: CustomPaint(painter: _KcalBars(days, r.kcalGoal.toDouble(), bar: p.brand, over: p.highFill, line: p.ink3, empty: p.track)),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(DateFormat('d MMM', appLocale).format(r.from), style: TextStyle(fontSize: 11, color: p.ink3)),
                const Spacer(),
                Text(tr('- - - goal', '- - - doel'), style: TextStyle(fontSize: 11, color: p.ink3)),
                const Spacer(),
                Text(DateFormat('d MMM', appLocale).format(r.to), style: TextStyle(fontSize: 11, color: p.ink3)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KcalBars extends CustomPainter {
  _KcalBars(this.values, this.goal, {required this.bar, required this.over, required this.line, required this.empty});
  final List<double?> values;
  final double goal;
  final Color bar, over, line, empty;

  @override
  void paint(Canvas canvas, Size size) {
    final known = values.whereType<double>();
    final top = [goal, if (known.isNotEmpty) known.reduce((a, b) => a > b ? a : b)].reduce((a, b) => a > b ? a : b) * 1.1;
    if (top <= 0) return;
    final step = size.width / values.length;
    final w = (step - 2).clamp(1.5, 14.0);
    for (final (i, v) in values.indexed) {
      final x = i * step + (step - w) / 2;
      if (v == null || v <= 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - 3, w, 3), const Radius.circular(1.5)), Paint()..color = empty);
        continue;
      }
      final h = (v / top * size.height).clamp(3.0, size.height);
      final r = Radius.circular((w / 2).clamp(0, 4));
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: r, topRight: r),
        Paint()..color = goal > 0 && v > goal * 1.1 ? over : bar,
      );
    }
    if (goal > 0) {
      final y = size.height - goal / top * size.height;
      final paint = Paint()
        ..color = line
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_KcalBars old) => old.values != values || old.goal != goal || old.bar != bar;
}

/// Macroverdeling van de maand als één gestapelde balk, met een legende.
class _Macros extends StatelessWidget {
  const _Macros({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Afgerond tot samen precies 100%
    final pr = (r.split!.$1 * 100).round() / 100, cb = (r.split!.$2 * 100).round() / 100, ft = 1 - pr - cb;
    final parts = [
      (tr('Protein', 'Eiwit'), pr, p.protein, tr('${r.avgProtein} g a day', '${r.avgProtein} g per dag')),
      (tr('Carbs', 'Koolhydraten'), cb, p.carbs, null),
      (tr('Fat', 'Vet'), ft, p.fat, null),
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Where your energy came from', 'Waar je energie vandaan kwam')),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, (_, f, c, _)) in parts.indexed)
                    if (f > 0)
                      Expanded(
                        flex: (f * 1000).round().clamp(1, 1000),
                        child: Container(color: c, margin: EdgeInsets.only(left: i == 0 ? 0 : 2)),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, f, c, extra) in parts)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.ink2))),
                        ],
                      ),
                      Text(fmtPct(f), style: numStyle(20, color: p.ink)),
                      if (extra != null) Text(extra, style: TextStyle(fontSize: 11.5, color: p.ink3)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wat je het meest at, met een balkje naar verhouding.
class _TopFoods extends StatelessWidget {
  const _TopFoods({required this.r, this.foods});
  final Recap r;

  /// Met Pro de top 10 van het jaar in plaats van de top 5.
  final List<(String, int)>? foods;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final list = foods != null && foods!.isNotEmpty ? foods! : r.topFoods;
    final most = list.first.$2;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            list.length > 5 ? tr('Your top ${list.length}', 'Jouw top ${list.length}') : tr('Your top 5', 'Jouw top 5'),
            trailing: list.length > 5 ? const ProTag() : null,
            subtitle: tr(
              '${fmtInt(r.distinctFoods)} different foods in ${fmtInt(r.entries)} entries',
              '${fmtInt(r.distinctFoods)} verschillende producten in ${fmtInt(r.entries)} regels',
            ),
          ),
          const SizedBox(height: 8),
          for (final (i, (name, n)) in list.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('${i + 1}', style: numStyle(16, color: i == 0 ? p.brand : p.ink3)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.ink)),
                        const SizedBox(height: 4),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (n / most).clamp(0.04, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(color: i == 0 ? p.brand : p.brand.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$n×', style: numStyle(13, color: p.ink2)),
                ],
              ),
            ),
          if (r.favouriteBreakfast != null) ...[
            const SizedBox(height: 8),
            Divider(color: p.line, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, size: 18, color: p.ink3),
                const SizedBox(width: 8),
                Text(tr('Favourite breakfast: ', 'Favoriet ontbijt: '), style: TextStyle(fontSize: 13, color: p.ink3)),
                Expanded(
                  child: Text(r.favouriteBreakfast!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Pro: per voedingsstof en per maand hoe dicht je bij je doel zat, als een raster van vakjes.
class _NutrientHeatmap extends StatelessWidget {
  const _NutrientHeatmap({required this.x});
  final RecapExtras x;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final months = [for (var m = 1; m <= 12; m++) DateFormat('MMMMM', appLocale).format(DateTime(2026, m))];
    Color cell(double? f) => f == null ? p.track : Color.lerp(p.brandSoft, p.brand, f.clamp(0.08, 1.0))!;
    return Panel(
      key: const ValueKey('recap-heatmap'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Nutrients month by month', 'Voedingsstoffen per maand'),
            subtitle: tr('Darker means closer to your goal · tap a square', 'Hoe donkerder, hoe dichter bij je doel · tik op een vakje'),
            trailing: const ProTag(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 92),
              for (final m in months)
                Expanded(
                  child: Center(
                    child: Text(
                      m,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final e in x.monthNutrients.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      nutrientByKey[e.key]?.name ?? e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.ink2),
                    ),
                  ),
                  for (final (m, f) in e.value.indexed)
                    Expanded(
                      child: Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        message: f == null
                            ? tr('${months[m]}: nothing logged', '${months[m]}: niets gelogd')
                            : '${DateFormat('MMMM', appLocale).format(DateTime(2026, m + 1))} · ${nutrientByKey[e.key]?.name ?? e.key} · '
                                  '${f >= 1.5 ? '150%+' : fmtPct(f)}',
                        child: Container(
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(color: cell(f), borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pro: je records van het jaar.
class _Records extends StatelessWidget {
  const _Records({required this.x});
  final RecapExtras x;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    String day(DateTime d) => DateFormat('d MMMM', appLocale).format(d);
    (IconData, String, String, String) info(RecapRecord r) => switch (r.kind) {
      RecapRecordKind.bestScore => (
        Icons.emoji_events_outlined,
        tr('Best day', 'Beste dag'),
        tr('score ${fmtInt(r.value)}', 'score ${fmtInt(r.value)}'),
        day(r.day),
      ),
      RecapRecordKind.mostProtein => (Icons.fitness_center_rounded, tr('Most protein', 'Meeste eiwit'), '${fmtInt(r.value)} g', day(r.day)),
      RecapRecordKind.mostFiber => (Icons.grass_rounded, tr('Most fibre', 'Meeste vezels'), '${fmtInt(r.value)} g', day(r.day)),
      RecapRecordKind.mostFoods => (
        Icons.restaurant_rounded,
        tr('Most variety in a day', 'Meest gevarieerde dag'),
        tr('${fmtInt(r.value)} different foods', '${fmtInt(r.value)} verschillende producten'),
        day(r.day),
      ),
      RecapRecordKind.busiestMonth => (
        Icons.calendar_month_outlined,
        tr('Most days logged', 'Meeste dagen gelogd'),
        tr('${fmtInt(r.value)} days', '${fmtInt(r.value)} dagen'),
        DateFormat('MMMM', appLocale).format(r.day),
      ),
    };
    return Panel(
      key: const ValueKey('recap-records'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Your records', 'Jouw records'), trailing: const ProTag()),
          const SizedBox(height: 6),
          for (final r in x.records)
            Builder(
              builder: (context) {
                final (icon, label, value, date) = info(r);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: p.brand),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                            ),
                            Text(date, style: TextStyle(fontSize: 12, color: p.ink3)),
                          ],
                        ),
                      ),
                      Text(value, style: numStyle(14, color: p.ink)),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Je sterkste stof en iets om aan te werken, naast elkaar.
class _Highlights extends StatelessWidget {
  const _Highlights({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tile(IconData icon, Color color, Color soft, String label, String name, double frac) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(child: Eyebrow(label, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 2),
            Text(
              tr('${frac >= 1.5 ? '150%+' : fmtPct(frac)} of your goal', '${frac >= 1.5 ? '150%+' : fmtPct(frac)} van je doel'),
              style: TextStyle(fontSize: 12, color: p.ink2),
            ),
          ],
        ),
      ),
    );
    final strong = r.topNutrient != null && r.topNutrient!.$2 >= 0.75 ? r.topNutrient : null;
    final weak = r.weakNutrient != null && r.weakNutrient!.$2 < 0.75 ? r.weakNutrient : null;
    if (strong == null && weak == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (strong != null) tile(Icons.check_circle_rounded, p.ok, p.okSoft, tr('Strongest', 'Sterkste'), strong.$1.name, strong.$2),
        if (strong != null && weak != null) const SizedBox(width: 10),
        if (weak != null) tile(Icons.trending_up_rounded, p.low, p.lowSoft, tr('To work on', 'Om aan te werken'), weak.$1.name, weak.$2),
      ],
    );
  }
}

/// Kaart op Vandaag tijdens de eerste dagen van een maand (en in januari ook voor het jaar).
class RecapCard extends StatelessWidget {
  const RecapCard({super.key});

  /// (begin, jaar?) van het overzicht dat nu klaarstaat, of null.
  static (DateTime, bool)? due(AppState s) {
    final now = DateTime.now();
    if (now.day > 5 && !(now.month == 1 && now.day <= 10)) return null;
    final candidates = [if (now.month == 1) (DateTime(now.year - 1), true), (DateTime(now.year, now.month - 1), false)];
    for (final (from, year) in candidates) {
      final key = '${year ? 'y' : 'm'}${dayKey(from)}';
      if (s.user.setting('_recap_seen')?['key'] == key) continue;
      final to = year ? DateTime(from.year, 12, 31) : DateTime(from.year, from.month + 1, 0);
      final a = dayKey(from), b = dayKey(to);
      if (s.user.loggedDays().any((d) => d.compareTo(a) >= 0 && d.compareTo(b) <= 0)) return (from, year);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final d = due(s);
    if (d == null) return const SizedBox.shrink();
    final (from, year) = d;
    final key = '${year ? 'y' : 'm'}${dayKey(from)}';
    final name = year ? '${from.year}' : DateFormat('MMMM', appLocale).format(from);
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      color: p.brandSoft,
      borderColor: p.brandSoft,
      onTap: () {
        s.markRecapSeen(key);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecapScreen(from: from, year: year),
          ),
        );
      },
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Your $name in review is ready', 'Jouw $name in een notendop staat klaar'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: tr('Dismiss', 'Verbergen'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => s.markRecapSeen(key),
          ),
        ],
      ),
    );
  }
}
