/// Grafieken per dag in de stijl van het ontwerp: rustig, zonder rasters, met de doelen als lijn of band.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../day_clock.dart';
import '../theme.dart';
import 'kit.dart';
import '../../i18n.dart';

/// Datums onder een grafiek: begin, midden en "vandaag" (of de laatste dag).
class DayAxis extends StatelessWidget {
  const DayAxis({super.key, required this.from, required this.days});
  final DateTime from;
  final int days;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = DateFormat('d MMM', appLocale);
    final last = from.add(Duration(days: days - 1));
    final mid = from.add(Duration(days: (days - 1) ~/ 2));
    final now = logicalNow();
    final lastIsToday = last.year == now.year && last.month == now.month && last.day == now.day;
    final style = numStyle(10.5, weight: FontWeight.w400, color: p.ink3);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(f.format(from), style: style),
          Text(f.format(mid), style: style),
          Text(lastIsToday ? tr('today', 'vandaag') : f.format(last), style: style),
        ],
      ),
    );
  }
}

/// Breedte van een staaf per dag: breed bij een week, smal bij een maand. Dezelfde maat in elke grafiek,
/// zodat de staven van energie en macro's onder elkaar staan.
double dayBarWidth(double step, int days) => days <= 10 ? math.min(44.0, step * 0.56) : math.max(2.0, math.min(12.0, step * 0.62));

/// Onder een grafiek: bij een week elke weekdag (vandaag vet), bij een langere periode begin, midden en einde.
class DayLabels extends StatelessWidget {
  const DayLabels({super.key, required this.days});
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    if (days.length > 10) return DayAxis(from: days.first, days: days.length);
    final p = context.pal;
    final now = logicalNow();
    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    final style = numStyle(10.5, weight: FontWeight.w400, color: p.ink3);
    final wd = DateFormat('E', appLocale);
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                isToday(d) ? tr('today', 'vandaag') : wd.format(d),
                textAlign: TextAlign.center,
                style: isToday(d) ? style.copyWith(color: p.ink, fontWeight: FontWeight.w600) : style,
              ),
            ),
          ),
      ],
    );
  }
}

/// Een dag zonder gegevens: een stipje op de basislijn, zodat een lege plek bewust oogt.
void _emptyDot(Canvas canvas, double cx, double base, Palette p) => canvas.drawCircle(Offset(cx, base - 3), 1.8, Paint()..color = p.lineStrong);

/// Voortschrijdend gemiddelde over [window] dagen (alleen dagen met een waarde; minstens 3 nodig).
List<double?> movingAverage(List<double?> values, {int window = 7}) => [
  for (var i = 0; i < values.length; i++)
    () {
      final w = values.sublist(math.max(0, i - window + 1), i + 1).whereType<double>().toList();
      return i < window - 1 || w.length < 3 ? null : w.reduce((a, b) => a + b) / w.length;
    }(),
];

/// Staaf per dag met een gestippelde doellijn, optioneel een doelband en een lijn voor het 7-daags gemiddelde.
/// De laatste dag (vandaag, nog bezig) is inkt.
class DayBarsChart extends StatelessWidget {
  const DayBarsChart({
    super.key,
    required this.values,
    required this.colorOf,
    this.goal,
    this.band,
    this.average = true,
    this.averageColor,
    this.height = 120,
    this.highlightLast = true,
  });

  final List<double?> values;
  final Color Function(double value, int index) colorOf;
  final double? goal;

