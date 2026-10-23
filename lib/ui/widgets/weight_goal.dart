import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../nutrition/insights.dart';
import '../theme.dart';
import 'kit.dart';
import '../../day_clock.dart';
import '../../i18n.dart';
import 'number_input.dart';

/// Doelgewicht met een datum, zoals de rekenhulp het teruggeeft.
typedef WeightGoal = ({double target, DateTime date});

/// Rekenhulp: van je huidige gewicht naar een doelgewicht in een aantal weken of maanden. Toont hoeveel je per dag
/// mag eten en geeft het doel met de datum terug als je het als plan wil gebruiken.
class WeightGoalDialog extends StatefulWidget {
  const WeightGoalDialog({
    super.key,
    required this.current,
    required this.tdee,
    required this.bmr,
    required this.male,
    this.heightCm,
    this.target,
    this.date,
  });
  final double current, tdee, bmr;
  final double? heightCm;
  final bool male;

  /// Het plan dat er al is, om mee te beginnen.
  final double? target;
  final DateTime? date;

  @override
  State<WeightGoalDialog> createState() => _WeightGoalDialogState();
}

class _WeightGoalDialogState extends State<WeightGoalDialog> {
  late final _now = TextEditingController(text: _fmt(widget.current));
  late final _target = TextEditingController(text: widget.target == null ? '' : _fmt(widget.target!));
  late bool _weeks = widget.date != null;
  late final _span = TextEditingController(text: widget.date == null ? '3' : '${_weeksUntil(widget.date!)}');

  static DateTime get _today {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day);
  }

  static int _weeksUntil(DateTime d) => (daysBetween(_today, d) / 7).round().clamp(1, 156);

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).dec;
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _now.dispose();
    _target.dispose();
    _span.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final now = _parse(_now.text), target = _parse(_target.text), span = _parse(_span.text);
    final t = _today;
    final ok = span != null && span > 0 && span <= (_weeks ? 156 : 36);
    final reached = !ok ? null : (_weeks ? DateTime(t.year, t.month, t.day + (span * 7).round()) : DateTime(t.year, t.month + span.round(), t.day));
    // Zelfde rekenwijze als het plan in je profiel: weken tot de datum
    final months = reached == null ? null : daysBetween(t, reached) / 7 * 12 / 52;
    final valid = now != null && target != null && months != null && now >= 30 && target >= 30 && months > 0;
    final plan = valid
        ? WeightPlan.of(
            current: now,
            target: target,
            months: months,
            tdee: widget.tdee,
            bmr: widget.bmr,
            male: widget.male,
            heightCm: widget.heightCm,
          )
        : null;
    final same = plan != null && (target! - now!).abs() < 0.1;

    Widget field(TextEditingController c, String label, String suffix) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: decimalInput,
        onTap: selectAllOnTap(c),
        decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
        onChanged: (_) => setState(() {}),
      ),
    );

    return AlertDialog(
      title: Text(tr('Goal weight calculator', 'Doelgewicht berekenen')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [field(_now, tr('Now', 'Nu'), 'kg'), SizedBox(width: 10), field(_target, tr('Goal', 'Doel'), 'kg')]),
              const SizedBox(height: 10),
              Row(
                children: [
                  field(_span, tr('Within', 'Binnen'), ''),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 190,
                    child: Segmented<bool>(
                      height: 36,
                      items: [(true, tr('weeks', 'weken')), (false, tr('months', 'maanden'))],
                      selected: _weeks,
                      onChanged: (w) => setState(() {
                        final v = _parse(_span.text);
                        if (v != null && w != _weeks) _span.text = _fmt(w ? (v * 52 / 12).roundToDouble() : (v * 12 / 52 * 2).round() / 2);
                        _weeks = w;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (plan == null)
                Text(
                  tr('Enter your goal weight and how long you want to take.', 'Vul je doelgewicht in en hoe lang je erover wil doen.'),
                  style: TextStyle(fontSize: 13, color: pal.ink3),
                )
              else if (same)
                Text(
                  tr('That is your current weight: choose "Maintain".', 'Dat is je huidige gewicht: kies "Behouden".'),
                  style: TextStyle(fontSize: 13, color: pal.ink2),
                )
              else ...[
                // Een onveilig plan krijgt geen geruststellend groen vak en geen negatief aantal kcal
                if (plan.unsafe)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: pal.highSoft, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      plan.dailyKcal <= 0
                          ? tr('This is not possible: you would have to eat less than nothing.', 'Dit kan niet: je zou minder dan niets moeten eten.')
                          : tr(
                              'This plan would mean eating only ${fmtInt(plan.dailyKcal)} kcal a day. Choose a later date or a different goal.',
                              'Dit plan betekent maar ${fmtInt(plan.dailyKcal)} kcal per dag eten. Kies een latere datum of een ander doel.',
                            ),
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: pal.ink),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: pal.brandSoft, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('You can eat about', 'Je mag per dag ongeveer'), style: TextStyle(fontSize: 13, color: pal.ink2)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(fmtInt(plan.dailyKcal), style: numStyle(30, color: pal.ink)),
                            const SizedBox(width: 6),
                            Text(tr('kcal per day', 'kcal eten'), style: TextStyle(fontSize: 14, color: pal.ink2)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            'You ${plan.ratePerWeek < 0 ? 'lose' : 'gain'} ${fmtDec(plan.ratePerWeek.abs(), 2)} kg per week: '
                                '${fmtInt(plan.dailyChange.abs())} kcal ${plan.ratePerWeek < 0 ? 'less' : 'more'} than you burn (${fmtInt(widget.tdee)} kcal) every day. '
                                'Goal reached around ${DateFormat('d MMMM yyyy', appLocale).format(reached!)}.',
                            '${plan.ratePerWeek < 0 ? 'Je valt' : 'Je komt'} ${fmtDec(plan.ratePerWeek.abs(), 2)} kg per week '
                                '${plan.ratePerWeek < 0 ? 'af' : 'aan'}: elke dag ${fmtInt(plan.dailyChange.abs())} kcal '
                                '${plan.ratePerWeek < 0 ? 'minder' : 'meer'} dan je verbruik (${fmtInt(widget.tdee)} kcal). '
                                'Doel bereikt rond ${DateFormat('d MMMM yyyy', appLocale).format(reached)}.',
                          ),
                          style: TextStyle(fontSize: 13, height: 1.45, color: pal.ink),
                        ),
                      ],
                    ),
                  ),
                for (final w in plan.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: pal.high),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(w, style: TextStyle(fontSize: 12.5, height: 1.4, color: pal.ink)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'As a plan, the app recalculates this every time you weigh yourself, so you stay on course to your date. '
                        'Water makes your weight fluctuate: watch your trend.',
                    'Als plan rekent de app dit opnieuw uit telkens je je weegt, zodat je op koers blijft naar je datum. '
                        'Vocht laat je gewicht schommelen: kijk naar je trend.',
                  ),
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: pal.ink3),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close', 'Sluiten'))),
        if (plan != null && !same && !plan.unsafe)
          FilledButton(
            onPressed: () => Navigator.pop<WeightGoal>(context, (target: target!, date: reached!)),
            child: Text(tr('Set as my goal', 'Als mijn doel instellen')),
          ),
      ],
    );
  }
}
