import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../nutrition/nutrients.dart';
import '../../nutrition/preferences.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/badges_view.dart';
import '../widgets/kit.dart';
import '../widgets/level_card.dart';
import '../widgets/weight_goal.dart';
import 'nutrient_detail_screen.dart';
import 'body_screen.dart';
import 'labs_screen.dart';
import 'oracle_screen.dart';
import 'planner_screen.dart';
import 'shopping_screen.dart';
import 'settings_screen.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

/// Vraag om het Profiel bij de doelen (energie en macro's) te tonen in plaats van bovenaan bij je level (P03).
/// Elke verhoging is één vraag; een profielscherm dat nog niet bestond, handelt een openstaande vraag af bij het openen.
final profileGoalsRequest = ValueNotifier<int>(0);
int _goalsHandled = 0;

/// Naar de doelen in het Profiel scrollen (het tabblad zelf openen doet de shell).
void showProfileGoals() => profileGoalsRequest.value++;

/// Profiel en doelen: energie (doel, tempo, formule of adaptief), macro's, voorkeuren, eigen doelen per
/// voedingsstof en het weekschema. De overige instellingen staan achter het tandwiel.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _energy = TextEditingController(text: _p.energyOverride == null ? '' : _num(_p.energyOverride!));

  Profile get _p => context.read<AppState>().profile;

  final _goalsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    profileGoalsRequest.addListener(_toGoals);
    if (profileGoalsRequest.value > _goalsHandled) _toGoals();
  }

  /// Na de volgende frame (het tabblad moet eerst zichtbaar zijn) naar de energiekaart scrollen.
  void _toGoals() {
    _goalsHandled = profileGoalsRequest.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _goalsKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    });
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.dec;
  static double? _parse(String s) => double.tryParse(s.replaceAll(',', '.'));

  @override
  void dispose() {
    profileGoalsRequest.removeListener(_toGoals);
    _energy.dispose();
    super.dispose();
  }

  static DietPreset? _presetOf(double protein, double carbs, double fat) =>
      DietPreset.values.where((d) => d.protein == protein && d.carbs == carbs && d.fat == fat).firstOrNull;

  void _update(Profile p) => context.read<AppState>().saveProfile(p);

  /// Macro's aanpassen zodat ze samen 100% blijven. Het verschil gaat eerst naar koolhydraten,
  /// bij een wijziging van koolhydraten naar vet; is dat op, dan schuift de derde mee.
  void _setMacro(String key, double v) {
    var protein = _p.proteinPct, carbs = _p.carbsPct, fat = _p.fatPct;
    switch (key) {
      case 'protein':
        protein = v;
        carbs = (100 - protein - fat).clamp(0, 100);
        fat = 100 - protein - carbs;
      case 'fat':
        fat = v;
        carbs = (100 - protein - fat).clamp(0, 100);
        protein = 100 - fat - carbs;
      default:
        carbs = v;
        fat = (100 - protein - carbs).clamp(0, 100);
        protein = 100 - carbs - fat;
    }
    _update(_p.copyWith(proteinPct: protein, carbsPct: carbs, fatPct: fat));
  }

  /// Persoonlijke gegevens wijzigen in een onderblad.
  Future<void> _editBody() async {
    final year = DateTime.now().year;
    final birth = TextEditingController(text: '${_p.birthYear}');
    final weight = TextEditingController(text: _num(_p.weightKg));
    final height = TextEditingController(text: _num(_p.heightCm));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setS) {
            final p = ctx.read<AppState>().profile;
            // Alleen waarden binnen een redelijk bereik tellen; daarbuiten blijft de oude waarde en staat er waarom
            Widget field(String label, TextEditingController c, String suffix, double min, double max, void Function(double) onValue) => Expanded(
              child: TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalInput,
                onTap: selectAllOnTap(c),
                decoration: InputDecoration(
                  labelText: label,
                  suffixText: suffix,
                  errorText: rangeError(c.text, min, max, unit: suffix),
                  errorMaxLines: 3,
                ),
                onChanged: (t) {
                  final v = _parse(t);
                  if (v != null && v >= min && v <= max) onValue(v);
                  setS(() {});
                },
              ),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('About you', 'Over jou'), style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 14),
                Segmented<Sex>(
                  items: [for (final x in Sex.values) (x, x.label)],
                  selected: p.sex,
                  onChanged: (v) => setS(() => _update(p.copyWith(sex: v))),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field(tr('Born in', 'Geboren in'), birth, '', year - 100.0, year - 18.0, (v) {
                      _update(ctx.read<AppState>().profile.copyWith(birthYear: v.round()));
                    }),
                    const SizedBox(width: 10),
                    field(tr('Height', 'Lengte'), height, 'cm', 120, 230, (v) => _update(ctx.read<AppState>().profile.copyWith(heightCm: v))),
                    const SizedBox(width: 10),
                    field(tr('Weight', 'Gewicht'), weight, 'kg', 25, 300, (v) => _update(ctx.read<AppState>().profile.copyWith(weightKg: v))),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Activity>(
                  initialValue: p.activity,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Activity', 'Activiteit')),
                  items: [
                    for (final a in Activity.values)
                      DropdownMenuItem(
                        value: a,
                        child: Text('${a.label}: ${a.description}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (a) => setS(() => _update(ctx.read<AppState>().profile.copyWith(activity: a))),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'The reference values apply to adults (18+), not during pregnancy or breastfeeding.',
                    'De richtwaarden gelden voor volwassenen (18+), niet tijdens zwangerschap of borstvoeding.',
                  ),
                  style: TextStyle(fontSize: 12, color: ctx.pal.ink3),
                ),
                const SizedBox(height: 14),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done', 'Klaar'))),
              ],
            );
          },
        ),
      ),
    );
    for (final c in [birth, weight, height]) {
      c.dispose();
    }
  }

  /// Voedingsstof kiezen om een eigen doel voor in te stellen.
  Future<void> _pickNutrient() async {
    final picked = await showModalBottomSheet<Nutrient>(context: context, isScrollControlled: true, builder: (ctx) => _NutrientPicker());
    if (picked != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: picked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final p = s.profile;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Narrow(
              maxWidth: isDesktop(context) ? wideMaxWidth : 760,
              child: PageHeader(
                eyebrow: tr('Your goals and level', 'Je doelen en level'),
                title: tr('Profile', 'Profiel'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: tr('Settings', 'Instellingen'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                  ],
                ),
              ),
            ),
            Narrow(
              maxWidth: isDesktop(context) ? wideMaxWidth : 760,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Op een pc: links je level, badges en metingen, rechts je doelen
                child: SplitColumns(
                  leftFlex: 4,
                  rightFlex: 5,
                  left: [
                    const LevelCard(),
                    const SizedBox(height: 10),
                    const BadgesCard(),
                    const SizedBox(height: 10),
                    Panel(
                      shadow: false,
                      radius: 16,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final (icon, title, sub, screen) in [
                            (
                              Icons.event_note_outlined,
                              tr('Meal planner', 'Maaltijdplanner'),
                              tr('Plan tomorrow and see your score in advance', 'Plan morgen en zie vooraf je score'),
                              const PlannerScreen() as Widget,
                            ),
                            (
                              Icons.shopping_cart_outlined,
                              tr('Shopping list', 'Boodschappenlijst'),
                              tr('From your plans and for your shortfalls', 'Uit je plannen en voor je tekorten'),
                              const ShoppingScreen(),
                            ),
                            (
                              Icons.travel_explore_rounded,
                              tr('Ask the Oracle', 'Vraag het Orakel'),
                              tr('Foods richest in a nutrient', 'Voeding die het rijkst is aan een stof'),
                              const OracleScreen(),
                            ),
                          ])
                            ListTile(
                              leading: Icon(icon, color: pal.brand),
                              title: Text(
                                title,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                              ),
                              subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: pal.ink2)),
                              trailing: Icon(Icons.chevron_right_rounded, color: pal.ink3),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Panel(
                      shadow: false,
                      radius: 16,
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyScreen())),
                      child: Row(
                        children: [
                          Icon(Icons.monitor_weight_outlined, color: pal.brand),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Body and measurements', 'Lichaam en metingen'),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                                ),
                                Text(
                                  tr('Weight, fasting, blood pressure and more', 'Gewicht, vasten, bloeddruk en meer'),
                                  style: TextStyle(fontSize: 12.5, color: pal.ink2),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: pal.ink3),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Panel(
                      shadow: false,
                      radius: 16,
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LabsScreen())),
                      child: Row(
                        children: [
                          Icon(Icons.bloodtype_outlined, color: pal.brand),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Blood values', 'Bloedwaarden'),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                                ),
                                Text(
                                  s.labResults.isEmpty
                                      ? tr('Read your lab report and get advice that fits', 'Lees je labo-verslag in en krijg advies dat erbij past')
                                      : tr(
                                          'Last blood test: ${DateFormat('d MMM yyyy', appLocale).format(DateTime.parse(s.labResults.first.day))}',
                                          'Laatste bloedafname: ${DateFormat('d MMM yyyy', appLocale).format(DateTime.parse(s.labResults.first.day))}',
                                        ),
                                  style: TextStyle(fontSize: 12.5, color: pal.ink2),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: pal.ink3),
                        ],
                      ),
                    ),
                  ],
                  right: [
                    KeyedSubtree(key: _goalsKey, child: _energyCard(s, pal, p)),
                    const SizedBox(height: 10),
                    _macroCard(s, pal, p),
                    const SizedBox(height: 10),
                    _preferencesCard(s, pal),
                    const SizedBox(height: 10),
                    _customTargetsCard(s, pal),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rekenhulp voor een doelgewicht; bewaart doel en datum als plan (en wist dan een eigen energiedoel).
  Future<void> _weightGoal(AppState s, Profile p) async {
    final year = DateTime.now().year;
    final plan = await showDialog<WeightGoal>(
      context: context,
      builder: (_) => WeightGoalDialog(
        current: s.currentWeight,
        tdee: s.adaptiveTdee ?? formulaTdee(p, year),
        bmr: bmr(p, p.ageIn(year)),
        male: p.sex == Sex.male,
        heightCm: p.heightCm,
        target: p.hasPlan ? p.targetWeightKg : null,
        date: p.hasPlan ? p.targetDate : null,
      ),
    );
    if (plan == null || !mounted) return;
    _energy.clear();
    final next = p.copyWith(
      goal: plan.target < s.currentWeight ? Goal.lose : Goal.gain,
      rateKgPerWeek: () => null,
      energyOverride: () => null,
      targetWeightKg: () => plan.target,
      targetDate: () => plan.date,
    );
    _update(next);
    final need = next.planRate ?? 0;
    if ((need - next.rate).abs() > 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'That needs ${fmtDec(need.abs(), 2)} kg per week; the app keeps it at ${fmtDec(next.rate.abs(), 2)}, so you will reach your goal a bit later.',
              'Dat vraagt ${fmtDec(need.abs(), 2)} kg per week; de app houdt het op ${fmtDec(next.rate.abs(), 2)}, dus je haalt je doel wat later.',
            ),
          ),
        ),
      );
    }
  }

  /// Wat het plan nog vraagt: doelgewicht, datum, wat er rest en het tempo van vandaag.
  Widget _planBox(Palette pal, Profile p) {
    final left = p.targetWeightKg! - p.weightKg;
    final days = daysBetween(logicalNow(), p.targetDate!);
    final need = p.planRate ?? 0;
    final done = need == 0;
    final String status;
    if (done) {
      status = tr('Goal reached! Choose "Maintain" or set a new goal.', 'Doel bereikt! Kies "Behouden" of stel een nieuw doel in.');
    } else if (days <= 0) {
      status = tr(
        'Your date has passed, ${fmtDec(left.abs())} kg to go. Set a new date.',
        'Je datum is voorbij, nog ${fmtDec(left.abs())} kg. Kies een nieuwe datum.',
      );
    } else {
      final weeks = days >= 14 ? tr('${(days / 7).round()} weeks', '${(days / 7).round()} weken') : tr('$days days', '$days dagen');
      status = tr(
        '${fmtDec(left.abs())} kg to go in $weeks: ${need < 0 ? '−' : '+'}${fmtDec(need.abs(), 2)} kg per week',
        'Nog ${fmtDec(left.abs())} kg in $weeks: ${need < 0 ? '−' : '+'}${fmtDec(need.abs(), 2)} kg per week',
      );
    }
    final capped = !done && (need - p.rate).abs() > 0.005;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      decoration: BoxDecoration(color: pal.brandSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 18, color: pal.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    '${_num(p.targetWeightKg!)} kg by ${DateFormat('d MMMM yyyy', appLocale).format(p.targetDate!)}',
                    '${_num(p.targetWeightKg!)} kg op ${DateFormat('d MMMM yyyy', appLocale).format(p.targetDate!)}',
                  ),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26, right: 8),
            child: Text(status, style: TextStyle(fontSize: 12.5, height: 1.4, color: pal.ink2)),
          ),
          if (capped)
            Padding(
              padding: const EdgeInsets.only(left: 26, right: 8, top: 4),
              child: Text(
                tr(
                  'Faster than healthy: the app keeps it at ${fmtDec(p.rate.abs(), 2)} kg per week.',
                  'Sneller dan gezond: de app houdt het op ${fmtDec(p.rate.abs(), 2)} kg per week.',
                ),
                style: TextStyle(fontSize: 12, height: 1.4, color: pal.high),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Wrap(
              children: [
                TextButton(onPressed: () => _weightGoal(context.read<AppState>(), p), child: Text(tr('Change', 'Wijzigen'))),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(tr('Stop your plan?', 'Je plan stoppen?')),
                        content: Text(tr('Your goal goes back to keeping your weight.', 'Je doel gaat terug naar je gewicht behouden.')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Stop plan', 'Plan stoppen'))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      _update(p.copyWith(targetWeightKg: () => null, targetDate: () => null, goal: Goal.maintain, rateKgPerWeek: () => null));
                    }
                  },
                  child: Text(tr('Stop plan', 'Plan stoppen')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _energyCard(AppState s, Palette pal, Profile p) {
    final year = DateTime.now().year;
    final kcal = energyTarget(p, year, tdee: s.adaptiveTdee);

    Widget chip(String text) => Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: pal.surface2,
        border: Border.all(color: pal.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          style: numStyle(12, weight: FontWeight.w400, color: pal.ink2),
        ),
      ),
    );

    final rate = p.rate;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Energy', 'Energie'),
            trailing: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
              onPressed: _editBody,
              child: Text(tr('Edit details', 'Gegevens wijzigen')),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(p.sex.label),
              chip(tr('${p.ageIn(year)} years', '${p.ageIn(year)} jaar')),
              chip('${_num(p.heightCm)} cm'),
              chip('${fmtDec(s.currentWeight)} kg'),
              chip(p.activity.label),
            ],
          ),
          const SizedBox(height: 14),
          Segmented<Goal>(
            height: 32,
            items: [for (final g in Goal.values) (g, g.label)],
            selected: p.goal,
            onChanged: (g) => _update(p.copyWith(goal: g, rateKgPerWeek: () => null, targetWeightKg: () => null, targetDate: () => null)),
          ),
          if (p.hasPlan) ...[
            const SizedBox(height: 12),
            _planBox(pal, p),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _weightGoal(s, p),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(tr('Set a goal weight and date: how much can I eat?', 'Doelgewicht en datum kiezen: hoeveel mag ik eten?')),
              ),
            ),
          if (p.goal != Goal.maintain && !p.hasPlan) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Pace', 'Tempo'), style: TextStyle(fontSize: 13, color: pal.ink2)),
                      Text(
                        tr(
                          '${p.goalKcal < 0 ? '−' : '+'}${fmtInt(p.goalKcal.abs())} kcal per day',
                          '${p.goalKcal < 0 ? '−' : '+'}${fmtInt(p.goalKcal.abs())} kcal per dag',
                        ),
                        style: numStyle(11.5, weight: FontWeight.w400, color: pal.ink3),
                      ),
                    ],
                  ),
                ),
                StepButton(
                  icon: Icons.remove_rounded,
                  tooltip: p.goal == Goal.lose ? tr('Slower', 'Trager') : tr('Slower', 'Trager'),
                  size: 28,
                  onTap: () {
                    final next = p.goal == Goal.lose ? (rate + 0.05).clamp(-1.0, -0.1) : (rate - 0.05).clamp(0.05, 0.5);
                    _update(p.copyWith(rateKgPerWeek: () => double.parse(next.toStringAsFixed(2))));
                  },
                ),
                SizedBox(
                  width: 112,
                  child: Text('${rate < 0 ? '−' : '+'}${fmtDec(rate.abs(), 2)} kg/week', textAlign: TextAlign.center, style: numStyle(14)),
                ),
                StepButton(
                  icon: Icons.add_rounded,
                  tooltip: tr('Faster', 'Sneller'),
                  size: 28,
                  onTap: () {
                    final next = p.goal == Goal.lose ? (rate - 0.05).clamp(-1.0, -0.1) : (rate + 0.05).clamp(0.05, 0.5);
                    _update(p.copyWith(rateKgPerWeek: () => double.parse(next.toStringAsFixed(2))));
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(color: pal.line),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Daily goal', 'Dagdoel'),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: pal.ink),
                    ),
                    Text(
                      p.energyOverride != null
                          ? tr('custom goal', 'eigen doel')
                          : (s.adaptiveTdee != null
                                ? tr('your usual activity is already included', 'je gewone beweging zit al in je verbruik')
                                : (s.settings.addExercise
                                      ? tr('exercise is added automatically', 'beweging komt er automatisch bij')
                                      : tr('without exercise', 'zonder beweging'))),
                      style: TextStyle(fontSize: 11.5, color: pal.ink3),
                    ),
                  ],
                ),
              ),
              Text(fmtInt(kcal), style: numStyle(24)),
              const SizedBox(width: 4),
              Text(
                'kcal',
                style: numStyle(12, weight: FontWeight.w400, color: pal.ink3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _energy,
            keyboardType: TextInputType.number,
            inputFormatters: wholeInput,
            onTap: selectAllOnTap(_energy),
            decoration: InputDecoration(
              labelText: tr('Custom energy goal (empty = calculate)', 'Eigen energiedoel (leeg = berekenen)'),
              suffixText: 'kcal',
              isDense: true,
              errorText: rangeError(_energy.text, 1000, 6000, unit: 'kcal', optional: true),
              errorMaxLines: 2,
            ),
            onChanged: (t) {
              final v = _parse(t);
              _update(_p.copyWith(energyOverride: () => (v != null && v >= 1000 && v <= 6000) ? v : null));
            },
          ),
        ],
      ),
    );
  }

  /// Een macro in grammen instellen (bv. 180 g eiwit); de app rekent dat om naar een percentage van je energie.
  Future<void> _editMacroGrams(String key, String label, AppState s) async {
    final kcalPerGram = key == 'fat' ? 9.0 : 4.0;
    final kcal = s.targets['energy']?.goal ?? 2000;
    final c = TextEditingController(text: fmtInt(s.targets[key]!.goal!));
    final grams = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('$label in grams', '$label in grammen')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput,
          onTap: selectAllOnTap(c),
          decoration: InputDecoration(
            suffixText: 'g',
            helperText: tr('For today, at ${fmtInt(kcal)} kcal', 'Voor vandaag, bij ${fmtInt(kcal)} kcal'),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, parseNum(c.text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: Text(tr('Set', 'Instellen'))),
        ],
      ),
    );
    if (grams == null || grams <= 0 || kcal <= 0) return;
    final pct = (grams * kcalPerGram / kcal * 100).clamp(0, 85).toDouble();
    _setMacro(key, pct);
  }

  Widget _macroCard(AppState s, Palette pal, Profile p) {
    final preset = _presetOf(p.proteinPct, p.carbsPct, p.fatPct);
    final rows = [
      (
        'protein',
        tr('Protein', 'Eiwit'),
        p.proteinPct,
        tr(
          '${fmtDec(s.targets['protein']!.goal! / s.currentWeight)} g per kg body weight',
          '${fmtDec(s.targets['protein']!.goal! / s.currentWeight)} g per kg lichaamsgewicht',
        ),
      ),
      ('carbs', tr('Carbohydrates', 'Koolhydraten'), p.carbsPct, tr('what remains', 'wat overblijft')),
      ('fat', tr('Fat', 'Vet'), p.fatPct, '${fmtDec(s.targets['fat']!.goal! / s.currentWeight)} g per kg'),
    ];
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelTitle("Macro's"),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in DietPreset.values)
                PillChip(
                  label: d.label,
                  selected: preset == d,
                  height: 30,
                  onTap: () {
                    final before = p;
                    _update(p.copyWith(proteinPct: d.protein, carbsPct: d.carbs, fatPct: d.fat));
                    showUndo(context, tr('Macros set to ${d.label}', "Macro's op ${d.label}"), () => _update(before));
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          MacroSplitBar((p.proteinPct / 100, p.carbsPct / 100, p.fatPct / 100), height: 10),
          const SizedBox(height: 4),
          for (final (i, (key, label, pct, rule)) in rows.indexed)
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: pal.line)),
              ),
              margin: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: Column(
                children: [
                  Row(
                    children: [
                      LegendItem.box(pal.macro(key), w: 10, h: 10, radius: 3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: pal.ink),
                            ),
                            Text(
                              rule,
                              style: numStyle(10.5, weight: FontWeight.w400, color: pal.ink3),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${pct.round()}%',
                        style: numStyle(12, weight: FontWeight.w400, color: pal.ink3),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => _editMacroGrams(key, label, s),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 30,
                          constraints: const BoxConstraints(minWidth: 64),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: pal.surface2,
                            border: Border.all(color: pal.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${fmtInt(s.targets[key]!.goal!)} g', style: numStyle(14)),
                              const SizedBox(width: 4),
                              Icon(Icons.edit_rounded, size: 12, color: pal.ink3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(activeTrackColor: pal.macro(key), thumbColor: pal.macro(key), trackHeight: 3),
                    child: Slider(
                      value: pct.clamp(0, 85).toDouble(),
                      min: 0,
                      max: 85,
                      divisions: 85,
                      label: '${pct.round()}%',
                      onChanged: (v) => _setMacro(key, v.roundToDouble()),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            tr(
              'Grams for today. EFSA recommends at least 0.83 g protein per kg; people who train a lot often take 1.6 to 2.2 g per kg. '
                  'Fiber: at least ${fmtInt(s.targets['fiber']?.goal ?? 25)} g.',
              'Grammen voor vandaag. EFSA raadt minstens 0,83 g eiwit per kg aan; wie veel traint, neemt vaak 1,6 à 2,2 g per kg. '
                  'Vezels: minstens ${fmtInt(s.targets['fiber']?.goal ?? 25)} g.',
            ),
            style: TextStyle(fontSize: 11.5, height: 1.45, color: pal.ink3),
          ),
        ],
      ),
    );
  }

  Widget _preferencesCard(AppState s, Palette pal) => Panel(
    shadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelTitle(tr('Preferences and restrictions', 'Voorkeuren en beperkingen')),
        const SizedBox(height: 2),
        Text(
          tr('Suggestions and "richest sources" take these into account.', 'Suggesties en "rijkste bronnen" houden hier rekening mee.'),
          style: TextStyle(fontSize: 12, color: pal.ink3),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in DietPref.values)
              PillChip(
                label: d.label,
                check: true,
                height: 30,
                selected: s.preferences.contains(d),
                onTap: () {
                  final next = Set.of(s.preferences);
                  next.contains(d) ? next.remove(d) : next.add(d);
                  s.setPreferences(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          tr(
            'Detection is based on the product name. With an allergy, always check the label.',
            'Herkenning gebeurt op de productnaam. Bij een allergie controleer je altijd het etiket.',
          ),
          style: TextStyle(fontSize: 11.5, color: pal.ink3),
        ),
      ],
    ),
  );

  Widget _customTargetsCard(AppState s, Palette pal) {
    final overrides = s.settings.overrides.entries.where((e) => nutrientByKey.containsKey(e.key)).toList();
    String describe(Nutrient n, Target? t) => t == null || (t.goal == null && t.upper == null)
        ? '–'
        : t.goal != null
        ? '${formatAmount(t.goal!, n)} ${n.unit}'
        : 'max ${formatAmount(t.upper!, n)} ${n.unit}';
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Custom goals', 'Eigen doelen'),
            trailing: Text(
              tr('rest follows EFSA', 'rest volgt EFSA'),
              style: numStyle(11.5, weight: FontWeight.w400, color: pal.ink3),
            ),
          ),
          for (final e in overrides)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: nutrientByKey[e.key]!))),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: pal.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        nutrientByKey[e.key]!.name,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: pal.ink),
                      ),
                    ),
                    Text(
                      describe(nutrientByKey[e.key]!, s.defaultTargets[e.key]),
                      style: numStyle(12, weight: FontWeight.w400, color: pal.ink3).copyWith(decoration: TextDecoration.lineThrough),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 12, color: pal.ink3),
                    const SizedBox(width: 8),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: pal.brandSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(describe(nutrientByKey[e.key]!, e.value), style: numStyle(13, color: pal.brand)),
                    ),
                  ],
                ),
              ),
            ),
          if (overrides.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                tr('You follow the EFSA reference values everywhere.', 'Je volgt overal de EFSA-richtwaarden.'),
                style: TextStyle(fontSize: 13, color: pal.ink2),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), foregroundColor: pal.ink2),
            onPressed: _pickNutrient,
            child: Text(tr('+ Goal for a nutrient', '+ Doel voor een voedingsstof')),
          ),
        ],
      ),
    );
  }
}

/// Doorzoekbare lijst van voedingsstoffen.
class _NutrientPicker extends StatefulWidget {
  @override
  State<_NutrientPicker> createState() => _NutrientPickerState();
}

class _NutrientPickerState extends State<_NutrientPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final n in nutrients)
        if (n.key != 'energy' && n.name.toLowerCase().contains(_q.toLowerCase())) n,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(hintText: tr('Search for a nutrient', 'Zoek een voedingsstof'), prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [for (final n in list) ListTile(title: Text(n.name), subtitle: Text(n.group.label), onTap: () => Navigator.pop(context, n))],
            ),
          ),
        ],
      ),
    );
  }
}
