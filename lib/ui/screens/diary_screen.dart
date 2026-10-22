import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/user_db.dart';
import '../../nutrition/insights.dart';
import '../../platform/platform.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'add_food_screen.dart';
import 'food_detail_screen.dart';
import 'nutrient_detail_screen.dart';
import 'scan_screen.dart';
import 'supplements_screen.dart';
import 'recap_screen.dart';
import 'weekly_report_screen.dart';
import '../../nutrition/allergens.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/bio_tips_view.dart';
import '../widgets/exercise_view.dart';
import '../widgets/gap_plan_view.dart';
import '../../i18n.dart';

/// Vandaag: energie en macro's, de 25 vitaminen en mineralen, wat aandacht vraagt, een suggestie,
/// de afgelopen week en de maaltijden.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key, this.onOpenNutrients, this.onOpenProfile});
  final VoidCallback? onOpenNutrients;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final empty = !s.entries.any((e) => !e.foodRef.startsWith('supp:'));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add',
        onPressed: () => openAddFood(context, Meal.forHour(DateTime.now().hour)),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Add', 'Toevoegen')),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            Narrow(child: _Header()),
            Narrow(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!s.hasProfile) ...[_ProfileHint(onOpenProfile: onOpenProfile), const SizedBox(height: 12)],
                    if (empty) ...[const _BudgetCard(), const SizedBox(height: 12), const _StartCard()] else ...[const _EnergyCard()],
                    if (s.note.trim().isNotEmpty) ...[const SizedBox(height: 12), const _NoteCard()],
                    if (s.isToday && s.hasProfile && !s.allergiesAsked) ...[const SizedBox(height: 12), const _AllergyAsk()],
                    if (s.isToday && WeeklyReportCard.shouldShow(s)) ...[const SizedBox(height: 12), const WeeklyReportCard()],
                    if (s.isToday && RecapCard.due(s) != null) ...[const SizedBox(height: 12), const RecapCard()],
                    if (!empty) ...[const SizedBox(height: 12), const _ForTodayCard()],
                    if (s.isToday) const _UsualStrip(),
                    const SizedBox(height: 16),
                    SectionHeader(tr('Meals', 'Maaltijden'), trailing: empty ? null : '${fmtInt(s.totals['energy'])} kcal'),
                    for (final meal in Meal.values) ...[_MealCard(key: ValueKey('${s.day}-${meal.name}'), meal: meal), const SizedBox(height: 8)],
                    const SizedBox(height: 8),
                    const _SupplementCard(),
                    const SizedBox(height: 10),
                    const _ExerciseCard(),
                    if (!empty) ...[
                      if (s.isToday && s.suggestion != null) ...[const SizedBox(height: 16), _SuggestionCard(suggestion: s.suggestion!)],
                      const SizedBox(height: 12),
                      const _WeekCard(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openAddFood(BuildContext context, Meal meal) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddFoodScreen(meal: meal)));

/// ISO-weeknummer.
int isoWeek(DateTime d) {
  // In UTC rekenen: anders scheelt de overgang naar zomertijd een uur en valt de deling een dag te kort
  final day = DateTime.utc(d.year, d.month, d.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  return thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = logicalNow();
    final today = DateTime(now.year, now.month, now.day);
    final diff = (s.date.difference(today).inHours / 24).round();
    final title = switch (diff) {
      0 => tr('Today', 'Vandaag'),
      -1 => tr('Yesterday', 'Gisteren'),
      1 => tr('Tomorrow', 'Morgen'),
      _ => toBeginningOfSentenceCase(DateFormat('EEE d MMM', appLocale).format(s.date)),
    };
    final eyebrow = diff.abs() <= 1
        ? '${DateFormat('EEEE', appLocale).format(s.date)} · week ${isoWeek(s.date)}'
        : '${DateFormat('yyyy', appLocale).format(s.date)} · week ${isoWeek(s.date)}';
    return PageHeader(
      eyebrow: eyebrow,
      title: title,
      titleBadge: diff == 0 ? const StreakFlame() : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquareButton(
            icon: s.note.trim().isEmpty ? Icons.sticky_note_2_outlined : Icons.sticky_note_2_rounded,
            tooltip: tr('Note for this day', 'Notitie bij deze dag'),
            onPressed: () => editNote(context),
          ),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous day', 'Vorige dag'), onPressed: () => s.shiftDay(-1)),
          const SizedBox(width: 6),
          SquareButton(
            icon: Icons.calendar_today_outlined,
            tooltip: tr('Pick a day', 'Kies een dag'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: s.date,
                firstDate: DateTime(2000),
                lastDate: today.add(const Duration(days: 365)),
              );
              if (picked != null) s.setDate(picked);
            },
          ),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.chevron_right_rounded, tooltip: tr('Next day', 'Volgende dag'), onPressed: () => s.shiftDay(1)),
        ],
      ),
    );
  }
}

