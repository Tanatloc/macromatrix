import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/health.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/report.dart';
import '../../state/app_state.dart';
import '../../sync/friends.dart';
import '../theme.dart';
import 'profile_screen.dart';
import '../widgets/avatar.dart';
import '../widgets/health_view.dart';
import '../widgets/kit.dart';
import '../widgets/share_actions.dart';

/// Weekrapport: je gemiddelde Voedingsscore tegenover vorige week, een gezondheidsoordeel, beste en zwakste stoffen,
/// battles en een tip.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key, required this.monday});
  final DateTime monday;

  static String _range(DateTime m) {
    final f = DateFormat('d MMM', appLocale);
    return '${f.format(m)} – ${f.format(DateTime(m.year, m.month, m.day + 6))}';
  }

  /// Over welke dagen de gemiddelden gaan, bv. "average of 5 fully logged days".
  static String period(WeeklyReport r) => tr(
    'average of ${r.days} fully logged ${r.days == 1 ? 'day' : 'days'}',
    'gemiddelde van ${r.days} volledig gelogde ${r.days == 1 ? 'dag' : 'dagen'}',
  );

  /// Gemiddelde energie tegenover je doel, bv. "Energy: 1650 of 2400 kcal a day (750 kcal deficit; average of 5
  /// fully logged days)".
  static String? energyLine(WeeklyReport r) {
    final avg = r.kcalAvg, goal = r.kcalGoal, balance = r.energyBalance;
    if (avg == null || goal == null || balance == null) return null;
    final gap = fmtGrouped(balance.abs(), 0);
    final kind = balance.abs() < 50
        ? tr('on target', 'op doel')
        : (balance < 0 ? tr('$gap kcal deficit', '$gap kcal tekort') : tr('$gap kcal surplus', '$gap kcal overschot'));
    final change = r.kcalChange;
    final vs = change == null ? '' : ' · ${change >= 0 ? '+' : ''}$change kcal ${tr('vs last week', 't.o.v. vorige week')}';
    return tr(
      'Energy: ${fmtGrouped(avg, 0)} of ${fmtGrouped(goal, 0)} kcal a day ($kind; ${period(r)})$vs',
      'Energie: ${fmtGrouped(avg, 0)} van ${fmtGrouped(goal, 0)} kcal per dag ($kind; ${period(r)})$vs',
    );
  }

  /// Gewicht over de week, bv. "Weight: 81.2 kg at your last weigh-in (−0.6 kg this week)", of null zonder weging.
  /// Met de trend over twee weken als je gewicht stabiel is.
  static String? weightLine(WeeklyReport r) {
    final end = r.weightEnd;
    if (end == null) return null;
    final c = r.weightChange;
    final change = c == null ? '' : ' (${c > 0 ? '+' : (c < 0 ? '−' : '±')}${fmtGrouped(c.abs())} kg ${tr('this week', 'deze week')})';
    final t = r.weightTrend;
    final stable = t != null && t.stable ? tr(' · stable over ${t.days} days', ' · stabiel over ${t.days} dagen') : '';
    return tr('Weight: ${fmtGrouped(end)} kg at your last weigh-in$change$stable', 'Gewicht: ${fmtGrouped(end)} kg bij je laatste weging$change$stable');
  }

  /// Beweging, bv. "Exercise: 3 sessions, 140 min logged, 950 kcal", of null zonder activiteiten.
  static String? exerciseLine(WeeklyReport r) {
    final e = r.exercise;
    if (e.sessions == 0) return null;
    final min = e.minutes > 0 ? ', ${fmtGrouped(e.minutes, 0)} min ${tr('logged', 'gelogd')}' : '';
    return tr(
      'Exercise: ${e.sessions} ${e.sessions == 1 ? 'session' : 'sessions'}$min, ${fmtGrouped(e.kcal, 0)} kcal',
      'Beweging: ${e.sessions} ${e.sessions == 1 ? 'activiteit' : 'activiteiten'}$min, ${fmtGrouped(e.kcal, 0)} kcal',
    );
  }

  /// Verschil tegenover vorige week in procent van je doel, bv. "▲ 12%", of null. Begrensd op 999, want een
  /// week met een enkele uitschieter gaf "▲ 95248".
  static String? delta(WeeklyReport r, String key) {
    final d = r.changeFor(key);
    if (d == null) return null;
    final pts = (d * 100).round();
    if (pts == 0) return '=';
    return '${pts > 0 ? '▲' : '▼'} ${pts.abs() > 999 ? '>999' : pts.abs()}%';
  }

  /// Je gemiddelde dagdoel voor een stof, bv. "goal 300 mg", of null.
  static String? goalText(WeeklyReport r, Nutrient n) {
    final g = r.goals[n.key];
    if (g == null || g <= 0) return null;
    final shown = fmtGrouped(g, g < 10 ? 1 : 0);
    return tr('goal $shown ${n.unit}', 'doel $shown ${n.unit}');
  }

  /// Koolhydraten, suiker en bloedsuiker, bij "Let op suiker".
  static List<String> sugarLines(SugarWeek w) {
    final perDay = tr('a day', 'per dag');
    final carbGoal = w.carbsGoal;
    return [
      carbGoal == null
          ? tr('Carbohydrates: ${fmtGrouped(w.carbs, 0)} g $perDay', 'Koolhydraten: ${fmtGrouped(w.carbs, 0)} g $perDay')
          : tr(
              'Carbohydrates: ${fmtGrouped(w.carbs, 0)} g $perDay (goal ${fmtGrouped(carbGoal, 0)} g) · ${w.carbDaysOver} of ${w.days} days above',
              'Koolhydraten: ${fmtGrouped(w.carbs, 0)} g $perDay (doel ${fmtGrouped(carbGoal, 0)} g) · ${w.carbDaysOver} van ${w.days} dagen erboven',
            ),
      tr('Sugars: ${fmtGrouped(w.sugars, 0)} g $perDay', 'Suikers: ${fmtGrouped(w.sugars, 0)} g $perDay'),
      if (w.freeSugars case final f?)
        w.freeSugarsMax == null
            ? tr('Free sugar: ${fmtGrouped(f, 0)} g $perDay', 'Vrije suiker: ${fmtGrouped(f, 0)} g $perDay')
            : tr(
                'Free sugar: ${fmtGrouped(f, 0)} g $perDay (max ${fmtGrouped(w.freeSugarsMax!, 0)} g) · ${w.freeSugarDaysOver} of ${w.days} days above',
                'Vrije suiker: ${fmtGrouped(f, 0)} g $perDay (max ${fmtGrouped(w.freeSugarsMax!, 0)} g) · ${w.freeSugarDaysOver} van ${w.days} dagen erboven',
              ),
      w.glucose == null
          ? tr('Blood glucose: no readings this week', 'Bloedsuiker: geen metingen deze week')
          : tr(
              'Blood glucose: ${fmtGrouped(w.glucose!)} mmol/L on average (${w.glucoseCount} ${w.glucoseCount == 1 ? 'reading' : 'readings'} this week)',
              'Bloedsuiker: gemiddeld ${fmtGrouped(w.glucose!)} mmol/L (${w.glucoseCount} ${w.glucoseCount == 1 ? 'meting' : 'metingen'} deze week)',
            ),
    ];
  }

  /// Tekst om te delen of te kopiëren.
  static String shareText(WeeklyReport r, int streak) {
    final change = r.change;
    final day = DateFormat('EEE d MMM', appLocale);
    String nutrients(List<(Nutrient, double)> xs) => xs
        .map((b) {
          final d = delta(r, b.$1.key);
          return '${b.$1.name} ${fmtPct(b.$2)}${d == null ? '' : ' ($d)'}';
        })
        .join(', ');
    return [
      tr('My MacroMatrix week (${_range(r.monday)})', 'Mijn MacroMatrix-week (${_range(r.monday)})'),
      tr(
        'Nutrient score: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change vs last week)'}, ${period(r)}',
        'Voedingsscore: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change t.o.v. vorige week)'}, ${period(r)}',
      ),
      tr('Full days logged: ${r.days}/7 · streak: $streak', 'Volledig gelogde dagen: ${r.days}/7 · reeks: $streak'),
      if (r.health != null) tr('Health: ${r.health!.rating.label}', 'Gezondheid: ${r.health!.rating.label}'),
      if (r.sugar != null) ...sugarLines(r.sugar!),
      ?energyLine(r),
      ?weightLine(r),
      ?exerciseLine(r),
      if (r.best.isNotEmpty) tr('Best: ${nutrients(r.best)}', 'Best: ${nutrients(r.best)}'),
      tr('Needs attention: ${nutrients(r.worst)}', 'Verdient aandacht: ${nutrients(r.worst)}'),
      if (r.notes.isNotEmpty) ...[
        tr('Notes:', 'Notities:'),
        for (final n in r.notes.entries) '- ${day.format(DateTime.parse(n.key))}: ${n.value.replaceAll('\n', ' ')}',
      ],
      'app.divinenet.online',
    ].join('\n');
  }

  /// Tip bij een duidelijk energieprobleem: dat gaat voor op een vitamine of mineraal. Dezelfde uitleg als bij
  /// energie in het gezondheidsdeel, samen gelezen met je gewicht: nooit blind "eet 900 kcal meer".
  static String? energyTip(WeeklyReport r) {
    final avg = r.kcalAvg, goal = r.kcalGoal;
    if (r.energyOff == 0 || avg == null || goal == null) return null;
    final c = r.energyCase;
    if (c == EnergyCase.onTarget) return null;
    final m = energyMessage(c, eaten: avg, goal: goal, trend: r.weightTrend, plan: r.plan);
    return '${m.effect} ${m.advice}';
  }

  /// Bij de tip een knop naar je energiedoel: als je gewicht zegt dat het doel niet klopt.
  static bool suggestGoalChange(WeeklyReport r) => energyTip(r) != null && r.energyCase == EnergyCase.goalOff;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = context.watch<Friends>();
    final p = context.pal;
    final r = s.weeklyReport(monday);
    final battles = f.battles.where((b) => b.finished && b.week == monday).toList();
    final level = s.level;

    Widget nutrientRow((Nutrient, double) x, Color color) {
      final (n, frac) = x;
      final d = r == null ? null : delta(r, n.key);
      final g = r == null ? null : goalText(r, n);
      // Doel en verschil met vorige week onder de naam, zodat de naam de volle breedte houdt (geen "Magnesiu m")
      final sub = [?g, if (d != null) '$d ${tr('vs last week', 't.o.v. vorige week')}'].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.name, style: TextStyle(fontSize: 14, color: p.ink)),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11.5, color: p.ink3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), minHeight: 8, backgroundColor: p.track, color: color),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                frac > 2 ? '200%+' : fmtPct(frac),
                textAlign: TextAlign.right,
                style: numStyle(13, color: p.ink2),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Weekly report', 'Weekrapport')),
        actions: [
          if (r != null)
            IconButton(
              tooltip: tr('Share', 'Delen'),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => shareWeek(context, r, copyText: shareText(r, s.streak.current)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: r == null
                  ? Panel(
                      child: Text(
                        tr(
                          'No fully logged days in this week yet. A day counts once you log at least half your energy goal, and today counts from tomorrow.',
                          'Nog geen volledig gelogde dagen in deze week. Een dag telt vanaf de helft van je energiedoel, en vandaag telt vanaf morgen.',
                        ),
                        style: TextStyle(color: p.ink2),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_range(monday), style: TextStyle(fontSize: 13, color: p.ink3)),
                        const SizedBox(height: 10),
                        // "Let op suiker": koolhydraten, suiker en bloedsuiker eerst
                        if (r.sugar case final sugar?) ...[
                          Panel(
                            shadow: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PanelTitle(tr('Carbs and sugar', 'Koolhydraten en suiker'), subtitle: period(r)),
                                const SizedBox(height: 6),
                                for (final line in sugarLines(sugar))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(line, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // Score
                        Panel(
                          child: Row(
                            children: [
                              LevelAvatar(avatar: s.avatar, level: level.level, size: 56),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr('Nutrient score', 'Voedingsscore'), style: TextStyle(fontSize: 13, color: p.ink2)),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text('${r.score}', style: numStyle(40, color: p.ink)),
                                        const SizedBox(width: 10),
                                        if (r.change != null)
                                          Text(
                                            '${r.change! > 0 ? '▲' : (r.change! < 0 ? '▼' : '=')} ${r.change!.abs()} ${tr('vs last week', 't.o.v. vorige week')}',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.change! >= 0 ? p.ok : p.low),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      tr(
                                        'Average of ${r.days} fully logged ${r.days == 1 ? 'day' : 'days'} (of 7) · ${s.streak.current}-day streak',
                                        'Gemiddelde van ${r.days} volledig gelogde ${r.days == 1 ? 'dag' : 'dagen'} (van 7) · reeks van ${s.streak.current}',
                                      ),
                                      style: TextStyle(fontSize: 12.5, color: p.ink3),
                                    ),
                                    if (r.partialDays > 0)
                                      Text(
                                        tr(
                                          '${r.partialDays} ${r.partialDays == 1 ? 'day' : 'days'} not counted: logged too little, or still in progress',
                                          '${r.partialDays} ${r.partialDays == 1 ? 'dag telt' : 'dagen tellen'} niet mee: te weinig gelogd, of nog bezig',
                                        ),
                                        style: TextStyle(fontSize: 12, color: p.ink3),
                                      ),
                                    // Energiebalans, gewicht en beweging van de week
                                    for (final line in [?energyLine(r), ?weightLine(r), ?exerciseLine(r)])
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(line, style: TextStyle(fontSize: 12.5, color: p.ink2)),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        HealthPanel(check: r.health, change: r.healthChange, hasLabs: s.labResults.isNotEmpty),
                        const SizedBox(height: 10),
                        Panel(
                          shadow: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PanelTitle(tr('Your strongest', 'Je sterkste')),
                              for (final b in r.best) nutrientRow(b, p.okFill),
                              if (r.best.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Text(
                                    tr(
                                      'No vitamin or mineral reached its goal on most days yet.',
                                      'Nog geen vitamine of mineraal die je op de meeste dagen haalde.',
                                    ),
                                    style: TextStyle(fontSize: 13, color: p.ink2),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              PanelTitle(tr('Needs attention', 'Verdient aandacht')),
                              for (final w in r.worst) nutrientRow(w, p.lowFill),
                              const SizedBox(height: 6),
                              Text(
                                tr(
                                  'Average share of your daily goal, ${period(r)}. ▲▼ = change vs last week, in % of your goal. Amounts above the safe upper limit, or reached on fewer than half of the days, are not shown as strongest.',
                                  'Gemiddeld deel van je dagdoel, ${period(r)}. ▲▼ = verschil met vorige week, in % van je doel. Wat boven de veilige bovengrens zit, of op minder dan de helft van de dagen op doel was, staat niet bij je sterkste.',
                                ),
                                style: TextStyle(fontSize: 11.5, color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        if (r.tip != null || energyTip(r) != null) ...[
                          const SizedBox(height: 10),
                          Panel(
                            shadow: false,
                            color: p.brandSoft,
                            borderColor: p.brandSoft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lightbulb_rounded, color: p.brand),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tr('Tip for this week', 'Tip voor deze week'),
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        energyTip(r) ??
                                            tr(
                                              'Boost your ${inSentence(r.tip!.nutrient.name)}: ${r.tip!.amountLabel} of ${r.tip!.food.name} gives ${fmtPct(r.tip!.fraction)} of your daily goal.',
                                              'Meer ${inSentence(r.tip!.nutrient.name)}: ${r.tip!.amountLabel} ${r.tip!.food.name} geeft ${fmtPct(r.tip!.fraction)} van je dagdoel.',
                                            ),
                                        style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
                                      ),
                                      // Je gewicht zegt dat het doel niet klopt: meteen naar je energiedoel
                                      if (suggestGoalChange(r))
                                        TextButton.icon(
                                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                          icon: const Icon(Icons.tune_rounded, size: 18),
                                          label: Text(tr('Adjust your energy goal', 'Je energiedoel aanpassen')),
                                          onPressed: () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => Scaffold(
                                                appBar: AppBar(title: Text(tr('Your goals', 'Je doelen'))),
                                                body: const ProfileScreen(),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (battles.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Panel(
                            shadow: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const PanelTitle('Battles'),
                                for (final b in battles)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          b.result == BattleResult.won ? Icons.emoji_events_rounded : Icons.flag_outlined,
                                          size: 20,
                                          color: b.result == BattleResult.won ? p.ok : p.ink3,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(switch (b.result) {
                                            BattleResult.won => tr('You beat ${b.otherName}', 'Je won van ${b.otherName}'),
                                            BattleResult.lost => tr('${b.otherName} won', '${b.otherName} won'),
                                            BattleResult.draw => tr('Draw with ${b.otherName}', 'Gelijkspel met ${b.otherName}'),
                                          }, style: TextStyle(fontSize: 13.5, color: p.ink)),
                                        ),
                                        Text('${b.myPoints} – ${b.otherPoints}', style: numStyle(13.5, color: p.ink2)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Center(
                          child: FilledButton.tonalIcon(
                            key: const Key('week-share'),
                            onPressed: () => shareWeek(context, r, copyText: shareText(r, s.streak.current)),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: Text(tr('Share as image', 'Delen als afbeelding')),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kaart op Vandaag (maandag tot woensdag): het rapport van vorige week staat klaar.
class WeeklyReportCard extends StatelessWidget {
  const WeeklyReportCard({super.key});

  static DateTime lastMonday() {
    final m = mondayOf(logicalNow());
    return DateTime(m.year, m.month, m.day - 7);
  }

  /// Tonen op maandag tot woensdag, als je vorige week iets logde en het rapport nog niet opende.
  static bool shouldShow(AppState s) {
    if (DateTime.now().weekday > 3) return false;
    final key = dayKey(lastMonday());
    if (s.user.setting('_report_seen')?['week'] == key) return false;
    return s.weeklyReport(lastMonday()) != null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final r = s.weeklyReport(lastMonday());
    if (r == null) return const SizedBox.shrink();
    void open() {
      s.markReportSeen(dayKey(lastMonday()));
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyReportScreen(monday: lastMonday())));
    }

    return Panel(
      shadow: false,
      radius: 16,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: open,
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Your weekly report is ready', 'Je weekrapport staat klaar'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  tr(
                        'Nutrient score ${r.score}${r.change == null ? '' : ' (${r.change! >= 0 ? '+' : ''}${r.change})'} · ${r.days} full days logged',
                        'Voedingsscore ${r.score}${r.change == null ? '' : ' (${r.change! >= 0 ? '+' : ''}${r.change})'} · ${r.days} volledige dagen gelogd',
                      ) +
                      (r.health == null ? '' : ' · ${tr('health', 'gezondheid')}: ${r.health!.rating.label.toLowerCase()}'),
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Dismiss', 'Verbergen'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => s.markReportSeen(dayKey(lastMonday())),
          ),
        ],
      ),
    );
  }
}
