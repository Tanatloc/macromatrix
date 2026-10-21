/// Beweging van een dag bekijken: per activiteit wat ze je oplevert, en wat je daardoor extra mag eten.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../i18n.dart';
import '../../nutrition/targets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Uit Health Connect overgenomen (de id krijgt daar een vast voorvoegsel) in plaats van zelf toegevoegd.
bool exerciseFromWatch(Exercise e) => e.id.startsWith('hc:');

/// Pictogram bij een activiteit, op de naam gekozen (zowel de MET-lijst als de namen uit Health Connect).
IconData exerciseIcon(String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (has(['hardlopen', 'lopen', 'running', 'run', 'hiit', 'interval'])) return Icons.directions_run_rounded;
  if (has(['wandel', 'hik', 'walk', 'hiking'])) return Icons.directions_walk_rounded;
  if (has(['fiets', 'cycl', 'bik'])) return Icons.directions_bike_rounded;
  if (has(['zwem', 'swim'])) return Icons.pool_rounded;
  if (has(['kracht', 'gewicht', 'strength', 'weight'])) return Icons.fitness_center_rounded;
  if (has(['roei', 'row', 'crosstrainer', 'elliptical'])) return Icons.rowing_rounded;
  if (has(['yoga', 'pilates'])) return Icons.self_improvement_rounded;
  if (has(['voetbal', 'tennis', 'padel', 'soccer', 'sport'])) return Icons.sports_soccer_rounded;
  if (has(['dans', 'dance'])) return Icons.music_note_rounded;
  if (has(['tuinier', 'huishoud', 'garden', 'clean'])) return Icons.home_work_rounded;
  return Icons.local_fire_department_rounded;
}

/// De details van één activiteit.
Future<void> openExercise(BuildContext context, Exercise e) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ExerciseSheet(id: e.id),
);

/// Alle beweging van de gekozen dag; bij één activiteit meteen de details daarvan.
Future<void> openDayExercise(BuildContext context) {
  final s = context.read<AppState>();
  if (s.exercise.length == 1) return openExercise(context, s.exercise.first);
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _DaySheet());
}

/// Eén activiteit in een lijst: tik erop voor de details.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow(this.exercise, {super.key});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = exercise;
    return InkWell(
      onTap: () => openExercise(context, e),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(exerciseIcon(e.name), size: 18, color: p.brand),
            const SizedBox(width: 10),
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
                  Row(
                    children: [
                      if (e.minutes != null)
                        Text(
                          '${e.minutes!.round()} min',
                          style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      if (exerciseFromWatch(e)) ...[
                        if (e.minutes != null) const SizedBox(width: 6),
                        Icon(Icons.watch_outlined, size: 12, color: p.ink3),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${fmtInt(e.kcal)} kcal',
              style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

/// Regel in een overzichtje: naam links, waarde rechts.
class _Ledger extends StatelessWidget {
  const _Ledger(this.name, this.value, {this.color, this.strong = false});
  final String name;
  final String value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 13, color: strong ? p.ink : p.ink2, fontWeight: strong ? FontWeight.w600 : null),
            ),
          ),
          Text(
            value,
            style: numStyle(13, weight: strong ? FontWeight.w600 : FontWeight.w400, color: color ?? p.ink),
          ),
        ],
      ),
    );
  }
}

/// Wat de beweging van de dag met je energiedoel doet. [only] licht één activiteit eruit.
class _GoalEffect extends StatelessWidget {
  const _GoalEffect({this.only});
  final Exercise? only;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final counted = s.settings.addExercise && s.adaptiveTdee == null;
    final budget = s.targets['energy']?.goal ?? 0;
    final burned = s.burnedKcal;

    if (!counted) {
      return Text(
        s.adaptiveTdee != null
            ? tr(
                'Your goal follows your estimated expenditure, which already includes your usual activity, so this is not added on top.',
                'Je doel volgt je geschatte verbruik; daar zit je gewone beweging al in, dus dit komt er niet bij.',
              )
            : tr(
                'Exercise is not added to your goal. You can turn that on under Profile.',
                'Beweging wordt niet bij je doel opgeteld. Dat kun je aanzetten bij je profiel.',
              ),
        style: TextStyle(fontSize: 12.5, color: p.ink3),
      );
    }

