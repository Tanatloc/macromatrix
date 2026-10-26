
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/processing_card.dart';
import '../widgets/bio_tips_view.dart';
import '../widgets/info_tip.dart';
import '../widgets/kit.dart';
import '../widgets/nutrient_row.dart';
import '../widgets/share_actions.dart';
import 'nutrient_detail_screen.dart';
import '../../i18n.dart';

enum _Filter {
  key('Important', 'Belangrijk', null),
  all('All', 'Alles', null),
  macro('Macro', 'Macro', [NutrientGroup.general, NutrientGroup.carbs]),
  vitamins('Vitamins', 'Vitaminen', [NutrientGroup.vitamins]),
  minerals('Minerals', 'Mineralen', [NutrientGroup.minerals]),
  fats('Fatty acids', 'Vetzuren', [NutrientGroup.fats]),
  amino('Amino acids', 'Aminozuren', [NutrientGroup.protein]),
  other('Other', 'Overige', [NutrientGroup.other]);

  const _Filter(this.en, this.nl, this.groups);
  final String en, nl;
  String get label => tr(en, nl);
  final List<NutrientGroup>? groups;
}

/// Alle voedingsstoffen van de gekozen dag, met een Voedingsscore, verhoudingen en een bereikbalk per stof
/// (de dagweergave van het dashboard).
class DayNutrients extends StatefulWidget {
  const DayNutrients({super.key});

  @override
  State<DayNutrients> createState() => _DayNutrientsState();
}

class _DayNutrientsState extends State<DayNutrients> {
  _Filter _filter = _Filter.key;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    // Op een pc: alles breder, de score en de balans naast elkaar, en de voedingsstoffen in twee kolommen
    return LayoutBuilder(builder: (context, c) => _build(context, s, p, c.maxWidth >= twoColumnWidth));
  }

  Widget _build(BuildContext context, AppState s, Palette p, bool wide) {
    final mw = wide ? wideMaxWidth : 760.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Narrow(
          maxWidth: mw,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: s.entries.isEmpty
                ? Panel(
                    child: Text(
                      tr(
                        'Nothing eaten on this day yet. Add something under Today to see all your nutrients here.',
                        'Nog niets gegeten op deze dag. Voeg iets toe bij Vandaag om hier al je voedingsstoffen te zien.',
                      ),
                      style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                    ),
                  )
                : wide
                // Score en bewerking naast elkaar (ongeveer even hoog), de inklapbare balans eronder over de hele
                // breedte: anders bleef er naast de score een groot gat onder de dichtgeklapte balans (P48)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(child: ScoreCard()),
                            const SizedBox(width: 12),
                            Expanded(child: ProcessingCard(share: s.processingOf(s.entries))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _MoreInsights(values: s.totals.values, tips: s.bioTipsToday.length),
                    ],
                  )
                // Gsm: eerst de score, meteen daarna wat je nog mist; balans en bewerking ingeklapt onderaan
                : const ScoreCard(),
          ),
        ),
        if (s.entries.isNotEmpty) ...[
          Narrow(
            maxWidth: mw,
            child: SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PillChip(label: f.label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                    ),
                ],
              ),
            ),
          ),
          Narrow(
            maxWidth: mw,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_filter == _Filter.key)
                    KeyNutrients(
                      isToday: s.isToday,
                      values: s.totals.values,
                      targets: s.targets,
                      incomplete: s.totals.incomplete,
                      hidden: s.hiddenNutrients,
                      columns: wide ? 2 : 1,
                      plain: true,
                      onShowAll: () => setState(() => _filter = _Filter.all),
                    )
                  else
                    NutrientPanel(
                      values: s.totals.values,
                      targets: s.targets,
                      incomplete: s.totals.incomplete,
                      groups: _filter.groups,
                      hidden: s.hiddenNutrients,
                      collapseAmino: _filter != _Filter.amino,
                      columns: wide ? 2 : 1,
                      plain: true,
                      onTapNutrient: (n) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: n))),
                    ),
                  // Balans en bewerking: extra inzicht, dicht onder de lijsten (op een pc staan ze bovenaan)
                  if (!wide) ...[
                    const SizedBox(height: 6),
                    _MoreInsights(values: s.totals.values, tips: s.bioTipsToday.length),
                    const SizedBox(height: 10),
                    ProcessingFold(share: s.processingOf(s.entries)),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('dashboard-howto'),
                      icon: const Icon(Icons.help_outline_rounded, size: 18),
                      label: Text(tr('How do I read this?', 'Hoe lees ik dit?')),
                      onPressed: () => _howToRead(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Uitleg bij het dashboard (vroeger een lange tekst onderaan).
void _howToRead(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(tr('How do I read this?', 'Hoe lees ik dit?')),
    content: Text(
      tr(
        'A full bar means you reached your goal. Next to it you see what that means: how much is still to go, on target, '
            'or how much is too much. For salt, saturated fat and free sugars the bar runs to your maximum: staying under it is good.\n\n'
            'Tap a nutrient for your history, the best sources and your own goal.\n\n'
            'The i icon means more than 10% of that day\'s calories come from products without data for that nutrient: '
            'the real total is then probably higher.\n\n'
            'Reference values: EFSA (healthy adults), amino acids: WHO. Not medical advice.',
        'Een volle balk betekent: doel gehaald. Ernaast staat wat dat betekent: hoeveel je nog nodig hebt, op doel, of hoeveel te veel. '
            'Bij zout, verzadigd vet en vrije suikers loopt de balk tot je maximum: daaronder blijven is goed.\n\n'
            'Tik op een voedingsstof voor je verloop, de beste bronnen en je eigen doel.\n\n'
            'Het i-icoontje betekent dat meer dan 10% van je calorieën van die dag uit producten komt zonder gegevens voor die stof: '
            'het echte totaal ligt dan waarschijnlijk hoger.\n\n'
            'Richtwaarden: EFSA (gezonde volwassenen), aminozuren: WHO. Geen medisch advies.',
      ),
      style: TextStyle(fontSize: 14, height: 1.5, color: c.pal.ink2),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('OK', 'OK')))],
  ),
);