  /// Doelband (van, tot), bv. doel ±10%.
  final (double, double)? band;
  final bool average;
  final Color? averageColor;
  final double height;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarsPainter(
          values: values,
          colorOf: colorOf,
          goal: goal,
          band: band,
          avg: average ? movingAverage(values) : null,
          avgColor: averageColor ?? p.brand,
          p: p,
          highlightLast: highlightLast,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.colorOf,
    required this.goal,
    required this.band,
    required this.avg,
    required this.avgColor,
    required this.p,
    required this.highlightLast,
  });
  final List<double?> values;
  final Color Function(double, int) colorOf;
  final double? goal;
  final (double, double)? band;
  final List<double?>? avg;
  final Color avgColor;
  final Palette p;
  final bool highlightLast;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final known = values.whereType<double>();
    final maxV = math.max(known.isEmpty ? 1.0 : known.reduce(math.max), math.max(goal ?? 0, band?.$2 ?? 0)) * 1.12;
    final base = size.height - 1;
    double y(double v) => base - v / maxV * (base - 2);
    final step = size.width / n;
    final bw = math.min(10.0, math.max(2.0, step * 0.62));

    if (band != null) {
      canvas.drawRect(Rect.fromLTRB(0, y(band!.$2), size.width, y(band!.$1)), Paint()..color = p.okSoft);
    }
    for (final (i, v) in values.indexed) {
      if (v == null || v <= 0) continue;
      final x = i * step + (step - bw) / 2;
      final last = highlightLast && i == n - 1;
      final c = last ? p.ink : colorOf(v, i);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x, y(v), x + bw, base), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        Paint()..color = c,
      );
    }
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = p.lineStrong);
    if (goal != null) {
      final gy = y(goal!);
      final dash = Paint()
        ..color = band != null ? p.okFill : p.ink
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, gy), Offset(math.min(x + 3, size.width), gy), dash);
      }
    }
    if (avg != null) {
      final path = Path();
      var started = false;
      for (final (i, v) in avg!.indexed) {
        if (v == null) continue;
        final o = Offset(i * step + step / 2, y(v));
        started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = avgColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

/// Macroverdeling per dag als 100%-gestapelde staven (eiwit onder, dan koolhydraten, vet boven),
/// met witte stippellijnen op de doelverdeling.
class SplitBarsChart extends StatelessWidget {
  const SplitBarsChart({super.key, required this.splits, this.target, this.height = 108});
  final List<(double, double, double)?> splits;

  /// Doelverdeling eiwit en koolhydraten (in delen van 1).
  final (double, double)? target;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SplitPainter(splits, target, context.pal)),
  );
}

class _SplitPainter extends CustomPainter {
  _SplitPainter(this.splits, this.target, this.p);
  final List<(double, double, double)?> splits;
  final (double, double)? target;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final n = splits.length;
    if (n == 0) return;
    final step = size.width / n;
    final bw = dayBarWidth(step, n);
    final h = size.height;
    final r = Radius.circular(math.min(6, bw / 2));
    // Een smalle naad tussen de lagen, in de kleur van de kaart
    final gap = n <= 10 ? 2.0 : 1.0;
    for (final (i, s) in splits.indexed) {
      final x = i * step + (step - bw) / 2;
      if (s == null) {
        _emptyDot(canvas, x + bw / 2, h, p);
        continue;
      }
      final bar = RRect.fromRectAndCorners(Rect.fromLTWH(x, 0, bw, h), topLeft: r, topRight: r);
      canvas.save();
      canvas.clipRRect(bar);
      final yp = h - s.$1 * h, yc = yp - s.$2 * h;
      canvas.drawRect(Rect.fromLTRB(x, yp, x + bw, h), Paint()..color = p.protein);
      canvas.drawRect(Rect.fromLTRB(x, yc, x + bw, yp - gap), Paint()..color = p.carbs);
      canvas.drawRect(Rect.fromLTRB(x, 0, x + bw, yc - gap), Paint()..color = p.fat);
      canvas.restore();
    }
    if (target != null) {
      // Doelverdeling als korte streepjes over elke staaf
      final dash = Paint()
        ..color = p.surface
        ..strokeWidth = 1.5;
      for (final f in [target!.$1, target!.$1 + target!.$2]) {
        final ty = h - f * h;
        for (final (i, s) in splits.indexed) {
          if (s == null) continue;
          final x = i * step + (step - bw) / 2;
          for (var dx = x; dx < x + bw; dx += 6) {
            canvas.drawLine(Offset(dx, ty), Offset(math.min(dx + 3, x + bw), ty), dash);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SplitPainter old) => true;
}

/// Wegingen als stippen, trendgewicht als lijn, met hulplijnen op hele kilo's.
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.weights, required this.trend, this.height = 104});
  final List<double?> weights;
  final List<double?> trend;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _WeightPainter(weights, trend, context.pal)),
  );
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(this.weights, this.trend, this.p);
  final List<double?> weights;
  final List<double?> trend;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...weights.whereType<double>(), ...trend.whereType<double>()];
    if (all.isEmpty) return;
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    final pad = math.max(0.4, (hi - lo) * 0.15);
    lo -= pad;
    hi += pad;
    double y(double w) => 4 + (hi - w) / (hi - lo) * (size.height - 8);
    final step = size.width / weights.length;

    // Hulplijnen op hele kilo's (hooguit vier), met het getal rechts
    final kgStep = math.max(1, ((hi - lo) / 4).ceil());
    for (var k = (lo / kgStep).ceil() * kgStep; k <= hi; k += kgStep) {
      final ky = y(k.toDouble());
      canvas.drawLine(Offset(0, ky), Offset(size.width - 22, ky), Paint()..color = p.line);
      final tp = TextPainter(
        text: TextSpan(
          text: '$k',
          style: numStyle(9.5, weight: FontWeight.w400, color: p.ink3),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width, ky - tp.height / 2));
    }
    final dot = Paint()..color = p.ink3.withValues(alpha: 0.55);
    for (final (i, w) in weights.indexed) {
      if (w != null) canvas.drawCircle(Offset(i * step + step / 2, y(w)), 2.5, dot);
    }
    final path = Path();
    var started = false;
    for (final (i, w) in trend.indexed) {
      if (w == null) continue;
      final o = Offset(i * step + step / 2, y(w));
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = p.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WeightPainter old) => true;
}

