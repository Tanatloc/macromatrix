import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/kit.dart';
import '../../i18n.dart';

/// Lichaam: metingen (gewicht, vetpercentage, bloeddruk, eigen metingen) met grafieken, en de vastentimer.
class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  String _chartType = 'weight';
  int _days = 90;

  static String fmt(double v, int decimals) => v.toStringAsFixed(decimals).dec;

  Future<void> _addMeasurement() async {
    final s = context.read<AppState>();
    final types = s.biometricTypes();
    var type = types.first;
    final v1 = TextEditingController();
    final v2 = TextEditingController();
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Add measurement', 'Meting toevoegen')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<BiometricType>(
                initialValue: type,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('What', 'Wat')),
                items: [for (final t in types) DropdownMenuItem(value: t, child: Text('${t.label} (${t.unit})'))],
                onChanged: (t) => setD(() => type = t!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: v1,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: type.secondLabel == null ? type.label : tr('Systolic', 'Bovendruk'), suffixText: type.unit),
              ),
              if (type.secondLabel != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: v2,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Diastolic', 'Onderdruk'), suffixText: type.unit),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _newCustomType();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Create custom measurement', 'Eigen meting maken')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save', 'Opslaan'))),
          ],
        ),
      ),
    );
    final value = parse(v1);
    if (ok == true && value != null) {
      s.addBiometric(type.key, value, value2: type.secondLabel == null ? null : parse(v2));
      setState(() => _chartType = type.key);
    }
  }

  Future<void> _newCustomType() async {
    final name = TextEditingController();
    final unit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Custom measurement', 'Eigen meting')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Name, e.g. "Energy", "Headache" or "Vitamin D level"', 'Naam, bv. "Energie", "Hoofdpijn" of "Vitamine D-waarde"'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: unit,
              decoration: InputDecoration(labelText: tr('Unit, e.g. "score 1-10" or "nmol/L"', 'Eenheid, bv. "score 1-10" of "nmol/L"')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Create', 'Maken'))),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && mounted) {
      context.read<AppState>().addCustomBiometricType(name.text.trim(), unit.text.trim());
      await _addMeasurement();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final types = s.biometricTypes();
    final byKey = {for (final t in types) t.key: t};
    final chartType = byKey[_chartType] ?? BiometricType.weight;
    final to = DateTime.now();
    final from = DateTime(to.year, to.month, to.day).subtract(Duration(days: _days));
    final history = s.user.biometricHistory(chartType.key, from: dayKey(from));

    Widget card(String title, List<Widget> children, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        shadow: false,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 14, 6),
              child: PanelTitle(title, trailing: trailing),
            ),
            ...children,
          ],
        ),
      ),
    );

    final now = logicalNow();
    final diff = (s.date.difference(DateTime(now.year, now.month, now.day)).inHours / 24).round();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMeasurement,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Measurement', 'Meting')),
      ),
      body: SafeArea(
        bottom: false,
        child: Narrow(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
            children: [
              // Geopend vanuit Profiel: terugknop
              if (Navigator.of(context).canPop())
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: tr('Back', 'Terug'),
                    ),
                  ),
                ),
              PageHeader(
                eyebrow: switch (diff) {
                  0 => tr('Today', 'Vandaag'),
                  -1 => tr('Yesterday', 'Gisteren'),
                  _ => toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', appLocale).format(s.date)),
                },
                title: tr('Body', 'Lichaam'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SquareButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous day', 'Vorige dag'), onPressed: () => s.shiftDay(-1)),
                    const SizedBox(width: 6),
                    SquareButton(icon: Icons.chevron_right_rounded, tooltip: tr('Next day', 'Volgende dag'), onPressed: () => s.shiftDay(1)),
                  ],
                ),
              ),
              const _FastingCard(),
              card(tr('Measurements on this day', 'Metingen op deze dag'), [
                if (s.biometrics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    child: Text(
                      tr('No measurements yet. Tap "Measurement" to add one.', 'Nog geen metingen. Tik op "Meting" om er een toe te voegen.'),
                      style: TextStyle(fontSize: 13.5, color: pal.ink2),
                    ),
                  ),
                for (final b in s.biometrics)
                  ListTile(
                    dense: true,
                    title: Text(byKey[b.type]?.label ?? b.type.replaceFirst('custom:', '')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${fmt(b.value, byKey[b.type]?.decimals ?? 1)}${b.value2 == null ? '' : '/${fmt(b.value2!, 0)}'} ${byKey[b.type]?.unit ?? ''}',
                          style: numStyle(13.5),
                        ),
                        IconButton(icon: Icon(Icons.close, size: 18), tooltip: tr('Delete', 'Verwijderen'), onPressed: () => s.deleteBiometric(b)),
                      ],
                    ),
                    onTap: () => setState(() => _chartType = b.type),
                  ),
              ]),
              card(
                chartType.label,
                [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        for (final t in types.where((t) => t.chartable))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: PillChip(
                              label: t.label,
                              height: 30,
                              selected: t.key == chartType.key,
                              onTap: () => setState(() => _chartType = t.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (history.length >= 2)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Text(
                        '${tr('Latest', 'Laatste')}: ${fmt(history.last.value, chartType.decimals)} ${chartType.unit} · '
                        '${tr('change in this period', 'verschil in deze periode')}: ${history.last.value - history.first.value >= 0 ? '+' : ''}'
                        '${fmt(history.last.value - history.first.value, chartType.decimals)} ${chartType.unit}',
                        style: numStyle(12, weight: FontWeight.w400, color: pal.ink3),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 18, 0),
                    child: TimeSeriesChart(
                      points: [for (final b in history) (parseDay(b.day), b.value)],
                      second: chartType.secondLabel == null
                          ? null
                          : [
                              for (final b in history)
                                if (b.value2 != null) (parseDay(b.day), b.value2!),
                            ],
                      from: from,
                      to: to,
                      color: pal.brand,
                      decimals: chartType.decimals,
                    ),
                  ),
                ],
                trailing: SizedBox(
                  width: 170,
                  child: Segmented<int>(
                    height: 24,
                    fontSize: 11.5,
                    items: [(30, '30 d'), (90, '90 d'), (365, tr('1 year', '1 jaar'))],
                    selected: _days,
                    onChanged: (d) => setState(() => _days = d),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vastentimer: starten met een doel (bv. 16 uur), de teller loopt, stoppen of annuleren.
class _FastingCard extends StatefulWidget {
  const _FastingCard();

  @override
  State<_FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<_FastingCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _dur(Duration d) => '${d.inHours} ${tr('h', 'u')} ${(d.inMinutes % 60).toString().padLeft(2, '0')} min';

  Future<void> _start() async {
    final s = context.read<AppState>();
    final hours = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Start a fast', 'Vasten starten')),
        children: [
          for (final (h, label) in [
            (12.0, tr('12 hours', '12 uur')),
            (14.0, tr('14 hours', '14 uur')),
            (16.0, tr('16:8 (16 hours)', '16:8 (16 uur)')),
            (18.0, tr('18 hours', '18 uur')),
            (20.0, tr('20 hours', '20 uur')),
            (24.0, tr('24 hours', '24 uur')),
          ])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, h), child: Text(label)),
        ],
      ),
    );
    if (hours != null) s.startFast(hours);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final f = s.currentFast;
    if (f == null) {
      final last = s.user.recentFasts(limit: 1).firstOrNull;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          shadow: false,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('Fasting', 'Vasten')),
            subtitle: Text(
              last == null
                  ? tr('No fast in progress.', 'Geen vasten bezig.')
                  : tr('Last time: ${_dur(last.elapsed())}', 'Laatste keer: ${_dur(last.elapsed())}'),
            ),
            trailing: OutlinedButton(onPressed: _start, child: Text(tr('Start', 'Start'))),
          ),
        ),
      );
    }
    final elapsed = f.elapsed();
    final goal = Duration(minutes: (f.goalHours * 60).round());
    final progress = (elapsed.inMinutes / goal.inMinutes).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.timer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Fasting: ${_dur(elapsed)}', 'Aan het vasten: ${_dur(elapsed)}'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: () => s.cancelFast(f), child: Text(tr('Cancel', 'Annuleren'))),
                FilledButton(onPressed: () => s.endFast(f), child: Text(tr('Stop', 'Stoppen'))),
              ],
            ),
            const SizedBox(height: 10),
            Bar(fraction: progress, color: context.pal.brand, height: 8),
            const SizedBox(height: 6),
            Text(
              elapsed >= goal
                  ? tr('Goal of ${f.goalHours.round()} hours reached!', 'Doel van ${f.goalHours.round()} uur gehaald!')
                  : tr(
                      '${_dur(goal - elapsed)} to go until your ${f.goalHours.round()}-hour goal',
                      'Nog ${_dur(goal - elapsed)} tot je doel van ${f.goalHours.round()} uur',
                    ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