/// Wat er echt toe doet: energie, macro's, vezels, verzadigd vet, zout, en de vitaminen en mineralen waarvan je
/// vandaag het minst hebt (hooguit 10, alleen wat onder je doel zit).
class KeyNutrients extends StatelessWidget {
  const KeyNutrients({
    super.key,
    required this.values,
    required this.targets,
    this.incomplete = const {},
    this.hidden = const {},
    this.onShowAll,
    this.columns = 1,
    this.isToday = true,
    this.sugarFocus,
    this.plain = false,
  });

  /// Dashboard: eenvoudige regels (zie [NutrientRow.plain]) en eerst wat je nog tekortkomt, dan de basis.
  final bool plain;

  final NutrientMap values;
  final Map<String, Target> targets;
  final Set<String> incomplete;
  final Set<String> hidden;
  final VoidCallback? onShowAll;

  /// Twee kolommen (pc): de basis en de tekorten naast elkaar.
  final int columns;
  final bool isToday;

  /// "Let op suiker" (P41); null = de instelling uit AppState.
  final bool? sugarFocus;

  static const basics = ['energy', 'protein', 'carbs', 'sugars', 'free_sugars', 'fiber', 'fat', 'sfa', 'sodium'];

  /// Met "Let op suiker": koolhydraten en suikers bovenaan, meteen onder energie.
  static const sugarBasics = ['energy', 'carbs', 'sugars', 'free_sugars', 'fiber', 'protein', 'fat', 'sfa', 'sodium'];