class _ProfileHint extends StatelessWidget {
  const _ProfileHint({this.onOpenProfile});
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Panel(
      shadow: false,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      onTap: onOpenProfile,
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: p.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Fill in your profile', 'Vul je profiel in'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  tr('Then your energy, vitamin and mineral goals will be right.', 'Dan kloppen je doelen voor energie, vitaminen en mineralen.'),
                  style: TextStyle(fontSize: 13, color: p.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.brand),
        ],
      ),
    );
  }
}

// ── Energie ──

class _EnergyCard extends StatelessWidget {
  const _EnergyCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final eaten = s.totals['energy'];
    final budget = s.targets['energy']?.goal ?? 2000;
    final burned = s.settings.addExercise && s.adaptiveTdee == null ? s.burnedKcal : 0.0;
    final left = budget - eaten;
    final over = left < 0;

    TextStyle label([bool strong = false]) => TextStyle(fontSize: 13, color: strong ? p.ink : p.ink2, fontWeight: strong ? FontWeight.w600 : null);
    Widget ledger(String name, String value, {Color? dot, Color? color, bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(name, style: label(strong))),
          Text(
            value,
            style: numStyle(13, weight: strong ? FontWeight.w600 : FontWeight.w400, color: color ?? p.ink),
          ),
        ],
      ),
    );

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 124,
                height: 124,
                child: CustomPaint(
                  painter: _EnergyRing(eaten: eaten, budget: budget, burned: burned, p: p),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (burned > 0) ...[_BurnedPill(burned: burned), const SizedBox(height: 3)],
                        Text(fmtInt(left.abs()), style: numStyle(30, color: over ? p.high : p.ink, height: 1)),
                        const SizedBox(height: 4),
                        Text(
                          over ? tr('kcal over goal', 'kcal te veel') : tr('kcal left', 'kcal over'),
                          style: TextStyle(fontSize: 12, color: p.ink2),
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
                    ledger(tr('Goal', 'Doel'), fmtInt(budget - burned)),
                    if (burned > 0)
                      InkWell(
                        onTap: () => openDayExercise(context),
                        child: ledger(tr('Exercise', 'Beweging'), '+${fmtInt(burned)}', dot: p.brand, color: p.brand),
                      ),
                    ledger(tr('Eaten', 'Gegeten'), '−${fmtInt(eaten)}', dot: p.ink),
                    Divider(height: 10, color: p.line),
                    ledger(over ? tr('Over goal', 'Te veel') : tr('Left', 'Over'), fmtInt(left.abs()), strong: true, color: over ? p.high : null),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: p.line),
          const SizedBox(height: 12),
          for (final (key, name) in [
            ('protein', tr('Protein', 'Eiwit')),
            ('carbs', tr('Carbs', 'Koolhydr.')),
            ('fat', tr('Fat', 'Vet')),
            ('fiber', tr('Fiber', 'Vezels')),
          ])
            _MacroLine(name: name, amount: s.totals[key], goal: s.targets[key]?.goal ?? 0, color: p.macro(key)),
        ],
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({required this.name, required this.amount, required this.goal, required this.color});
  final String name;
  final double amount;
  final double goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Row(
              children: [
                LegendItem.box(color, w: 7, h: 7),
                const SizedBox(width: 7),
                Text(
                  name,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                ),
              ],
            ),
          ),
          Expanded(
            child: Bar(fraction: goal <= 0 ? 0 : amount / goal, color: color),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: fmtInt(amount),
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: ' / ${fmtInt(goal)} g'),
                ],
              ),
              textAlign: TextAlign.right,
              style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              goal <= 0 ? '' : fmtPct(amount / goal),
              textAlign: TextAlign.right,
              style: numStyle(12, weight: FontWeight.w400, color: p.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// "+337" in de ring: wat beweging vandaag bij je budget legt. Tik erop voor de activiteiten.
class _BurnedPill extends StatelessWidget {
  const _BurnedPill({required this.burned});
  final double burned;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.brandSoft,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => openDayExercise(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_rounded, size: 12, color: p.brand),
              const SizedBox(width: 2),
              Text('+${fmtInt(burned)}', style: numStyle(11.5, color: p.brand)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ring van het energiebudget: gegeten in inkt; het deel dat beweging erbij gaf in de merkkleur;
/// wat je over het budget gaat in rood.
class _EnergyRing extends CustomPainter {
  _EnergyRing({required this.eaten, required this.budget, required this.burned, required this.p});
  final double eaten;
  final double budget;
  final double burned;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;
    const start = -math.pi / 2;
    canvas.drawArc(rect, 0, math.pi * 2, false, arc(p.track)..strokeCap = StrokeCap.butt);
    if (budget <= 0) return;
    final b = (burned / budget).clamp(0, 1).toDouble();
    if (b > 0.01) canvas.drawArc(rect, start + math.pi * 2 * (1 - b), math.pi * 2 * b, false, arc(p.brand.withValues(alpha: 0.55)));
    final f = eaten / budget;
    if (f > 0) canvas.drawArc(rect, start, math.pi * 2 * math.min(1, f), false, arc(p.ink));
    if (f > 1) canvas.drawArc(rect, start, math.pi * 2 * math.min(1, f - 1), false, arc(p.highFill));
  }

  @override
  bool shouldRepaint(_EnergyRing old) => old.eaten != eaten || old.budget != budget || old.burned != burned || old.p != p;
}

// ── Micronutriënten ──

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion});
  final Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    final x = suggestion;
    final amount = x.portion == null ? '${fmtInt(x.grams)} g' : '${x.portion!.label} (${fmtInt(x.grams)} g)';
    final meal = Meal.forHour(DateTime.now().hour);
    return Panel(
      shadow: false,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 13, color: p.brand),
              const SizedBox(width: 6),
              Eyebrow(
                x.mine ? tr('Biggest win · from what you eat', 'Grootste winst · uit wat je eet') : tr('Biggest win today', 'Grootste winst vandaag'),
                color: p.brand,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: amount,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: tr(' ${x.food.name} takes your ', ' ${x.food.name} brengt je ')),
                TextSpan(
                  text: tr(
                    '${inSentence(x.nutrient.name)} from ${fmtPct(x.before)} to ${fmtPct(x.after)}',
                    '${inSentence(x.nutrient.name)} van ${fmtPct(x.before)} naar ${fmtPct(x.after)}',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (x.extra != null)
                  TextSpan(
                    text: tr(
                      ' and adds ${fmtPct(x.extra!.$2)} of your ${inSentence(x.extra!.$1.name)}',
                      ' en geeft ${fmtPct(x.extra!.$2)} van je ${inSentence(x.extra!.$1.name)} erbij',
                    ),
                  ),
                const TextSpan(text: '.'),
              ],
            ),
            style: TextStyle(fontSize: 15, height: 1.45, color: p.ink),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.brand,
                  foregroundColor: p.onBrand,
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FoodDetailScreen(food: x.food, meal: meal, initialGrams: x.grams, initialPortion: x.portion),
                  ),
                ),
                child: Text(tr('Add to ${meal.label.toLowerCase()}', 'Toevoegen aan ${meal.label.toLowerCase()}')),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: x.nutrient))),
                child: Text(tr('Other sources', 'Andere bronnen')),
              ),
            ],
          ),
          if (s.preferences.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tr('Taking into account: ', 'Rekening gehouden met: ') + s.preferences.map((e) => e.label.toLowerCase()).join(', '),
              style: TextStyle(fontSize: 11.5, color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Afgelopen 7 dagen ──

class _WeekCard extends StatelessWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final to = s.date;
    final from = to.subtract(const Duration(days: 6));
    final daily = s.dailyTotals(from, to);
    final days = [for (var i = 0; i < 7; i++) dayKey(from.add(Duration(days: i)))];
    final targets = s.targetsForDate(to);
    List<double?> series(String key) => [for (final d in days) daily[d]?[key]];

    final energyGoal = targets['energy']?.goal ?? 2000;
    final proteinGoal = targets['protein']?.goal ?? 0;
    final kcal = series('energy');
    final protein = series('protein');
    final inBand = kcal.whereType<double>().where((v) => (v - energyGoal).abs() <= energyGoal * 0.1).length;
    final proteinOk = protein.whereType<double>().where((v) => v >= proteinGoal).length;
    final logged = kcal.whereType<double>().length;

    return Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Spark(
              label: tr('Energy avg.', 'Energie gem.'),
              unit: 'kcal',
              values: kcal,
              target: energyGoal,
              color: p.ink,
              note: tr('$inBand of $logged days within ±10%', '$inBand van $logged dagen binnen ±10%'),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _Spark(
              label: tr('Protein avg.', 'Eiwit gem.'),
              unit: 'g',
              values: protein,
              target: proteinGoal,
              color: p.protein,
              note: tr('Goal ${fmtInt(proteinGoal)} g · $proteinOk of $logged days', 'Doel ${fmtInt(proteinGoal)} g · $proteinOk van $logged dagen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({required this.label, required this.unit, required this.values, required this.target, required this.color, required this.note});
  final String label;
  final String unit;
  final List<double?> values;
  final double target;
  final Color color;
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final known = values.whereType<double>().toList();
    final avg = known.isEmpty ? 0.0 : known.reduce((a, b) => a + b) / known.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(known.isEmpty ? '–' : fmtInt(avg), style: numStyle(20)),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(fontSize: 12, color: p.ink3)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparkPainter(values: values, target: target, color: color, guide: p.lineStrong),
          ),
        ),
        const SizedBox(height: 4),
        Text(note, style: TextStyle(fontSize: 11.5, color: p.ink3)),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.target, required this.color, required this.guide});
  final List<double?> values;
  final double target;
  final Color color;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final known = values.whereType<double>().toList();
    final all = [...known, target];
    final maxV = all.reduce(math.max) * 1.08;
    final minV = all.reduce(math.min) * 0.85;
    double y(double v) => maxV == minV ? size.height / 2 : size.height - (v - minV) / (maxV - minV) * size.height;
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    // Doellijn, gestippeld
    final ty = y(target);
    final dash = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 3, size.width), ty), dash);
    }
    final path = Path();
    var started = false;
    Offset? last;
    for (final (i, v) in values.indexed) {
      if (v == null) continue;
      final o = Offset(i * step, y(v));
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
      last = o;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (last != null) canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.target != target || old.color != color;
}

