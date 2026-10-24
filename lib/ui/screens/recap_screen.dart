import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/report.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/kit.dart';

/// Maand- of jaaroverzicht, in dezelfde rustige stijl als het weekrapport.
class RecapScreen extends StatelessWidget {
  const RecapScreen({super.key, required this.from, required this.year});
  final DateTime from;
  final bool year;

  DateTime get to => year ? DateTime(from.year, 12, 31) : DateTime(from.year, from.month + 1, 0);

  String get title => year
      ? tr('Your ${from.year}', 'Jouw ${from.year}')
      : tr('Your ${DateFormat('MMMM', appLocale).format(from)}', 'Jouw ${DateFormat('MMMM', appLocale).format(from)}');

  String shareText(Recap r) => [
    tr('$title on MacroMatrix', '$title op MacroMatrix'),
    tr('${r.daysLogged} days logged, ${r.distinctFoods} different foods', '${r.daysLogged} dagen gelogd, ${r.distinctFoods} verschillende producten'),
    tr('Average Nutrient score: ${r.avgScore}', 'Gemiddelde Voedingsscore: ${r.avgScore}'),
    tr('Longest streak: ${r.longestStreak} days · ${fmtInt(r.xp)} XP', 'Langste reeks: ${r.longestStreak} dagen · ${fmtInt(r.xp)} XP'),
    if (r.topFoods.isNotEmpty) tr('Most logged: ${r.topFoods.first.$1}', 'Meest gelogd: ${r.topFoods.first.$1}'),
    'app.divinenet.online',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final r = s.recap(from, to, year: year);

    // Zelfde opbouw als het weekrapport: rustige panelen, cijfers in inkt, één zachte merkkleur bovenaan
    Widget section(String title, Widget child, {String? subtitle}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [PanelTitle(title, subtitle: subtitle), const SizedBox(height: 10), child],
        ),
      ),
    );
    Widget big(String v, {String? unit}) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(v, style: numStyle(40, color: p.ink)),
        if (unit != null) ...[const SizedBox(width: 6), Text(unit, style: TextStyle(fontSize: 14, color: p.ink2))],
      ],
    );
    Widget note(String v) => Text(v, style: TextStyle(fontSize: 13, color: p.ink3, height: 1.35));

    return Scaffold(
      appBar: AppBar(
        title: Text(year ? tr('Year in review', 'Jaaroverzicht') : tr('Monthly recap', 'Maandoverzicht')),
        actions: [
          if (r != null)
            IconButton(
              tooltip: tr('Copy summary', 'Samenvatting kopiëren'),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareText(r)));
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Narrow(
            child: r == null
                ? Panel(
                    child: Text(tr('Nothing logged in this period.', 'Niets gelogd in deze periode.'), style: TextStyle(color: p.ink2)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Opening: wie, welke periode, en de drie kerncijfers
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Panel(
                          shadow: false,
                          color: p.brandSoft,
                          borderColor: p.brandSoft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  LevelAvatar(avatar: s.avatar, level: s.level.level, size: 56),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: p.ink),
                                        ),
                                        Text(
                                          // 'van de 412 dagen' klinkt als een verwijt; enkel bij een maand of korter
                                          r.daysInPeriod <= 31
                                              ? tr(
                                                  'You logged ${r.daysLogged} of ${r.daysInPeriod} days.',
                                                  'Je logde ${r.daysLogged} van de ${r.daysInPeriod} dagen.',
                                                )
                                              : tr(
                                                  '${r.daysLogged} ${r.daysLogged == 1 ? 'day' : 'days'} logged.',
                                                  '${r.daysLogged} ${r.daysLogged == 1 ? 'dag' : 'dagen'} gelogd.',
                                                ),
                                          style: TextStyle(fontSize: 13.5, color: p.ink2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: StatTile(
                                      label: tr('Best streak', 'Beste reeks'),
                                      value: tr('${r.longestStreak} ${r.longestStreak == 1 ? 'day' : 'days'}', '${r.longestStreak} ${r.longestStreak == 1 ? 'dag' : 'dagen'}'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: StatTile(label: tr('Foods', 'Producten'), value: fmtInt(r.distinctFoods))),
                                  const SizedBox(width: 8),
                                  Expanded(child: StatTile(label: tr('XP earned', 'XP verdiend'), value: fmtInt(r.xp))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      section(
                        tr('Nutrient score', 'Voedingsscore'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            big('${r.avgScore}', unit: tr('on average', 'gemiddeld')),
                            if (r.bestDay != null)
                              note(
                                tr(
                                  'Best day: ${DateFormat('EEEE d MMMM', appLocale).format(r.bestDay!.$1)} with ${r.bestDay!.$2}.',
                                  'Beste dag: ${DateFormat('EEEE d MMMM', appLocale).format(r.bestDay!.$1)} met ${r.bestDay!.$2}.',
                                ),
                              ),
                            if (r.bestMonth != null)
                              note(
                                tr(
                                  'Best month: ${DateFormat('MMMM', appLocale).format(r.bestMonth!.$1)} (${r.bestMonth!.$2}).',
                                  'Beste maand: ${DateFormat('MMMM', appLocale).format(r.bestMonth!.$1)} (${r.bestMonth!.$2}).',
                                ),
                              ),
                          ],
                        ),
                      ),
                      section(
                        tr('What you ate most', 'Wat je het meest at'),
                        subtitle: tr(
                          '${fmtInt(r.distinctFoods)} different foods in ${fmtInt(r.entries)} entries',
                          '${fmtInt(r.distinctFoods)} verschillende producten in ${fmtInt(r.entries)} regels',
                        ),
                        Column(
                          children: [
                            for (final (i, (name, n)) in r.topFoods.indexed)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text('${i + 1}', style: numStyle(13, color: p.ink3)),
                                    ),
                                    Expanded(
                                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.ink)),
                                    ),
                                    Text('$n×', style: numStyle(13, color: p.ink2)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Alleen als het echt goed ging: 28% van je doel is geen sterkste punt
                      if (r.topNutrient != null && r.topNutrient!.$2 >= 0.75)
                        section(
                          tr('Your strongest nutrient', 'Je sterkste voedingsstof'),
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: p.ok, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.topNutrient!.$1.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
                                    note(
                                      tr(
                                        'On average ${r.topNutrient!.$2 >= 1.5 ? '150%+' : fmtPct(r.topNutrient!.$2)} of your daily goal.',
                                        'Gemiddeld ${r.topNutrient!.$2 >= 1.5 ? '150%+' : fmtPct(r.topNutrient!.$2)} van je dagdoel.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      section(
                        tr('Energy', 'Energie'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            big(fmtInt(r.avgKcal), unit: tr('kcal per logged day', 'kcal per gelogde dag')),
                            if (r.favouriteBreakfast != null) ...[
                              const SizedBox(height: 10),
                              Eyebrow(tr('Favourite breakfast', 'Favoriet ontbijt')),
                              const SizedBox(height: 2),
                              Text(r.favouriteBreakfast!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.ink)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Kaart op Vandaag tijdens de eerste dagen van een maand (en in januari ook voor het jaar).
class RecapCard extends StatelessWidget {
  const RecapCard({super.key});

  /// (begin, jaar?) van het overzicht dat nu klaarstaat, of null.
  static (DateTime, bool)? due(AppState s) {
    final now = DateTime.now();
    if (now.day > 5 && !(now.month == 1 && now.day <= 10)) return null;
    final candidates = [if (now.month == 1) (DateTime(now.year - 1), true), (DateTime(now.year, now.month - 1), false)];
    for (final (from, year) in candidates) {
      final key = '${year ? 'y' : 'm'}${dayKey(from)}';
      if (s.user.setting('_recap_seen')?['key'] == key) continue;
      final to = year ? DateTime(from.year, 12, 31) : DateTime(from.year, from.month + 1, 0);
      final a = dayKey(from), b = dayKey(to);
      if (s.user.loggedDays().any((d) => d.compareTo(a) >= 0 && d.compareTo(b) <= 0)) return (from, year);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final d = due(s);
    if (d == null) return const SizedBox.shrink();
    final (from, year) = d;
    final key = '${year ? 'y' : 'm'}${dayKey(from)}';
    final name = year ? '${from.year}' : DateFormat('MMMM', appLocale).format(from);
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      color: p.brandSoft,
      borderColor: p.brandSoft,
      onTap: () {
        s.markRecapSeen(key);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecapScreen(from: from, year: year),
          ),
        );
      },
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Your $name in review is ready', 'Jouw $name in een notendop staat klaar'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: tr('Dismiss', 'Verbergen'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => s.markRecapSeen(key),
          ),
        ],
      ),
    );
  }
}
