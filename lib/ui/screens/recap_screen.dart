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

/// Maand- of jaaroverzicht in de stijl van een "wrapped": grote cijfers op kleurige kaarten.
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

    Widget card(List<Color> colors, Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
        child: child,
      ),
    );
    Widget big(String v) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(v, style: numStyle(52, color: Colors.white, height: 1.05)),
    );
    Widget label(String v) => Text(
      v,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70, letterSpacing: 0.4),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
                      card(
                        const [Color(0xFF0F766E), Color(0xFF14B8A6)],
                        Row(
                          children: [
                            LevelAvatar(avatar: s.avatar, level: s.level.level, size: 64),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    // 'van de 412 dagen' sinds de installatie klinkt als een verwijt; enkel bij een maand of korter
                                    r.daysInPeriod <= 31
                                        ? tr(
                                            'You logged ${r.daysLogged} of ${r.daysInPeriod} days.',
                                            'Je logde ${r.daysLogged} van de ${r.daysInPeriod} dagen.',
                                          )
                                        : tr(
                                            '${r.daysLogged} ${r.daysLogged == 1 ? 'day' : 'days'} logged.',
                                            '${r.daysLogged} ${r.daysLogged == 1 ? 'dag' : 'dagen'} gelogd.',
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      card(
                        const [Color(0xFF7C3AED), Color(0xFFC084FC)],
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(tr('DIFFERENT FOODS', 'VERSCHILLENDE PRODUCTEN')),
                            big(fmtInt(r.distinctFoods)),
                            Text(tr('out of ${fmtInt(r.entries)} things you logged', 'op ${fmtInt(r.entries)} dingen die je logde')),
                            const SizedBox(height: 14),
                            label(tr('YOUR TOP 5', 'JOUW TOP 5')),
                            const SizedBox(height: 4),
                            for (final (i, (name, n)) in r.topFoods.indexed)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text('${n}x', style: const TextStyle(color: Colors.white70)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      card(
                        const [Color(0xFF2563EB), Color(0xFF60A5FA)],
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(tr('AVERAGE NUTRIENT SCORE', 'GEMIDDELDE NUTRIENT SCORE')),
                            big('${r.avgScore}'),
                            if (r.bestDay != null)
                              Text(
                                tr(
                                  'Best day: ${DateFormat('EEEE d MMMM', appLocale).format(r.bestDay!.$1)} with ${r.bestDay!.$2}.',
                                  'Beste dag: ${DateFormat('EEEE d MMMM', appLocale).format(r.bestDay!.$1)} met ${r.bestDay!.$2}.',
                                ),
                              ),
                            if (r.bestMonth != null)
                              Text(
                                tr(
                                  'Best month: ${DateFormat('MMMM', appLocale).format(r.bestMonth!.$1)} (${r.bestMonth!.$2}).',
                                  'Beste maand: ${DateFormat('MMMM', appLocale).format(r.bestMonth!.$1)} (${r.bestMonth!.$2}).',
                                ),
                              ),
                          ],
                        ),
                      ),
                      card(
                        const [Color(0xFFEA580C), Color(0xFFFBBF24)],
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  label(tr('LONGEST STREAK', 'LANGSTE REEKS')),
                                  big('${r.longestStreak}'),
                                  Text(tr('days in a row', 'dagen op rij')),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [label('XP'), big(fmtInt(r.xp)), Text(tr('earned', 'verdiend'))],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (r.topNutrient != null)
                        card(
                          const [Color(0xFF059669), Color(0xFF84CC16)],
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              label(tr('YOUR SUPERPOWER', 'JOUW SUPERKRACHT')),
                              const SizedBox(height: 4),
                              Text(
                                r.topNutrient!.$1.name,
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              Text(
                                tr(
                                  'On average ${r.topNutrient!.$2 >= 1.5 ? '150%+' : fmtPct(r.topNutrient!.$2)} of your daily goal.',
                                  'Gemiddeld ${r.topNutrient!.$2 >= 1.5 ? '150%+' : fmtPct(r.topNutrient!.$2)} van je dagdoel.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      card(
                        const [Color(0xFFDB2777), Color(0xFFF472B6)],
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(tr('ENERGY', 'ENERGIE')),
                            big(fmtInt(r.avgKcal)),
                            Text(tr('kcal on an average logged day', 'kcal op een gemiddelde gelogde dag')),
                            if (r.favouriteBreakfast != null) ...[
                              const SizedBox(height: 14),
                              label(tr('FAVOURITE BREAKFAST', 'FAVORIET ONTBIJT')),
                              Text(r.favouriteBreakfast!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
      borderColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
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
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED)),
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
