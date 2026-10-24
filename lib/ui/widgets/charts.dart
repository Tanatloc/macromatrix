import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../theme.dart';

/// Grafiek over een periode: één waarde per dag (staafjes) of losse metingen (lijn), met optioneel een doel
/// en een bovengrens als horizontale lijn.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.points,
    required this.from,
    required this.to,
    required this.color,
    this.goal,
    this.upper,
    this.bars = false,
    this.decimals = 0,
    this.height = 200,
    this.second,
    this.band,
    this.trend,
  });

  final List<(DateTime, double)> points;

  /// Tweede reeks (bv. onderdruk bij bloeddruk).
  final List<(DateTime, double)>? second;
  final DateTime from;
  final DateTime to;
  final Color color;
  final double? goal;
  final double? upper;
  final bool bars;
  final int decimals;
  final double height;

  /// Streefzone (van, tot) als groene band, bv. 4–7 mmol/L bij bloedsuiker (N79).
  final (double, double)? band;

  /// Afgevlakte trend (bv. trendgewicht): een lijn zonder punten; de metingen zelf staan er dan als losse punten bij (N44).
  final List<(DateTime, double)>? trend;

  double _x(DateTime d) => d.difference(from).inHours / 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final days = to.difference(from).inDays.clamp(1, 10000);
    final values = [
      for (final p in points) p.$2,
      ...?second?.map((p) => p.$2),
      ...?trend?.map((p) => p.$2),
      ?goal,
      ?upper,
      ?band?.$1,
      ?band?.$2,
    ];
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            tr('No data in this period yet.', 'Nog geen gegevens in deze periode.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      );
    }
    var minY = bars ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.12 + (maxY == minY ? 1 : 0);
    if (!bars) minY -= pad;
    maxY += pad;

    final lines = ExtraLinesData(
      horizontalLines: [
        if (goal != null)
          HorizontalLine(
            y: goal!,
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(color: muted, fontSize: 10),
              labelResolver: (_) => tr('goal', 'doel'),
            ),
          ),
        if (upper != null)
          HorizontalLine(
            y: upper!,
            color: theme.colorScheme.error,
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(color: muted, fontSize: 10),
              labelResolver: (_) => 'max',
            ),
          ),
      ],
    );

    // Een handvol datums onder de as, niet elke dag
    final step = days <= 8 ? 1 : (days / 6).ceil();
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (v, meta) {
            // Geen label op de uiterste rand als dat geen rond getal is: anders overlapt het met het label ernaast
            final edge = v == meta.max || v == meta.min;
            if (edge && (v % meta.appliedInterval).abs() > 1e-6) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              child: Text(v.toStringAsFixed(decimals).dec, style: TextStyle(fontSize: 10, color: muted)),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: step.toDouble(),
          reservedSize: 24,
          getTitlesWidget: (v, meta) {
            final d = from.add(Duration(days: v.round()));
            return SideTitleWidget(
              meta: meta,
              child: Text('${d.day}/${d.month}', style: TextStyle(fontSize: 10, color: muted)),
            );
          },
        ),
      ),
    );
    final grid = FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
    );

    final chart = bars
        ? BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              alignment: BarChartAlignment.spaceBetween,
              gridData: grid,
              titlesData: titles,
              borderData: FlBorderData(show: false),
              extraLinesData: lines,
              barGroups: [
                for (final (d, v) in points)
                  BarChartGroupData(
                    x: _x(d).round(),
                    barRods: [
                      BarChartRodData(
                        toY: v,
                        color: upper != null && v > upper! ? theme.colorScheme.error : color,
                        width: days > 45 ? 3 : (days > 14 ? 6 : 14),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
              ],
            ),
          )
        : LineChart(
            LineChartData(
              minX: 0,
              maxX: days.toDouble(),
              minY: minY,
              maxY: maxY,
              gridData: grid,
              titlesData: titles,
              borderData: FlBorderData(show: false),
              extraLinesData: lines,
              rangeAnnotations: band == null
                  ? const RangeAnnotations()
                  : RangeAnnotations(
                      horizontalRangeAnnotations: [HorizontalRangeAnnotation(y1: band!.$1, y2: band!.$2, color: context.pal.okSoft)],
                    ),
              lineBarsData: [
                if (trend != null)
                  LineChartBarData(
                    spots: [for (final (d, v) in trend!) FlSpot(_x(d), v)],
                    color: color,
                    barWidth: 2.5,
                    isCurved: false,
                    dotData: const FlDotData(show: false),
                  ),
                for (final (series, c) in [(points, color), if (second != null) (second!, color.withValues(alpha: 0.55))])
                  LineChartBarData(
                    spots: [for (final (d, v) in series) FlSpot(_x(d), v)],
                    // Met een trendlijn: de metingen als losse, lichte punten zonder lijn ertussen
                    color: trend != null ? Colors.transparent : c,
                    barWidth: 2.5,
                    isCurved: false,
                    dotData: trend != null
                        ? FlDotData(
                            getDotPainter: (_, _, _, _) =>
                                FlDotCirclePainter(radius: 3, color: color.withValues(alpha: 0.45), strokeWidth: 0),
                          )
                        : FlDotData(show: series.length < 40),
                  ),
              ],
            ),
          );
    return SizedBox(
      height: height,
      child: Padding(padding: const EdgeInsets.only(right: 8, top: 8), child: chart),
    );
  }
}