// ── Lege dag ──

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final t = s.targets;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(painter: _EnergyRing(eaten: 0, budget: 1, burned: 0, p: p)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(s.isToday ? tr('Budget today', 'Budget vandaag') : 'Budget'),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(fmtInt(t['energy']?.goal ?? 0), style: numStyle(26)),
                    const SizedBox(width: 5),
                    Text('kcal', style: TextStyle(fontSize: 13, color: p.ink2)),
                  ],
                ),
                Text(
                  tr(
                    '${fmtInt(t['protein']?.goal ?? 0)} g protein · ${fmtInt(t['carbs']?.goal ?? 0)} g carbs · ${fmtInt(t['fat']?.goal ?? 0)} g fat',
                    '${fmtInt(t['protein']?.goal ?? 0)} g eiwit · ${fmtInt(t['carbs']?.goal ?? 0)} g koolh. · ${fmtInt(t['fat']?.goal ?? 0)} g vet',
                  ),
                  style: numStyle(12, weight: FontWeight.w400, color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final meal = Meal.forHour(DateTime.now().hour);
    final yesterday = s.user
        .entriesFor(dayKey(s.date.subtract(const Duration(days: 1))))
        .where((e) => e.meal == meal && !e.foodRef.startsWith('supp:'))
        .toList();
    final saved = s.savedMeals();
    final yesterdayAll = s.user.entriesFor(dayKey(s.date.subtract(const Duration(days: 1)))).where((e) => !e.foodRef.startsWith('supp:')).toList();

    Widget action({required IconData icon, required String title, required String sub, String meta = '', required VoidCallback onTap}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: p.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: p.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.ink2),
                      ),
                    ],
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: numStyle(12.5, weight: FontWeight.w400, color: p.ink3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (var i = 0; i < 25; i++)
                  Opacity(
                    opacity: 1 - i * 0.025,
                    child: Panel(dashed: true, radius: 5, padding: EdgeInsets.zero, child: const SizedBox(width: 20, height: 22)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('Start your day', 'Begin je dag'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: p.ink),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'As soon as you log something, these 25 boxes fill up with your vitamins and minerals. You see right away where you stand.',
              'Zodra je iets logt, vullen deze 25 vakjes zich met je vitaminen en mineralen. Je ziet meteen waar je staat.',
            ),
            style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
          ),
          const SizedBox(height: 8),
          for (final m in saved.take(2))
            action(
              icon: Icons.restaurant_menu_rounded,
              title: m.name,
              sub: m.items.map((i) => i.name).join(' · '),
              meta: '${fmtInt(m.kcal)} kcal',
              onTap: () {
                s.addSavedMeal(m, meal);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('${m.name} added to ${meal.label.toLowerCase()}', '${m.name} toegevoegd aan ${meal.label.toLowerCase()}')),
                  ),
                );
              },
            ),
          if (yesterday.isNotEmpty)
            action(
              icon: Icons.copy_rounded,
              title: tr('Yesterday\'s ${meal.label.toLowerCase()}', '${meal.label} van gisteren'),
              sub: tr(
                'Copy ${yesterday.length} ${yesterday.length == 1 ? 'item' : 'items'}',
                '${yesterday.length} ${yesterday.length == 1 ? 'item' : 'items'} kopiëren',
              ),
              meta: '${fmtInt(yesterday.fold<double>(0, (a, e) => a + e.kcal))} kcal',
              onTap: () => s.copyMealFromYesterday(meal),
            ),
          if (yesterdayAll.map((e) => e.meal).toSet().length > 1)
            action(
              icon: Icons.content_copy_rounded,
              title: tr('Same as yesterday', 'Zoals gisteren'),
              sub: tr('Copy all ${yesterdayAll.length} items of yesterday', 'Alle ${yesterdayAll.length} items van gisteren kopiëren'),
              meta: '${fmtInt(yesterdayAll.fold<double>(0, (a, e) => a + e.kcal))} kcal',
              onTap: () {
                final n = s.copyDayFromYesterday();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('Copied $n items from yesterday', '$n items van gisteren gekopieerd'))));
              },
            ),
          if (canScanBarcodes)
            action(
              icon: Icons.qr_code_scanner_rounded,
              title: tr('Scan barcode', 'Barcode scannen'),
              sub: tr('Look up a branded product', 'Merkproduct opzoeken'),
              onTap: () async {
                final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
                if (code == null || !context.mounted) return;
                final food = await s.lookupBarcode(code);
                if (food != null && context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FoodDetailScreen(food: food, meal: meal),
                    ),
                  );
                }
              },
            )
          else
            action(
              icon: Icons.search_rounded,
              title: tr('Search', 'Zoeken'),
              sub: tr('Basic foods, brands and recipes', 'Basisvoedingsmiddelen, merken en recepten'),
              onTap: () => openAddFood(context, meal),
            ),
        ],
      ),
    );
  }
}

