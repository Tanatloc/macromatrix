import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/report.dart';
import '../../state/app_state.dart';
import '../../sync/friends.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/kit.dart';

/// Weekrapport: je gemiddelde Nutrient Score tegenover vorige week, beste en zwakste stoffen, battles en een tip.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key, required this.monday});
  final DateTime monday;

  static String _range(DateTime m) {
    final f = DateFormat('d MMM', appLocale);
    return '${f.format(m)} – ${f.format(DateTime(m.year, m.month, m.day + 6))}';
  }

  /// Tekst om te delen of te kopiëren.
  static String shareText(WeeklyReport r, int streak) {
    final change = r.change;
    return [
      tr('My MacroMatrix week (${_range(r.monday)})', 'Mijn MacroMatrix-week (${_range(r.monday)})'),
      tr(
        'Nutrient Score: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change vs last week)'}',
        'Nutrient Score: ${r.score}${change == null ? '' : ' (${change >= 0 ? '+' : ''}$change t.o.v. vorige week)'}',
      ),
      tr('Days logged: ${r.days}/7 · streak: $streak', 'Gelogde dagen: ${r.days}/7 · reeks: $streak'),
      tr('Best: ${r.best.map((b) => b.$1.name).join(', ')}', 'Best: ${r.best.map((b) => b.$1.name).join(', ')}'),
      'app.divinenet.online',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = context.watch<Friends>();
    final p = context.pal;
    final r = s.weeklyReport(monday);
    final battles = f.battles.where((b) => b.finished && b.week == monday).toList();
    final level = s.level;

    Widget nutrientRow((dynamic, double) x, Color color) {
      final (n, frac) = x;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(n.name as String, style: TextStyle(fontSize: 14, color: p.ink)),
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
                      child: Text(tr('Nothing logged in this week.', 'Niets gelogd in deze week.'), style: TextStyle(color: p.ink2)),
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
                                    Text('Nutrient Score', style: TextStyle(fontSize: 13, color: p.ink2)),
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
                                        '${r.days} of 7 days logged · ${s.streak.current}-day streak',
                                        '${r.days} van 7 dagen gelogd · reeks van ${s.streak.current}',
                                      ),
                                      style: TextStyle(fontSize: 12.5, color: p.ink3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
                                  'Average share of your daily goal on the days you logged.',
                                  'Gemiddeld deel van je dagdoel op de dagen die je logde.',
                                ),
                                style: TextStyle(fontSize: 11.5, color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        if (r.tip != null) ...[
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
    final m = mondayOf(DateTime.now());
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
                    'Nutrient Score ${r.score}${r.change == null ? '' : ' (${r.change! >= 0 ? '+' : ''}${r.change})'} · ${r.days} days logged',
                    'Nutrient Score ${r.score}${r.change == null ? '' : ' (${r.change! >= 0 ? '+' : ''}${r.change})'} · ${r.days} dagen gelogd',
                  ),
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