  /// De vitaminen en mineralen onder je doel, de grootste tekorten eerst.
  static List<String> shortfalls(NutrientMap values, Map<String, Target> targets, {int limit = 10}) {
    final low = [
      for (final k in stripKeys)
        if (!basics.contains(k))
          if (targets[k]?.goal case final g? when g > 0 && (values[k] ?? 0) < g) (k, (values[k] ?? 0) / g),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (k, _) in low.take(limit)) k];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final low = shortfalls(values, targets);
    void open(Nutrient n) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: n)));
    Widget row(int i, String k) => NutrientRow(
      first: i == 0,
      nutrient: nutrientByKey[k]!,
      amount: values[k],
      target: targets[k],
      complete: !incomplete.contains(k),
      plain: plain,
      onTap: () => open(nutrientByKey[k]!),
    );
    final sugar = sugarFocus ?? Provider.of<AppState?>(context)?.sugarFocus ?? false;
    final basics = [
      for (final k in sugar ? KeyNutrients.sugarBasics : KeyNutrients.basics)
        if (!hidden.contains(k)) k,
    ];
    final basicsPanel = Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('The basics', 'De basis'),
            subtitle: sugar ? tr('Carbs and sugar first: you keep an eye on sugar', 'Koolhydraten en suiker eerst: je let op suiker') : null,
          ),
          const SizedBox(height: 4),
          for (final (i, k) in basics.indexed) row(i, k),
        ],
      ),
    );
    final lowPanel = Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            isToday ? tr('Still short today', 'Vandaag nog te weinig') : tr('Still short this day', 'Deze dag nog te weinig'),
            subtitle: low.isEmpty ? null : tr('Vitamins and minerals under your goal', 'Vitaminen en mineralen onder je doel'),
          ),
          const SizedBox(height: 4),
          if (low.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('You reach all your vitamins and minerals today.', 'Je haalt vandaag al je vitaminen en mineralen.'),
                      style: TextStyle(fontSize: 13.5, color: p.ink2),
                    ),
                  ),
                  // Doel gehaald: als deelkaart (alleen vandaag, en als er echt iets gelogd is)
                  if (isToday && (values['energy'] ?? 0) > 0 && Provider.of<AppState?>(context, listen: false) != null)
                    TextButton.icon(
                      key: const Key('micros-share'),
                      onPressed: () => shareAllMicros(context, values: values, targets: targets),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text(tr('Share', 'Delen')),
                    ),
                ],
              ),
            )
          else
            for (final (i, k) in low.indexed) row(i, k),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (columns > 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: basicsPanel),
              const SizedBox(width: 12),
              Expanded(child: lowPanel),
            ],
          )
        else if (plain) ...[
          lowPanel,
          const SizedBox(height: 10),
          basicsPanel,
        ] else ...[
          basicsPanel,
          const SizedBox(height: 10),
          lowPanel,
        ],
        if (onShowAll != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.list_rounded, size: 18),
              label: Text(tr('Show all nutrients', 'Alle voedingsstoffen tonen')),
              onPressed: onShowAll,
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Voedingsscore met de verdeling op doel / tekort / te veel. [bare]: zonder kaart eromheen.
class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key, this.bare = false});
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final v = s.totals.values;
    final empty = (v['energy'] ?? 0) <= 0;
    final score = dayScore(v, s.targets, closed: s.dateClosed);
    // Dezelfde regel als de balken en percentages (levelOf / isTooMuch), maar alleen over de vitaminen en mineralen:
    // dat staat erbij, zodat rood vet of verzadigd vet niet tegen "0 te veel" lijkt in te gaan (NW-15)
    final levels = [
      for (final k in stripKeys)
        if (s.targets[k] != null) levelOf(v[k] ?? 0, s.targets[k]),
    ];
    int count(Level l) => levels.where((x) => x == l).length;
    final coverage = dataCoverage(s.totals);
    final reason = empty ? null : scoreEnergyNote(v, s.targets, closed: s.dateClosed);

    final info = InfoTip(
      title: tr('Nutrient score', 'Voedingsscore'),
      message: tr(
        'How close you are to your goal for ${stripKeys.length} vitamins and minerals, on average. '
            'Each nutrient counts up to 100%; above an upper limit the score drops. '
            'Once the day is over, energy counts too: more than ${fmtPct(energyScoreBand)} under or over your energy goal lowers the score.',
        'Hoe dicht je bij je doel zit voor ${stripKeys.length} vitaminen en mineralen, gemiddeld. '
            'Per stof telt maximaal 100%; boven een bovengrens of limiet daalt de score. '
            'Als de dag voorbij is, telt ook energie: meer dan ${fmtPct(energyScoreBand)} onder of boven je energiedoel verlaagt de score.',
      ),
    );
    // ui-nieuw: zoals de calorieënkaart van Vandaag: links het getal groot, rechts drie rustige tellers
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tr('NUTRIENT SCORE', 'VOEDINGSSCORE'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: p.ink3),
                        ),
                      ),
                      info,
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: empty ? '—' : '$score',
                          style: numStyle(44, weight: FontWeight.w800, color: p.ink),
                        ),
                        if (!empty)
                          TextSpan(
                            text: ' /100',
                            style: numStyle(14, weight: FontWeight.w500, color: p.ink3),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (l, label) in [
                    (Level.ok, tr('on target', 'op doel')),
                    (Level.low, tr('short', 'tekort')),
                    (Level.high, tr('too much', 'te veel')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusMark(l),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${count(l)}',
                              style: numStyle(14, weight: FontWeight.w700, color: p.ink),
                            ),
                          ),
                          Text(label, style: TextStyle(fontSize: 13, color: p.ink2)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Alleen iets zeggen over de gegevens als er echt iets ontbreekt; anders is het ruis
        if (empty || coverage < 0.9)
          Text(
            empty
                ? tr('Nothing logged yet', 'Nog niets gelogd')
                : tr(
                    'Data complete for ${fmtPct(coverage)} of your kcal: the score may be a bit low',
                    'Gegevens compleet voor ${fmtPct(coverage)} van je kcal: de score ligt misschien wat te laag',
                  ),
            style: TextStyle(fontSize: 12, color: empty ? p.ink3 : p.low),
          ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(reason.$1, style: TextStyle(fontSize: 12, color: reason.$2 ? p.low : p.ink3)),
          ),
      ],
    );
    return bare ? body : Panel(child: body);
  }
}