/// Kleine lijn zonder assen (bv. volledigheidsscore per dag), met een stip op de laatste waarde.
class MiniLine extends StatelessWidget {
  const MiniLine({super.key, required this.values, required this.color, this.height = 32});
  final List<double?> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _MiniPainter(values, color)),
  );
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.values, this.color);
  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final known = values.whereType<double>();
    if (known.isEmpty) return;
    final lo = known.reduce(math.min), hi = known.reduce(math.max);
    double y(double v) => hi == lo ? size.height / 2 : size.height - 2 - (v - lo) / (hi - lo) * (size.height - 4);
    final step = values.length <= 1 ? 0.0 : (size.width - 4) / (values.length - 1);
    final path = Path();
    var started = false;
    Offset? last;
    for (final (i, v) in values.indexed) {
      if (v == null) continue;
      final o = Offset(2 + i * step, y(v));
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
      last = o;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeJoin = StrokeJoin.round,
    );
    if (last != null) canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MiniPainter old) => true;
}

/// Gestapelde balk met de grootste bijdragers aan een voedingsstof (merkkleur, telkens lichter), rest grijs.
class ContributorBar extends StatelessWidget {
  const ContributorBar({super.key, required this.shares, this.height = 12});

  /// Delen in volgorde; de laatste is "overige" als [restIsOther].
  final List<double> shares;
  final double height;

  static const opacities = [1.0, 0.78, 0.6, 0.45, 0.32];

  static Color colorAt(Palette p, int i) => i < opacities.length ? p.brand.withValues(alpha: opacities[i]) : p.lineStrong;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final (i, s) in shares.indexed)
              if (s > 0)
                Expanded(
                  flex: math.max(1, (s * 1000).round()),
                  child: Container(color: colorAt(p, i), margin: const EdgeInsets.only(right: 2)),
                ),
          ],
        ),
      ),
    );
  }
}

/// Legenda met kleine stalen, zoals onder de grafieken in het ontwerp.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});
  final List<(Widget, String)> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [for (final (sw, label) in items) LegendItem(swatch: sw, label: label)],
    ),
  );
}

/// Energie per dag als balken tegenover je doel. Kleur: groen binnen ±10%, rood erboven, zand eronder; vandaag (nog
/// bezig) iets lichter. Achter elke balk staat een lichte kolom tot het doel van die dag, met beweging erbij.
/// Bij een week ([days] ≤ 10) staan de kcal boven elke balk en de weekdag eronder.
class EnergyBars extends StatelessWidget {
  const EnergyBars({super.key, required this.days, required this.values, required this.goal, this.goals, this.height = 150});

