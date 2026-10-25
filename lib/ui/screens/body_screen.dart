import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../nutrition/insights.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/kit.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

// ── Bloedsuiker: bewaard in mmol/L, getoond en ingevuld in de eenheid van je meter (mmol/L of mg/dL), met een
// meetmoment (N23) ──

/// mg/dL per mmol/L voor glucose.
const glucoseMgPerMmol = 18.0;

/// Meetmomenten voor bloedsuiker, zoals bewaard.
const glucoseMoments = ['fasting', 'before_meal', 'after_meal'];

String glucoseMomentLabel(String m) => switch (m) {
  'fasting' => tr('Fasting', 'Nuchter'),
  'before_meal' => tr('Before a meal', 'Voor de maaltijd'),
  'after_meal' => tr('After a meal', 'Na de maaltijd'),
  _ => m,
};

/// Lijkt een bloedsuikerwaarde in de andere eenheid ingevuld (141 als mmol/L is bijna zeker mg/dL)? Geeft de
/// eenheid die past, of null.
String? glucoseOtherUnit(double v, {required bool mgdl}) {
  if (!mgdl && v > 35 && v <= 630) return 'mg/dL';
  if (mgdl && v > 0 && v < 18) return 'mmol/L';
  return null;
}

/// Kies je mg/dL voor bloedsuiker? (Instelling, geldt voor alle metingen.)
bool glucoseInMgdl(AppState s) => s.user.setting('glucose')?['unit'] == 'mg/dL';