    final base = budget - burned;
    final others = burned - (only?.kcal ?? burned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Ledger(tr('Goal without exercise', 'Doel zonder beweging'), fmtInt(base)),
        if (only != null) _Ledger(tr('This activity', 'Deze activiteit'), '+${fmtInt(only!.kcal)}', color: p.brand),
        if (others > 0.5)
          _Ledger(
            only == null ? tr('Exercise', 'Beweging') : tr('Other exercise', 'Andere beweging'),
            '+${fmtInt(others)}',
            color: p.brand,
          ),
        Divider(height: 12, color: p.line),
        _Ledger(tr('Goal today', 'Doel vandaag'), fmtInt(budget), strong: true),
      ],
    );
  }
}

class _ExerciseSheet extends StatelessWidget {
  const _ExerciseSheet({required this.id});
  final String id;

  Future<void> _edit(BuildContext context, Exercise e) async {
    final s = context.read<AppState>();
    final name = TextEditingController(text: e.name);
    final minutes = TextEditingController(text: e.minutes == null ? '' : '${e.minutes!.round()}');
    final kcal = TextEditingController(text: '${e.kcal.round()}');
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Edit exercise', 'Beweging aanpassen')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Activity', 'Activiteit'))),
            const SizedBox(height: 12),
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Duration', 'Duur'), suffixText: 'min'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kcal,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Burned', 'Verbrand'), suffixText: 'kcal'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save', 'Opslaan'))),
        ],
      ),
    );
    if (ok != true) return;
    final burned = parse(kcal);
    final label = name.text.trim();
    if (burned == null || burned <= 0 || label.isEmpty) return;
    s.updateExercise(e, name: label, kcal: burned, minutes: parse(minutes));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final e = s.exercise.where((x) => x.id == id).firstOrNull;
    // Net verwijderd: het venster sluit zichzelf zodra de lijst bijgewerkt is.
    if (e == null) return const SizedBox(height: 120);
    final minutes = e.minutes ?? 0;
    final watch = exerciseFromWatch(e);
    final rest = bmr(s.profile, s.profile.ageIn(s.date.year)) / 1440 * minutes;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
                child: Icon(exerciseIcon(e.name), size: 28, color: p.brand),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              e.name,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.ink),
            ),
            const SizedBox(height: 2),
            Text(
              '${fmtInt(e.kcal)} kcal',
              textAlign: TextAlign.center,
              style: numStyle(30, color: p.brand, height: 1.2),
            ),
            Text(
              watch
                  ? tr('from your watch, via Health Connect', 'van je horloge, via Health Connect')
                  : tr('added by yourself', 'zelf toegevoegd'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.ink3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (minutes > 0) ...[
                  Expanded(child: StatTile(label: tr('Duration', 'Duur'), value: '${minutes.round()} min')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(label: tr('Pace', 'Tempo'), value: '${fmtDec(e.kcal / minutes)} kcal/min'),
                  ),
                ] else
                  Expanded(child: StatTile(label: tr('Duration', 'Duur'), value: tr('unknown', 'onbekend'))),
              ],
            ),
            const SizedBox(height: 16),
            SectionHeader(tr('What you may eat extra', 'Wat je extra mag eten')),
            const SizedBox(height: 4),
            _GoalEffect(only: e),
            if (watch && rest > 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: Text(
                  tr(
                    'Your watch reports the total energy of this session, so about ${fmtInt(rest)} kcal of it is the energy you would also have burned at rest. Your goal already counts that around the clock.',
                    'Je horloge geeft de totale energie van deze sessie door, dus daar zit ongeveer ${fmtInt(rest)} kcal rustverbruik in. Dat rekent je doel ook al de klok rond mee.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: p.ink2, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _edit(context, e),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('Edit', 'Aanpassen')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: p.high),
                    onPressed: () {
                      Navigator.pop(context);
                      s.deleteExercise(e);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(tr('Remove', 'Verwijderen')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySheet extends StatelessWidget {
  const _DaySheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    if (s.exercise.isEmpty) return const SizedBox(height: 120);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Text(
              s.isToday ? tr('Exercise today', 'Beweging vandaag') : tr('Exercise', 'Beweging'),
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.ink),
            ),
            const SizedBox(height: 2),
            Text(
              '${fmtInt(s.burnedKcal)} kcal',
              style: numStyle(30, color: p.brand, height: 1.2),
            ),
            const SizedBox(height: 10),
            for (final e in s.exercise) ExerciseRow(e),
            const SizedBox(height: 14),
            SectionHeader(tr('What you may eat extra', 'Wat je extra mag eten')),
            const SizedBox(height: 4),
            const _GoalEffect(),
          ],
        ),
      ),
    );
  }
}
