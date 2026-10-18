import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../nutrition/insights.dart';
import '../../nutrition/targets.dart';
import '../theme.dart';
import 'kit.dart';
import '../../i18n.dart';

/// Rekenhulp: van je huidige gewicht naar een doelgewicht in een aantal maanden. Toont hoeveel je per dag mag eten
/// en geeft het tempo terug (kg per week) als je het wil gebruiken.
class WeightGoalDialog extends StatefulWidget {
  const WeightGoalDialog({super.key, required this.current, required this.tdee, required this.bmr, required this.male});
  final double current, tdee, bmr;
  final bool male;

  @override
  State<WeightGoalDialog> createState() => _WeightGoalDialogState();
}

class _WeightGoalDialogState extends State<WeightGoalDialog> {
  late final _now = TextEditingController(text: _fmt(widget.current));
  final _target = TextEditingController();
  final _months = TextEditingController(text: '3');

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).dec;
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _now.dispose();
    _target.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final now = _parse(_now.text), target = _parse(_target.text), months = _parse(_months.text);
    final valid = now != null && target != null && months != null && now >= 30 && target >= 30 && months > 0 && months <= 36;
    final plan = valid ? WeightPlan.of(current: now, target: target, months: months, tdee: widget.tdee, bmr: widget.bmr, male: widget.male) : null;
    final same = plan != null && (target! - now!).abs() < 0.1;
    final reached = valid ? DateTime.now().add(Duration(days: (months * 365.25 / 12).round())) : null;

    Widget field(TextEditingController c, String label, String suffix) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              Row(children: [field(_months, tr('Within', 'Binnen'), tr('months', 'maanden'))]),
              const SizedBox(height: 16),
              if (plan == null)
                Text(
                  tr('Enter your goal weight and the number of months.', 'Vul je doelgewicht en het aantal maanden in.'),
                  style: TextStyle(fontSize: 13, color: pal.ink3),
                )
              else if (same)
                Text(
                  tr('That is your current weight: choose "Maintain".', 'Dat is je huidige gewicht: kies "Behouden".'),
                  style: TextStyle(fontSize: 13, color: pal.ink2),
                )
              else ...[
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
                    'An estimate: your expenditure drops as you get lighter, and water makes your weight fluctuate. Watch your trend weight.',
                    'Een schatting: je verbruik daalt mee als je lichter wordt, en vocht laat je gewicht schommelen. Kijk naar je trendgewicht.',
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
        if (plan != null && !same)
          FilledButton(onPressed: () => Navigator.pop(context, plan.ratePerWeek), child: Text(tr('Use this pace', 'Dit tempo gebruiken'))),
      ],
    );
  }
}

/// Tempo uit de rekenhulp omzetten naar een doel en een tempo dat de app toelaat.
(Goal, double) goalFromRate(double rate) => rate < 0
    ? (Goal.lose, double.parse(rate.clamp(-1.0, -0.1).toStringAsFixed(2)))
    : (Goal.gain, double.parse(rate.clamp(0.05, 0.5).toStringAsFixed(2)));