// ── Maaltijden ──

class _MealCard extends StatefulWidget {
  const _MealCard({super.key, required this.meal});
  final Meal meal;

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard> {
  bool _open = false;

  Meal get meal => widget.meal;

  Future<void> _menu(String v) async {
    final s = context.read<AppState>();
    if (v == 'save') {
      final name = await _askName(context, meal);
      if (name != null && name.isNotEmpty) {
        s.saveMealFromDiary(name, meal);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  '"$name" saved. You\'ll find it under Add → Saved meals.',
                  '"$name" opgeslagen. Je vindt het bij Toevoegen → Opgeslagen maaltijden.',
                ),
              ),
            ),
          );
        }
      }
    }
    if (v == 'copy' && mounted) {
      final n = s.copyMealFromYesterday(meal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? tr('You had no ${meal.label.toLowerCase()} yesterday.', 'Gisteren had je geen ${meal.label.toLowerCase()}.')
                : tr('Copied $n ${n == 1 ? 'item' : 'items'} from yesterday.', '$n ${n == 1 ? 'item' : 'items'} gekopieerd van gisteren.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final entries = s.entriesFor(meal);

    final menu = PopupMenuButton<String>(
      tooltip: tr('More', 'Meer'),
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: p.ink3),
      padding: EdgeInsets.zero,
      onSelected: _menu,
      itemBuilder: (_) => [
        PopupMenuItem(value: 'copy', child: Text(tr('Copy from yesterday', 'Kopieer van gisteren'))),
        if (entries.isNotEmpty) PopupMenuItem(value: 'save', child: Text(tr('Save as meal', 'Opslaan als maaltijd'))),
      ],
    );

    if (entries.isEmpty) {
      return Panel(
        dashed: true,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        onTap: () => openAddFood(context, meal),
        child: Row(
          children: [
            Expanded(
              child: Text(
                meal.label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
              ),
            ),
            Text(tr('Nothing logged yet', 'Nog niets gelogd'), style: TextStyle(fontSize: 13, color: p.ink2)),
            const SizedBox(width: 6),
            Icon(Icons.add_rounded, size: 18, color: p.ink2),
            menu,
          ],
        ),
      );
    }

    final kcal = entries.fold<double>(0, (a, e) => a + e.kcal);
    final times = entries.map((e) => e.time).whereType<String>().toList()..sort();
    final split = macroSplit(s.totalsFor(meal).values);

    return Panel(
      shadow: false,
      radius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        meal.label,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      if (times.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          times.first,
                          style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        fmtInt(kcal),
                        style: numStyle(13.5, weight: FontWeight.w500, color: p.ink),
                      ),
                      menu,
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      entries.map((e) => e.name).join(' · '),
                      maxLines: _open ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.ink2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(padding: const EdgeInsets.only(right: 10), child: MacroSplitBar(split)),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in entries) _EntryRow(entry: e),
                      Divider(color: p.line),
                      TextButton.icon(
                        style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.fromLTRB(14, 6, 14, 10)),
                        onPressed: () => openAddFood(context, meal),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('Add to ${meal.label.toLowerCase()}', 'Voeg toe aan ${meal.label.toLowerCase()}')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    final e = entry;
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: p.highSoft,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: p.high),
      ),
      onDismissed: (_) {
        s.deleteEntry(e);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(tr('${e.name} removed', '${e.name} verwijderd')),
              // Met een knop blijft een SnackBar standaard staan tot je tikt; deze moet vanzelf verdwijnen
              persist: false,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(label: tr('Undo', 'Ongedaan maken'), onPressed: () => s.restoreEntry(e)),
            ),
          );
      },
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FoodDetailScreen(food: s.foodFor(e), meal: e.meal, entry: e),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 16, 9),
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
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                    ),
                    Text(
                      [?e.time, ?e.brand, _amountLabel(e)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                fmtInt(e.kcal),
                style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _amountLabel(DiaryEntry e) {
    final g = '${_trim(e.grams)} g';
    if (e.portionLabel == null) return g;
    return '${_trim(e.quantity)} × ${e.portionLabel} ($g)';
  }
}

String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).dec;