/// Twee verhoudingen in gewone taal: omega-6 tegenover omega-3, en kalium tegenover natrium. Een balk toont waar
/// je zit; het groene stuk is goed.
class _Ratios extends StatelessWidget {
  const _Ratios({required this.values});
  final Map<String, double> values;

  @override
  Widget build(BuildContext context) {
    double? ratio(String a, String b) {
      final x = values[a], y = values[b];
      return (x == null || y == null || y <= 0) ? null : x / y;
    }

    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            tr('Balance', 'Balans'),
            trailing: Text(tr('tap for details', 'tik voor uitleg'), style: TextStyle(fontSize: 11.5, color: context.pal.ink3)),
          ),
          _RatioRow(
            title: 'Omega-6 : 3',
            value: ratio('omega6', 'omega3'),
            max: 16,
            good: (0, 4),
            sentence: (r) => tr('You ate ${fmtDec(r)} times as much omega-6 as omega-3.', 'Je at ${fmtDec(r)} keer zoveel omega-6 als omega-3.'),
            goal: tr('Good is at most 4 times as much.', 'Goed is hoogstens 4 keer zoveel.'),
            tip: tr('More oily fish, flaxseed or walnuts helps.', 'Meer vette vis, lijnzaad of walnoten helpt.'),
            okLabel: tr('Balanced', 'In balans'),
            badLabel: tr('Too little omega-3', 'Te weinig omega-3'),
          ),
          _RatioRow(
            title: tr('Potassium : sodium', 'Kalium : natrium'),
            value: ratio('potassium', 'sodium'),
            max: 5,
            good: (2, double.infinity),
            sentence: (r) => tr('You ate ${fmtDec(r)} times as much potassium as sodium.', 'Je at ${fmtDec(r)} keer zoveel kalium als natrium.'),
            goal: tr('Good is at least 2 times as much.', 'Goed is minstens 2 keer zoveel.'),
            tip: tr(
              'Vegetables, fruit and legumes provide potassium; less salt helps too.',
              'Groenten, fruit en peulvruchten geven kalium; minder zout helpt ook.',
            ),
            okLabel: tr('Balanced', 'In balans'),
            badLabel: tr('Too much salt', 'Te veel zout'),
          ),
        ],
      ),
    );
  }
}