  final List<DateTime> days;
  final List<double?> values;
  final double goal;

  /// Doel per dag, met de beweging van die dag erbij. Een dag met een hoger doel wordt daartegen beoordeeld.
  final List<double>? goals;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final anyExtra = goals != null && goals!.any((g) => g > goal + 1);
    final now = logicalNow();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _EnergyPainter(
              values: values,
              goals: [for (var i = 0; i < values.length; i++) goals?[i] ?? goal],
              today: [for (final d in days) d.year == now.year && d.month == now.month && d.day == now.day],
              labels: days.length <= 10,
              // Een painter erft het lettertype van de app niet vanzelf
              font: DefaultTextStyle.of(context).style,
              p: p,
            ),
          ),
        ),
        DayLabels(days: days),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            LegendItem(swatch: LegendItem.box(p.okFill, w: 10, h: 10, radius: 3), label: tr('within ±10%', 'binnen ±10%')),
            LegendItem(swatch: LegendItem.box(p.highFill, w: 10, h: 10, radius: 3), label: tr('above goal', 'boven doel')),
            LegendItem(swatch: LegendItem.box(_below(p), w: 10, h: 10, radius: 3), label: tr('below goal', 'onder doel')),
            LegendItem(
              swatch: LegendItem.box(p.track, w: 10, h: 10, radius: 3),
              label: anyExtra ? tr('goal that day (incl. exercise)', 'doel van die dag (incl. beweging)') : tr('goal', 'doel'),
            ),
          ],
        ),
      ],
    );
  }
}

Color _below(Palette p) => p.lowFill.withValues(alpha: 0.55);

/// Kleur van een dag tegenover zijn doel: groen binnen ±10%, rood erboven, zand eronder.
Color energyColor(Palette p, double kcal, double goal) => (kcal - goal).abs() <= goal * 0.1 ? p.okFill : (kcal > goal ? p.highFill : _below(p));

class _EnergyPainter extends CustomPainter {
  _EnergyPainter({required this.values, required this.goals, required this.today, required this.labels, required this.font, required this.p});
  final TextStyle font;
  final List<double?> values;
  final List<double> goals;
  final List<bool> today;
  final bool labels;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final known = values.whereType<double>();
    final top = math.max(known.isEmpty ? 0.0 : known.reduce(math.max), goals.reduce(math.max)) * 1.08;
    final head = labels ? 18.0 : 4.0;
    final base = size.height - 1;
    double y(double v) => base - v / top * (base - head);
    final step = size.width / n;
    final bw = dayBarWidth(step, n);
    final r = Radius.circular(math.min(6, bw / 2));

    for (final (i, v) in values.indexed) {
      final x = i * step + (step - bw) / 2;
      if (v == null || v <= 0) {
        _emptyDot(canvas, x + bw / 2, base, p);
        continue;
      }
      final g = goals[i];
      // Achter elke balk een lichte kolom tot het doel van die dag (met beweging erbij is die hoger)
      canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTRB(x, y(g), x + bw, base), topLeft: r, topRight: r), Paint()..color = p.track);
      final c = energyColor(p, v, g);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x, math.min(y(v), base - 2), x + bw, base), topLeft: r, topRight: r),
        Paint()..color = today[i] ? c.withValues(alpha: c.a * 0.55) : c,
      );
      if (labels) {
        final t = TextPainter(
          text: TextSpan(
            text: fmtInt(v),
            style: font.merge(numStyle(10.5, weight: today[i] ? FontWeight.w600 : FontWeight.w500, color: today[i] ? p.ink : p.ink2)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        t.paint(canvas, Offset(i * step + (step - t.width) / 2, y(math.max(v, g)) - t.height - 3));
      }
    }
    canvas.drawLine(Offset(0, base + 0.5), Offset(size.width, base + 0.5), Paint()..color = p.lineStrong);
  }

  @override
  bool shouldRepaint(_EnergyPainter old) => true;
}
