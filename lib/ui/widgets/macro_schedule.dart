import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nutrition/targets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';
import '../../i18n.dart';

/// Macroschema: per weekdag een andere verdeling van eiwit, koolhydraten en vet (bv. meer koolhydraten op
/// trainingsdagen). Elke dag is een rij met de verdeling als balk; tik om te wijzigen.
class MacroScheduleCard extends StatelessWidget {
  const MacroScheduleCard({super.key});

  static List<String> get _names => isNl
      ? ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag', 'Zondag']
      : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static DietPreset? _presetOf(double protein, double carbs, double fat) =>
      DietPreset.values.where((d) => d.protein == protein && d.carbs == carbs && d.fat == fat).firstOrNull;

  Future<void> _pickDay(BuildContext context, int weekday) async {
    final s = context.read<AppState>();
    final base = s.profile;
    final current = s.settings.schedule[weekday];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final pal = ctx.pal;
        Widget option({
          required String title,
          required String sub,
          required (double, double, double) split,
          required bool selected,
          required Object value,
        }) => Material(
          color: selected ? pal.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(ctx, value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                        ),
                      ),
                      if (selected) Icon(Icons.check_circle_rounded, color: pal.brand, size: 20),
                    ],
                  ),
                  Text(sub, style: TextStyle(fontSize: 12, color: pal.ink3)),
                  const SizedBox(height: 8),
                  MacroSplitBar(split: split),
                ],
              ),
            ),
          ),
        );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Text(_names[weekday - 1], style: Theme.of(ctx).textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(
                    tr('Choose how you split your energy that day.', 'Kies hoe je je energie die dag verdeelt.'),
                    style: TextStyle(fontSize: 13, color: pal.ink2),
                  ),
                ),
                option(
                  title: tr('Default', 'Standaard'),
                  sub: tr('Your usual split from Profile', 'Je gewone verdeling uit Profiel'),
                  split: (base.proteinPct, base.carbsPct, base.fatPct),
                  selected: current == null,
                  value: 'default',
                ),
                for (final d in DietPreset.values) ...[
                  const SizedBox(height: 4),
                  option(
                    title: d.label,
                    sub: _presetHint(d),
                    split: (d.protein, d.carbs, d.fat),
                    selected: current != null && _presetOf(current.$1, current.$2, current.$3) == d,
                    value: d,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;
    final sched = Map.of(s.settings.schedule);
    if (choice is DietPreset) {
      sched[weekday] = (choice.protein, choice.carbs, choice.fat);
    } else {
      sched.remove(weekday);
    }
    s.saveSettings(s.settings.copyWith(schedule: sched));
  }

  static String _presetHint(DietPreset d) => switch (d.name) {
    'balanced' => tr('A regular, varied split', 'Een gewone, gevarieerde verdeling'),
    'highProtein' => tr('More protein, e.g. for strength training or losing weight', 'Meer eiwit, bv. bij krachttraining of afvallen'),
    'lowCarb' => tr('Fewer carbs, more fat', 'Minder koolhydraten, meer vet'),
    'keto' => tr('Very few carbs', 'Heel weinig koolhydraten'),
    'mediterranean' => tr('Lots of olive oil, fish and vegetables', 'Veel olijfolie, vis en groenten'),
    'endurance' => tr('Lots of carbs, e.g. on long training days', 'Veel koolhydraten, bv. op lange trainingsdagen'),
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final base = s.profile;
    final today = DateTime.now().weekday;
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Macro schedule', 'Macroschema')),
          const SizedBox(height: 4),
          Text(
            tr(
              'A different split of protein, carbs and fat per weekday, for example more carbs on training days. Tap a day to change it.',
              'Een andere verdeling van eiwit, koolhydraten en vet per weekdag, bijvoorbeeld meer koolhydraten op trainingsdagen. Tik op een dag om te wijzigen.',
            ),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: pal.ink3),
          ),
          const SizedBox(height: 10),
          for (var d = 1; d <= 7; d++)
            Builder(
              builder: (context) {
                final sched = s.settings.schedule[d];
                final split = sched ?? (base.proteinPct, base.carbsPct, base.fatPct);
                final label = sched == null
                    ? tr('Default', 'Standaard')
                    : (_presetOf(split.$1, split.$2, split.$3)?.label ?? tr('Custom split', 'Eigen verdeling'));
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _pickDay(context, d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            _names[d - 1],
                            style: TextStyle(fontSize: 14, fontWeight: d == today ? FontWeight.w700 : FontWeight.w500, color: pal.ink),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: sched == null ? FontWeight.w400 : FontWeight.w600,
                                  color: sched == null ? pal.ink3 : pal.brand,
                                ),
                              ),
                              const SizedBox(height: 4),
                              MacroSplitBar(split: split, compact: true),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: pal.ink3),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            children: [
              for (final (label, color) in [
                (tr('Protein', 'Eiwit'), pal.protein),
                (tr('Carbohydrates', 'Koolhydraten'), pal.carbs),
                (tr('Fat', 'Vet'), pal.fat),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LegendItem.box(color),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 12, color: pal.ink2)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Verdeling eiwit / koolhydraten / vet als één balk met de percentages erin.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar({super.key, required this.split, this.compact = false});
  final (double, double, double) split;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final (p, c, f) = split;
    Widget part(double pct, Color color, String name) => Expanded(
      flex: pct.round().clamp(1, 100),
      child: Container(
        color: color,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          pct < 12 ? '${pct.round()}' : (compact ? '${pct.round()}%' : '$name ${pct.round()}%'),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: compact ? 20 : 24,
        child: Row(
          children: [part(p, pal.protein, tr('Protein', 'Eiwit')), part(c, pal.carbs, tr('Carbs', 'Koolh.')), part(f, pal.fat, tr('Fat', 'Vet'))],
        ),
      ),
    );
  }
}