Future<String?> _askName(BuildContext context, Meal meal) {
  final c = TextEditingController(text: meal.label);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Save meal', 'Maaltijd opslaan')),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Name, e.g. "My usual breakfast"', 'Naam, bv. "Mijn standaard ontbijt"')),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Save', 'Opslaan'))),
      ],
    ),
  );
}

// ── Beweging en notitie ──

/// Beweging van de dag: verbrande energie telt (standaard) mee in je energiedoel.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard();

  Future<void> _add(BuildContext context) async {
    final s = context.read<AppState>();
    ExerciseType? type = exerciseTypes.first;
    final minutes = TextEditingController(text: '30');
    final kcal = TextEditingController();
    final name = TextEditingController();
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    double estimate() => (type?.met ?? 0) * s.currentWeight * (parse(minutes) ?? 0) / 60;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Add exercise', 'Beweging toevoegen')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ExerciseType?>(
                initialValue: type,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Activity', 'Activiteit')),
                items: [
                  for (final t in exerciseTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t.name, overflow: TextOverflow.ellipsis),
                    ),
                  DropdownMenuItem(value: null, child: Text(tr('Other (enter kcal yourself)', 'Andere (zelf kcal invullen)'))),
                ],
                onChanged: (t) => setD(() => type = t),
              ),
              const SizedBox(height: 12),
              if (type == null) ...[
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Name, e.g. "Spinning"', 'Naam, bv. "Spinning"')),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Duration', 'Duur'), suffixText: 'min'),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kcal,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Burned (empty = estimate)', 'Verbrand (leeg = schatting)'),
                  suffixText: 'kcal',
                  helperText: type == null
                      ? null
                      : tr(
                          'Estimate: ${estimate().round()} kcal (at ${s.currentWeight.round()} kg)',
                          'Schatting: ${estimate().round()} kcal (bij ${s.currentWeight.round()} kg)',
                        ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add', 'Toevoegen'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final burned = parse(kcal) ?? estimate();
    final label = type?.name ?? (name.text.trim().isEmpty ? tr('Exercise', 'Beweging') : name.text.trim());
    if (burned > 0) s.addExercise(label, burned, minutes: parse(minutes));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: PanelTitle(
              tr('Exercise', 'Beweging'),
              trailing: s.burnedKcal > 0
                  ? Text(
                      '${fmtInt(s.burnedKcal)} kcal',
                      style: numStyle(13, weight: FontWeight.w500, color: p.brand),
                    )
                  : null,
            ),
          ),
          for (final e in s.exercise) Padding(padding: const EdgeInsets.only(right: 4), child: ExerciseRow(e)),
          if (s.adaptiveTdee != null && s.exercise.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 10),
              child: Text(
                tr(
                  'Your goal follows your estimated expenditure; your usual activity is already included, so this is not added.',
                  'Je doel volgt je geschatte verbruik; daar zit je gewone beweging al in, dus dit komt er niet bij.',
                ),
                style: TextStyle(fontSize: 11.5, color: p.ink3),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6)),
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr('Add exercise', 'Voeg beweging toe')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Notitie bij de gekozen dag bewerken (onderaan het scherm).
Future<void> editNote(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _NoteSheet());