/// Lichaam: metingen (gewicht, vetpercentage, bloeddruk, eigen metingen) met grafieken, en de vastentimer.
class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key, this.addWeight = false});

  /// Geopend via "+ › Gewicht": meteen het invulvenster voor je gewicht (N38).
  final bool addWeight;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  String _chartType = 'weight';
  // Standaard 30 dagen: bij 90 stonden alle punten van een nieuwe gebruiker in de laatste week (N44)
  int _days = 30;

  static String fmt(double v, int decimals) => v.toStringAsFixed(decimals).dec;

  // Verwijderde metingen van de laatste seconden: één "Ongedaan maken" zet ze allemaal terug. Een snelle dubbele
  // tik op × wiste vroeger ook de meting die eronder schoof, en Ongedaan maken zette er maar één terug (N04).
  final _deleted = <Biometric>[];
  Timer? _deleteLock, _deleteBatch;

  @override
  void initState() {
    super.initState();
    if (widget.addWeight) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _addMeasurement() : null);
  }

  @override
  void dispose() {
    _deleteLock?.cancel();
    _deleteBatch?.cancel();
    super.dispose();
  }

  void _delete(AppState s, Biometric b) {
    // Kort na een verwijdering geen nieuwe: de volgende × schuift onder de vinger
    if (_deleteLock?.isActive ?? false) return;
    _deleteLock = Timer(const Duration(milliseconds: 600), () {});
    // Wat je binnen enkele seconden na elkaar wist, zet één Ongedaan maken samen terug
    if (!(_deleteBatch?.isActive ?? false)) _deleted.clear();
    _deleteBatch?.cancel();
    _deleteBatch = Timer(const Duration(seconds: 8), () {});
    _deleted.add(b);
    s.deleteBiometric(b);
    final batch = [..._deleted];
    showUndo(
      context,
      batch.length == 1
          ? tr('Measurement removed', 'Meting verwijderd')
          : tr('${batch.length} measurements removed', '${batch.length} metingen verwijderd'),
      () {
        for (final d in batch) {
          s.restoreBiometric(d);
        }
        _deleted.clear();
        _deleteBatch?.cancel();
      },
    );
  }

  /// Meting toevoegen, of met [existing] een bestaande aanpassen (de soort ligt dan vast, alleen de waarde verandert).
  Future<void> _addMeasurement({Biometric? existing}) async {
    final s = context.read<AppState>();
    final types = s.biometricTypes();
    // Een eigen soort die niet meer in de lijst staat, toch kunnen tonen
    final types2 = existing == null || types.any((t) => t.key == existing.type)
        ? types
        : [...types, BiometricType.custom(existing.type.replaceFirst('custom:', ''), '')];
    // Een nieuwe meting staat op de soort van de open grafiek: vanuit Bloedsuiker typte je anders 145 als kg (N78)
    var type = existing == null
        ? types2.firstWhere((t) => t.key == _chartType, orElse: () => types2.first)
        : types2.firstWhere((t) => t.key == existing.type);
    // Tot 3 decimalen (overbodige nullen vallen weg), zodat bewaren zonder te wijzigen niets afrondt
    String text(double? v) => v == null ? '' : fmtNum(v, 3);
    // Bloedsuiker: eenheid van je meter en het meetmoment
    final wasMgdl = glucoseInMgdl(s);
    var mgdl = wasMgdl;
    var moment = existing == null ? null : s.user.biometricMoment(existing.id);
    bool isGlucose() => type.key == 'glucose';
    String unitOf(BiometricType t) => t.key == 'glucose' && mgdl ? 'mg/dL' : t.unit;
    final v1 = TextEditingController(
      text: text(existing != null && existing.type == 'glucose' && mgdl ? existing.value * glucoseMgPerMmol : existing?.value),
    );
    final v2 = TextEditingController(text: text(existing?.value2));
    double? parse(TextEditingController c) => parseNum(c.text);
    String? error1, error2;
    // Vergelijken met je vorige gewicht; bij aanpassen telt de meting zelf niet mee (je verbetert net een tikfout)
    final last = existing == null
        ? s.currentWeight
        : s.user.biometricHistory('weight').where((b) => b.id != existing.id).lastOrNull?.value ?? s.currentWeight;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          // Met de keuzes voor bloedsuiker past het venster niet altijd naast het toetsenbord
          scrollable: true,
          title: Text(existing == null ? tr('Add measurement', 'Meting toevoegen') : tr('Edit measurement', 'Meting aanpassen')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<BiometricType>(
                initialValue: type,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('What', 'Wat')),
                items: [for (final t in types2) DropdownMenuItem(value: t, child: Text('${t.label} (${unitOf(t)})'))],
                onChanged: existing != null ? null : (t) => setD(() => type = t!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: v1,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalInput,
                onTap: selectAllOnTap(v1),
                onChanged: (_) => setD(() => error1 = null),
                decoration: InputDecoration(
                  labelText: type.secondLabel == null ? type.label : tr('Systolic', 'Bovendruk'),
                  suffixText: unitOf(type),
                  errorText: error1,
                ),
              ),
              if (isGlucose()) ...[
                // "141 als mmol/L": vragen of het mg/dL is, met de omrekening
                if (parse(v1) case final v? when glucoseOtherUnit(v, mgdl: mgdl) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            mgdl
                                ? tr('Did you mean ${fmtNum(v, 1)} mmol/L?', 'Bedoel je ${fmtNum(v, 1)} mmol/L?')
                                : tr(
                                    'Did you mean ${fmtNum(v, 0)} mg/dL = ${fmtNum(v / glucoseMgPerMmol, 1)} mmol/L?',
                                    'Bedoel je ${fmtNum(v, 0)} mg/dL = ${fmtNum(v / glucoseMgPerMmol, 1)} mmol/L?',
                                  ),
                            style: TextStyle(fontSize: 13, color: context.pal.ink),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setD(() {
                            mgdl = !mgdl;
                            error1 = null;
                          }),
                          child: Text(tr('Yes, ${mgdl ? 'mmol/L' : 'mg/dL'}', 'Ja, ${mgdl ? 'mmol/L' : 'mg/dL'}')),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                // Eenheid van je meter: een wissel rekent het getal om
                Segmented<bool>(
                  height: 30,
                  items: const [(false, 'mmol/L'), (true, 'mg/dL')],
                  selected: mgdl,
                  onChanged: (m) => setD(() {
                    if (m == mgdl) return;
                    if (parse(v1) case final v?) v1.text = fmtNum(m ? v * glucoseMgPerMmol : v / glucoseMgPerMmol, m ? 0 : 1);
                    mgdl = m;
                    error1 = null;
                  }),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in glucoseMoments)
                      PillChip(
                        label: glucoseMomentLabel(m),
                        height: 30,
                        selected: moment == m,
                        onTap: () => setD(() => moment = moment == m ? null : m),
                      ),
                  ],
                ),
              ],
              if (type.secondLabel != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: v2,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimalInput,
                  onTap: selectAllOnTap(v2),
                  decoration: InputDecoration(labelText: tr('Diastolic', 'Onderdruk'), suffixText: type.unit, errorText: error2),
                ),
              ],
              if (existing == null) ...[
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(
              onPressed: () async {
                // Onmogelijke waarden (vergeten komma, 645 kg) houden we hier al tegen
                final (lo, hi) = isGlucose() && mgdl ? (18.0, 630.0) : _range(type.key);
                setD(() {
                  error1 = rangeError(v1.text, lo, hi, unit: unitOf(type));
                  error2 = type.secondLabel == null ? null : rangeError(v2.text, lo, hi, unit: type.unit);
                });
                if (error1 != null || error2 != null) return;
                // Ongewoon gewicht: vragen terwijl het venster open blijft. "Aanpassen" brengt je terug naar het
                // veld met het getal geselecteerd, in plaats van alles te sluiten (N41, zoals bij eten).
                final value = parse(v1);
                if (value != null && type.key == 'weight' && (value - last).abs() > 5) {
                  final sure = await confirmUnusual(
                    ctx,
                    tr(
                      '${fmt(value, 1)} kg is ${fmt((value - last).abs(), 1)} kg ${value > last ? 'more' : 'less'} than your last weight (${fmt(last, 1)} kg). Your goals are calculated from it.',
                      '${fmt(value, 1)} kg is ${fmt((value - last).abs(), 1)} kg ${value > last ? 'meer' : 'minder'} dan je vorige gewicht (${fmt(last, 1)} kg). Je doelen worden ermee berekend.',
                    ),
                  );
                  if (!ctx.mounted) return;
                  // De focus keert vanzelf terug naar het veld; het getal selecteren zodat je meteen overtypt
                  if (!sure) {
                    selectAllOnTap(v1)();
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: Text(tr('Save', 'Opslaan')),
            ),
          ],
        ),
      ),
    );
    // Bloedsuiker altijd in mmol/L bewaren; de gekozen eenheid onthouden voor de volgende keer
    final glucose = ok == true && type.key == 'glucose';
    final value = switch (parse(v1)) {
      final v? when glucose && mgdl => v / glucoseMgPerMmol,
      final v => v,
    };
    if (glucose && mgdl != wasMgdl) s.user.setSetting('glucose', {...?s.user.setting('glucose'), 'unit': mgdl ? 'mg/dL' : 'mmol/L'});
    if (!mounted) return;
    // Al een gewicht op deze dag: vragen of het nieuwe het vervangt of erbij komt, met het uur van het vorige (N78)
    if (ok == true && value != null && existing == null && type.key == 'weight') {
      final same = s.biometrics.where((b) => b.type == 'weight').lastOrNull;
      if (same != null && mounted) {
        final at = same.time == null ? '' : tr(' at ${same.time}', ' om ${same.time}');
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Replace or add?', 'Vervangen of erbij?')),
            content: Text(
              tr(
                'You already weighed ${fmt(same.value, 1)} kg on this day$at. Your trend uses the last weight of the day.',
                'Je woog op deze dag al ${fmt(same.value, 1)} kg$at. Je trend rekent met het laatste gewicht van de dag.',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep both', 'Allebei houden'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Replace', 'Vervangen'))),
            ],
          ),
        );
        if (replace == null || !mounted) return;
        if (replace) {
          s.user.updateBiometric(same.id, value: value);
          s.restoreBiometric(same);
          setState(() => _chartType = type.key);
          return;
        }
      }
    }
    if (ok == true && value != null) {
      final value2 = type.secondLabel == null ? null : parse(v2);
      if (existing == null) {
        s.addBiometric(type.key, value, value2: value2, moment: glucose ? moment : null);
      } else {
        s.user.updateBiometric(existing.id, value: value, value2: value2);
        if (glucose) s.user.setBiometricMoment(existing.id, moment);
        // "Terugzetten" van de (niet verwijderde) meting laat de app alles opnieuw tonen en neemt een
        // aangepast gewicht over in je profiel, net als na toevoegen of verwijderen
        s.restoreBiometric(existing);
      }
      setState(() => _chartType = type.key);
    }
  }

  /// Redelijk bereik per soort meting; eigen metingen krijgen geen grens.
  static (double, double) _range(String key) => switch (key) {
    'weight' => (25, 300),
    'body_fat' => (2, 70),
    'lean_mass' || 'body_water' => (5, 150),
    'waist' => (40, 200),
    'blood_pressure' => (40, 260),
    'heart_rate' => (25, 220),
    'glucose' => (1, 35),
    'ketones' => (0, 10),
    'sleep' => (0, 24),
    'steps' => (0, 150000),
    _ => (double.negativeInfinity, double.infinity),
  };

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
    // Bloedsuiker in de eenheid van je meter: (factor, eenheid, decimalen) om te tonen
    final mgdl = glucoseInMgdl(s);
    (double, String, int) shownAs(String type) =>
        type == 'glucose' && mgdl ? (glucoseMgPerMmol, 'mg/dL', 0) : (1.0, byKey[type]?.unit ?? '', byKey[type]?.decimals ?? 1);
    final (chartF, chartUnit, chartDec) = shownAs(chartType.key);

    Widget measurementRow(Biometric b) {
      final (f, unit, dec) = shownAs(b.type);
      final moment = b.type == 'glucose' ? s.user.biometricMoment(b.id) : null;
      // Meetmoment en uur, zodat twee metingen van dezelfde soort op één dag uit elkaar te houden zijn (N78)
      final sub = [?(moment == null ? null : glucoseMomentLabel(moment)), ?b.time].join(' · ');
      return ListTile(
        dense: true,
        title: Text(byKey[b.type]?.label ?? b.type.replaceFirst('custom:', '')),
        subtitle: sub.isEmpty ? null : Text(sub),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${fmt(b.value * f, dec)}${b.value2 == null ? '' : '/${fmt(b.value2!, 0)}'} $unit', style: numStyle(13.5)),
            IconButton(icon: Icon(Icons.close, size: 18), tooltip: tr('Delete', 'Verwijderen'), onPressed: () => _delete(s, b)),
          ],
        ),
        // Tikken: de meting aanpassen (en haar grafiek tonen)
        onTap: () {
          setState(() => _chartType = b.type);
          _addMeasurement(existing: b);
        },
      );
    }

    final to = DateTime.now();
    // De dag van de app (begint pas na het nachtelijke omslaguur), in kalenderdagen: niet DateTime.now() en
    // niet 24-uursblokken, anders schuift de as na middernacht of bij een klokwissel een dag op
    final ln = logicalNow();
    final today = DateTime(ln.year, ln.month, ln.day);
    final periodFrom = DateTime(today.year, today.month, today.day - _days);
    final history = s.user.biometricHistory(chartType.key, from: dayKey(periodFrom));
    // Metingen pas sinds kort: de as begint een dag voor de eerste (en toont minstens een week), zodat de punten
    // niet tegen de rechterrand gedrukt staan (N79, N44)
    final first = history.isEmpty ? null : parseDay(history.first.day);
    var from = periodFrom;
    if (first != null && first.difference(periodFrom).inDays > 2) from = first.plusDays(-1);
    final weekAgo = DateTime(today.year, today.month, today.day - 7);
    if (from.isAfter(weekAgo)) from = weekAgo;
    final zoomed = first != null && from != periodFrom;
    // Gewicht: dezelfde trendlijn als op Dashboard, ingelopen vanaf een maand eerder, tot je laatste weging (N44)
    List<(DateTime, double)>? trend;
    if (chartType.key == 'weight' && history.length >= 2) {
      final warm = from.plusDays(-30);
      final byDay = {for (final b in s.user.biometricHistory('weight', from: dayKey(warm))) b.day: b.value};
      final days = [
        for (var d = warm; d.compareTo(parseDay(history.last.day)) <= 0; d = DateTime(d.year, d.month, d.day + 1)) dayKey(d),
      ];
      final t = weightTrend(byDay, days);
      trend = [
        for (final (i, d) in days.indexed)
          if (t[i] != null && !parseDay(d).isBefore(from)) (parseDay(d), t[i]!),
      ];
    }
    // Bloedsuiker: groene streefzone van 4–7 mmol/L (72–126 mg/dL), een gangbaar doel voor de maaltijd (N79)
    final band = chartType.key == 'glucose' ? (4 * chartF, 7 * chartF) : null;
    final fasts = s.currentFast != null || s.user.recentFasts(limit: 1).isNotEmpty;

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
    final header = PageHeader(
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
    );
    final back = Navigator.of(context).canPop();
    final backButton = IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: tr('Back', 'Terug'),
    );
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
              // Geopend vanuit Profiel of een snelkoppeling: terugknop. Op een pc naast de titel, zoals de titelbalk
              // van de andere schermen (P125); op een gsm erboven.
              if (back && isDesktop(context))
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: backButton),
                    Expanded(child: header),
                  ],
                )
              else ...[
                if (back)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(padding: const EdgeInsets.only(top: 6), child: backButton),
                  ),
                header,
              ],
              // Vasten alleen bovenaan voor wie vast; anders staat de kaart onderaan, uit de weg (N38)
              if (fasts) const _FastingCard(),
              card(tr('Measurements on this day', 'Metingen op deze dag'), [
                if (s.biometrics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    child: Text(
                      tr('No measurements yet. Tap "Measurement" to add one.', 'Nog geen metingen. Tik op "Meting" om er een toe te voegen.'),
                      style: TextStyle(fontSize: 13.5, color: pal.ink2),
                    ),
                  ),
                for (final b in s.biometrics) measurementRow(b),
              ]),
              card(
                chartType.label,
                [
                  // Over meerdere regels in plaats van zijwaarts scrollen: met een muis of trackpad kon je de
                  // laatste soorten niet bereiken, en op een gsm viel "Bloedsuiker" buiten beeld (P124)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in types.where((t) => t.chartable))
                          PillChip(label: t.label, height: 30, selected: t.key == chartType.key, onTap: () => setState(() => _chartType = t.key)),
                      ],
                    ),
                  ),
                  if (history.length >= 2)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Text(
                        '${tr('Latest', 'Laatste')}: ${fmt(history.last.value * chartF, chartDec)} $chartUnit · '
                        '${tr('change in this period', 'verschil in deze periode')}: ${history.last.value - history.first.value >= 0 ? '+' : ''}'
                        '${fmt((history.last.value - history.first.value) * chartF, chartDec)} $chartUnit',
                        style: numStyle(12, weight: FontWeight.w400, color: pal.ink3),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 18, 0),
                    child: TimeSeriesChart(
                      points: [for (final b in history) (parseDay(b.day), b.value * chartF)],
                      second: chartType.secondLabel == null
                          ? null
                          : [
                              for (final b in history)
                                if (b.value2 != null) (parseDay(b.day), b.value2!),
                            ],
                      from: from,
                      to: to,
                      color: pal.brand,
                      decimals: chartDec,
                      band: band,
                      trend: trend,
                    ),
                  ),
                  if (trend != null || band != null || zoomed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (trend != null) ...[
                            LegendItem(
                              swatch: LegendItem.box(pal.brand.withValues(alpha: 0.45), w: 7, h: 7, radius: 4),
                              label: tr('weigh-ins', 'wegingen'),
                            ),
                            LegendItem(swatch: LegendItem.box(pal.brand, w: 14, h: 2), label: tr('trend weight', 'trendgewicht')),
                          ],
                          if (band != null)
                            LegendItem(
                              swatch: LegendItem.box(pal.okSoft, w: 14, h: 8, border: pal.okFill),
                              label: mgdl
                                  ? tr('target 72–126 mg/dL before meals', 'streefzone 72–126 mg/dL voor de maaltijd')
                                  : tr('target 4–7 mmol/L before meals', 'streefzone 4–7 mmol/L voor de maaltijd'),
                            ),
                          if (zoomed)
                            Text(
                              tr(
                                'Measurements since ${DateFormat('d MMM', appLocale).format(first)}',
                                'Metingen sinds ${DateFormat('d MMM', appLocale).format(first)}',
                              ),
                              style: TextStyle(fontSize: 11.5, color: pal.ink3),
                            ),
                        ],
                      ),
                    ),
                ],
                // Grote periodeknoppen (minstens 44 px hoog) met duidelijke letters (N94)
                trailing: SizedBox(
                  width: 196,
                  child: Segmented<int>(
                    height: 40,
                    fontSize: 13.5,
                    items: [(30, '30 d'), (90, '90 d'), (365, tr('1 year', '1 jaar'))],
                    selected: _days,
                    onChanged: (d) => setState(() => _days = d),
                  ),
                ),
              ),
              if (!fasts) const _FastingCard(),
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