class _RatioRow extends StatefulWidget {
  const _RatioRow({
    required this.title,
    required this.value,
    required this.max,
    required this.good,
    required this.sentence,
    required this.goal,
    required this.tip,
    required this.okLabel,
    required this.badLabel,
  });

  final String title;
  final double? value;
  final double max;
  final (double, double) good;
  final String Function(double) sentence;
  final String goal, tip, okLabel, badLabel;

  @override
  State<_RatioRow> createState() => _RatioRowState();
}

/// Eén compacte regel: naam, balk, waarde en status. Tik voor de uitleg.
class _RatioRowState extends State<_RatioRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final w = widget;
    final v = w.value;
    final ok = v != null && v >= w.good.$1 && v <= w.good.$2;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    w.title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final width = c.maxWidth;
                      double x(double r) => (r.clamp(0, w.max) / w.max) * width;
                      return SizedBox(
                        height: 14,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 4,
                              height: 6,
                              child: Container(
                                decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                            Positioned(
                              left: x(w.good.$1),
                              width: x(w.good.$2) - x(w.good.$1),
                              top: 4,
                              height: 6,
                              child: Container(
                                decoration: BoxDecoration(color: p.okFill, borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                            if (v != null)
                              Positioned(
                                left: (x(v) - 2.5).clamp(0, width - 5),
                                top: 0,
                                width: 5,
                                height: 14,
                                // Naald in de statuskleur: buiten de goede zone mag hij niet "groen" ogen
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: ok ? p.ok : p.low,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: p.surface, width: 1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    v == null ? '–' : '${fmtDec(v)}:1',
                    textAlign: TextAlign.right,
                    style: numStyle(13, color: v == null || ok ? p.ink : p.low),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  v == null ? Icons.remove_rounded : (ok ? Icons.check_circle_rounded : Icons.error_outline_rounded),
                  size: 18,
                  color: v == null ? p.ink3 : (ok ? p.ok : p.low),
                ),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  v == null
                      ? tr('No data yet.', 'Nog geen gegevens.')
                      : '${ok ? w.okLabel : w.badLabel}. ${w.sentence(v)} ${w.goal}${ok ? '' : ' ${w.tip}'}',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Balans en opname samen, standaard dichtgeklapt, zodat de Voedingsscore en de lijst meer ruimte krijgen.
class _MoreInsights extends StatefulWidget {
  const _MoreInsights({required this.values, required this.tips});
  final Map<String, double> values;
  final int tips;

  @override
  State<_MoreInsights> createState() => _MoreInsightsState();
}

class _MoreInsightsState extends State<_MoreInsights> {
  // Onthouden zolang de app openstaat
  static bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          shadow: false,
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              Icon(Icons.balance_rounded, color: p.brand, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Balance and absorption', 'Balans en opname'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                    ),
                    Text(
                      widget.tips == 0
                          ? tr('Omega-6 : 3 and potassium : sodium', 'Omega-6 : 3 en kalium : natrium')
                          : tr(
                              '2 balances · ${widget.tips} ${widget.tips == 1 ? 'tip' : 'tips'}',
                              '2 verhoudingen · ${widget.tips} ${widget.tips == 1 ? 'tip' : 'tips'}',
                            ),
                      style: TextStyle(fontSize: 12.5, color: p.ink2),
                    ),
                  ],
                ),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink3),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    _Ratios(values: widget.values),
                    const SizedBox(height: 10),
                    const BioTipsCard(),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