class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _c = TextEditingController(text: context.read<AppState>().note);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Note for ${s.isToday ? 'today' : DateFormat('EEEE d MMMM', appLocale).format(s.date)}',
              'Notitie bij ${s.isToday ? 'vandaag' : DateFormat('EEEE d MMMM', appLocale).format(s.date)}',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: tr(
                'How did you feel, how did you sleep, anything special you ate, ...',
                'Hoe voelde je je, hoe sliep je, iets bijzonders gegeten, ...',
              ),
            ),
            onChanged: s.setNote,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done', 'Klaar'))),
        ],
      ),
    );
  }
}

/// De notitie van de dag, als er een is. Tik om te bewerken.
class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => editNote(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 18, color: p.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.note, style: TextStyle(fontSize: 14, height: 1.4, color: p.ink)),
          ),
        ],
      ),
    );
  }
}

/// Je supplementen van de dag om aan te vinken.
class _SupplementCard extends StatelessWidget {
  const _SupplementCard();

  void _manage(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupplementsScreen()));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final list = s.supplements;
    if (list.isEmpty) {
      return Panel(
        shadow: false,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => _manage(context),
        child: Row(
          children: [
            Icon(Icons.medication_outlined, size: 20, color: p.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Add supplements', 'Supplementen toevoegen'), style: TextStyle(fontSize: 14, color: p.ink2)),
            ),
            Icon(Icons.chevron_right_rounded, color: p.ink3),
          ],
        ),
      );
    }
    final taken = list.where(s.supplementTaken).length;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.medication_outlined, size: 20, color: p.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Supplements', 'Supplementen'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              Text(tr('$taken of ${list.length}', '$taken van ${list.length}'), style: TextStyle(fontSize: 12.5, color: p.ink3)),
              TextButton(onPressed: () => _manage(context), child: Text(tr('Manage', 'Beheren'))),
            ],
          ),
          for (final sup in list)
            // Material: anders valt het tikeffect weg achter de kaart
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(right: 8),
                controlAffinity: ListTileControlAffinity.leading,
                value: s.supplementTaken(sup),
                onChanged: (v) => s.setSupplementTaken(sup, v ?? false),
                title: Text(sup.name, style: TextStyle(fontSize: 14, color: p.ink)),
                subtitle: Text(sup.dose, style: TextStyle(fontSize: 12, color: p.ink3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Usually for breakfast": wat je meestal eet op dit moment van de dag, met één tik toe te voegen.
class _UsualStrip extends StatelessWidget {
  const _UsualStrip();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final meal = Meal.forHour(DateTime.now().hour);
    if (s.entriesFor(meal).isNotEmpty) return const SizedBox.shrink();
    final usual = s.usualFor(meal);
    if (usual.isEmpty) return const SizedBox.shrink();
    String amount(DiaryEntry e) => e.portionLabel == null
        ? '${fmtInt(e.grams)} g'
        : '${e.quantity == e.quantity.roundToDouble() ? e.quantity.round() : e.quantity} × ${e.portionLabel}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Panel(
        shadow: false,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: p.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Usually for ${meal.label.toLowerCase()}', 'Meestal bij je ${meal.label.toLowerCase()}'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                ),
                if (usual.length > 1)
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                    onPressed: () {
                      for (final e in usual) {
                        s.addAgain(e, meal);
                      }
                    },
                    child: Text(tr('Add all', 'Alles toevoegen')),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in usual)
                  ActionChip(
                    avatar: Icon(Icons.add_rounded, size: 18, color: p.brand),
                    label: Text('${e.name.split(',').first} · ${amount(e)}', overflow: TextOverflow.ellipsis),
                    onPressed: () {
                      s.addAgain(e, meal);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr('${e.name} added to ${meal.label.toLowerCase()}', '${e.name} toegevoegd aan ${meal.label.toLowerCase()}')),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Je reeks naast de titel: oranje vlam met het aantal dagen. Grijs met een uitroepteken als je vandaag nog niets
/// logde en je reeks vanavond zou eindigen.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final streak = s.streak;
    final loggedToday = s.user.loggedDays().contains(dayKey(logicalNow()));
    final atRisk = !loggedToday && streak.current > 0;
    if (streak.current == 0) return const SizedBox.shrink();
    return Tooltip(
      message: atRisk
          ? tr('Log something today to keep your ${streak.current}-day streak', 'Log vandaag iets om je reeks van ${streak.current} dagen te houden')
          : tr('${streak.current} days in a row · longest ${streak.longest}', '${streak.current} dagen op rij · langste ${streak.longest}'),
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: atRisk ? null : const LinearGradient(colors: [Color(0xFFFF8A00), Color(0xFFE5482D)]),
          color: atRisk ? p.surface2 : null,
          border: atRisk ? Border.all(color: p.carbs, width: 1.5) : null,
          boxShadow: atRisk ? null : [BoxShadow(color: const Color(0xFFFF6A00).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 20, color: atRisk ? p.carbs : Colors.white),
            const SizedBox(width: 3),
            Text('${streak.current}', style: numStyle(16, color: atRisk ? p.carbs : Colors.white)),
            if (atRisk) ...[const SizedBox(width: 3), Icon(Icons.priority_high_rounded, size: 16, color: p.carbs)],
          ],
        ),
      ),
    );
  }
}

