import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/report.dart';
import '../../state/app_state.dart';
import '../../sync/friends.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/health_view.dart';
import '../widgets/kit.dart';

/// Weekrapport: je gemiddelde Voedingsscore tegenover vorige week, een gezondheidsoordeel, beste en zwakste stoffen,
/// battles en een tip.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key, required this.monday});
  final DateTime monday;

  static String _range(DateTime m) {
    final f = DateFormat('d MMM', appLocale);
    return '${f.format(m)} – ${f.format(DateTime(m.year, m.month, m.day + 6))}';
  }

  /// Gemiddelde energie tegenover je doel, bv. "Energy: 1650 of 2400 kcal a day (750 kcal deficit)".
  static String? energyLine(WeeklyReport r) {
    final avg = r.kcalAvg, goal = r.kcalGoal, balance = r.energyBalance;
    if (avg == null || goal == null || balance == null) return null;
    final gap = fmtNum(balance.abs(), 0);
    final kind = balance.abs() < 50
        ? tr('on target', 'op doel')
        : (balance < 0 ? tr('$gap kcal deficit', '$gap kcal tekort') : tr('$gap kcal surplus', '$gap kcal overschot'));
    final change = r.kcalChange;
    final vs = change == null ? '' : ' · ${change >= 0 ? '+' : ''}$change kcal ${tr('vs last week', 't.o.v. vorige week')}';
    return tr(
      'Energy: ${fmtNum(avg, 0)} of ${fmtNum(goal, 0)} kcal a day ($kind)$vs',
      'Energie: ${fmtNum(avg, 0)} van ${fmtNum(goal, 0)} kcal per dag ($kind)$vs',
    );
  }

  /// Gewicht over de week, bv. "Weight: 81.2 kg (−0.6 kg this week)", of null zonder weging.
  static String? weightLine(WeeklyReport r) {
    final end = r.weightEnd;
    if (end == null) return null;
    final c = r.weightChange;
    final change = c == null ? '' : ' (${c > 0 ? '+' : (c < 0 ? '−' : '±')}${fmtNum(c.abs())} kg ${tr('this week', 'deze week')})';
    return tr('Weight: ${fmtNum(end)} kg$change', 'Gewicht: ${fmtNum(end)} kg$change');
  }

  /// Beweging, bv. "Exercise: 3 sessions, 140 min, 950 kcal", of null zonder activiteiten.
  static String? exerciseLine(WeeklyReport r) {
    final e = r.exercise;
    if (e.sessions == 0) return null;
    final min = e.minutes > 0 ? ', ${fmtNum(e.minutes, 0)} min' : '';
    return tr(
      'Exercise: ${e.sessions} ${e.sessions == 1 ? 'session' : 'sessions'}$min, ${fmtNum(e.kcal, 0)} kcal',
      'Beweging: ${e.sessions} ${e.sessions == 1 ? 'activiteit' : 'activiteiten'}$min, ${fmtNum(e.kcal, 0)} kcal',
    );
  }

  /// Verschil tegenover vorige week in procentpunt, bv. "▲ 12", of null.
  static String? delta(WeeklyReport r, String key) {
    final d = r.changeFor(key);
    if (d == null) return null;
    final pts = (d * 100).round();
    return pts == 0 ? '=' : '${pts > 0 ? '▲' : '▼'} ${pts.abs()}';
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
        'Nutrient score: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change vs last week)'}',
        'Nutrient score: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change t.o.v. vorige week)'}',
      ),
      tr('Full days logged: ${r.days}/7 · streak: $streak', 'Volledig gelogde dagen: ${r.days}/7 · reeks: $streak'),
      if (r.health != null)
        tr('Health: ${r.health!.rating.label} (${r.health!.score}/100)', 'Gezondheid: ${r.health!.rating.label} (${r.health!.score}/100)'),
      ?energyLine(r),
      ?weightLine(r),
      ?exerciseLine(r),
      tr('Best: ${nutrients(r.best)}', 'Best: ${nutrients(r.best)}'),
      tr('Needs attention: ${nutrients(r.worst)}', 'Verdient aandacht: ${nutrients(r.worst)}'),
      if (r.notes.isNotEmpty) ...[
        tr('Notes:', 'Notities:'),
        for (final n in r.notes.entries) '- ${day.format(DateTime.parse(n.key))}: ${n.value.replaceAll('\n', ' ')}',
      ],
      'app.divinenet.online',
    ].join('\n');
  }

  /// Tip bij een duidelijk energieprobleem: dat gaat voor op een vitamine of mineraal.
  static String? energyTip(WeeklyReport r) {
    final balance = r.energyBalance;
    if (r.energyOff == 0 || balance == null) return null;
    final gap = fmtNum(balance.abs(), 0);
    return r.energyOff < 0
        ? tr(
            'You ate about $gap kcal a day less than your goal. Eating too little for a long time costs muscle and energy and makes it hard to reach your other nutrients: add a snack or a bigger portion at a main meal.',
            'Je at ongeveer $gap kcal per dag minder dan je doel. Lang te weinig eten kost spiermassa en energie en maakt je andere voedingsstoffen moeilijk haalbaar: voeg een tussendoortje toe of neem een grotere portie bij een hoofdmaaltijd.',
          )
        : tr(
            'You ate about $gap kcal a day more than your goal. Smaller portions or fewer snacks and sugary drinks bring you closer.',
            'Je at ongeveer $gap kcal per dag meer dan je doel. Kleinere porties of minder tussendoortjes en suikerdranken brengen je dichterbij.',
          );
  }

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(n.name, style: TextStyle(fontSize: 14, color: p.ink)),
            ),
            // Tegenover vorige week, in procentpunt van je doel
            if (d != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(d, style: numStyle(11.5, color: p.ink3)),
              ),
            SizedBox(
              width: 110,
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
              tooltip: tr('Copy summary', 'Samenvatting kopiëren'),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareText(r, s.streak.current)));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('Summary copied: paste it anywhere to share', 'Samenvatting gekopieerd: plak ze waar je wilt om te delen')),
                  ),
                );
              },
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
                                    Text('Nutrient score', style: TextStyle(fontSize: 13, color: p.ink2)),
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
                                        '${r.days} of 7 days fully logged · ${s.streak.current}-day streak',
                                        '${r.days} van 7 dagen volledig gelogd · reeks van ${s.streak.current}',
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
                              const SizedBox(height: 12),
                              PanelTitle(tr('Needs attention', 'Verdient aandacht')),
                              for (final w in r.worst) nutrientRow(w, p.lowFill),
                              const SizedBox(height: 6),
                              Text(
                                tr(
                                  'Average share of your daily goal on fully logged days. ▲▼ = change vs last week.',
                                  'Gemiddeld deel van je dagdoel op volledig gelogde dagen. ▲▼ = verschil met vorige week.',
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
                        'Nutrient score ${r.score}${r.change == null ? '' : ' (${r.change! >= 0 ? '+' : ''}${r.change})'} · ${r.days} volledige dagen gelogd',
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