/// Eén keer vragen naar allergieën (voor wie zijn account aanmaakte voor deze vraag bestond).
class _AllergyAsk extends StatelessWidget {
  const _AllergyAsk();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      color: p.highSoft,
      borderColor: p.highSoft,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: () {
        var picked = <Allergen>{};
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setSheet) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('Your allergies', 'Je allergieën'), style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      tr('Select only what you react to, e.g. just peanuts.', 'Duid alleen aan waarop je reageert, bv. enkel pinda.'),
                      style: TextStyle(fontSize: 13, color: ctx.pal.ink2),
                    ),
                    const SizedBox(height: 12),
                    AllergenPicker(selected: picked, onChanged: (v) => setSheet(() => picked = v)),
                    const SizedBox(height: 10),
                    Text(allergenNote, style: TextStyle(fontSize: 11.5, color: ctx.pal.ink3)),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () {
                        s.setAllergies(picked);
                        Navigator.pop(ctx);
                      },
                      child: Text(picked.isEmpty ? tr('I have no allergies', 'Ik heb geen allergieën') : tr('Save', 'Bewaren')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: p.high),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Do you have food allergies? Set them for warnings.', 'Heb je voedselallergieën? Stel ze in voor waarschuwingen.'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: tr('No allergies', 'Geen allergieën'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => s.setAllergies({}),
          ),
        ],
      ),
    );
  }
}

/// Eén kaart met de tips van de dag: wat je nog kunt eten en een tip voor de opname.
class _ForTodayCard extends StatelessWidget {
  const _ForTodayCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final hasTips = s.bioTipsToday.isNotEmpty;
    if (!s.isToday && !hasTips) return const SizedBox.shrink();
    return Panel(
      shadow: false,
      radius: 16,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Eyebrow(s.isToday ? tr('For today', 'Voor vandaag') : tr('Tips', 'Tips')),
            ),
            if (s.isToday) const GapPlanButton(bare: true),
            if (s.isToday && hasTips) Divider(height: 1, indent: 14, endIndent: 14, color: p.line),
            if (hasTips) const BioTipLine(bare: true),
          ],
        ),
      ),
    );
  }
}
