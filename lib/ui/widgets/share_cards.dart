/// Deelkaarten: een mooie afbeelding (1080 × 1350, staand) om op Instagram, WhatsApp en zo te delen. Gratis reclame
/// voor de app, dus altijd met het logo en het webadres onderaan.
///
/// Elke kaart is een eigen widget op vaste grootte (geen schermafdruk). Wat persoonlijk is (gewicht, energie, je
/// profielfoto) staat er alleen op als je het aanvinkt: zie [ShareToggle] en share_sheet.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../i18n.dart';
import '../../nutrition/badges.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/report.dart';
import '../theme.dart';
import 'avatar.dart';
import 'badges_view.dart';
import 'kit.dart';

/// Grootte van elke kaart in pixels (Instagram-staand, 4:5).
const shareCardSize = Size(1080, 1350);

/// Sleutels van de vinkjes. Alles wat persoonlijk is, staat standaard uit.
abstract final class ShareShow {
  /// Profielfoto en level.
  static const profile = 'profile';

  /// Energie (kcal) en macro's.
  static const energy = 'energy';

  /// Gewicht of gewichtsverandering.
  static const weight = 'weight';

  /// Wat je het vaakst at.
  static const topFood = 'topfood';
}

/// Een vinkje in het voorbeeld: wat mag er (extra) op de kaart.
class ShareToggle {
  const ShareToggle(this.id, this.label, {this.initial = false});
  final String id;
  final String label;
  final bool initial;
}

/// Wie deelt: alleen getoond met het vinkje [ShareShow.profile].
class ShareProfile {
  const ShareProfile({this.avatar, required this.level});
  final String? avatar;
  final int level;
}

/// Kleur van de vlam van je reeks (dezelfde als in de app).
const _flame = Color(0xFFFF8A00);

/// Kleur voor een score: van licht (laag) naar de volle merkkleur (hoog), zoals in het maandoverzicht.
Color _scoreColor(Palette p, int score) => Color.lerp(p.brandSoft, p.brand, (score / 100).clamp(0.08, 1.0))!;

/// Raamwerk van elke kaart: logo en naam bovenaan, de inhoud, en onderaan de slogan met het webadres.
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({super.key, required this.kicker, required this.child, this.profile});
  final String kicker;
  final Widget child;
  final ShareProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: shareCardSize.width,
      height: shareCardSize.height,
      color: p.bg,
      padding: const EdgeInsets.fromLTRB(80, 72, 80, 64),
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: kSans, color: p.ink, fontSize: 30, height: 1.25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  Image.asset('assets/logo.png', width: 76, height: 76, filterQuality: FilterQuality.medium),
                  const SizedBox(width: 22),
                  Text(
                    'MacroMatrix',
                    style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, letterSpacing: -1.4, color: p.ink),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: profile != null
                          ? LevelAvatar(avatar: profile!.avatar, level: profile!.level, size: 84)
                          : FittedBox(fit: BoxFit.scaleDown, child: _Pill(kicker)),
                    ),
                  ),
                ],
              ),
            ),
            if (profile != null) ...[const SizedBox(height: 28), Align(alignment: Alignment.centerLeft, child: _Pill(kicker))],
            const SizedBox(height: 40),
            Expanded(child: child),
            const SizedBox(height: 40),
            Container(height: 2, color: p.line),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Every vitamin and mineral, tracked', 'Elke vitamine en elk mineraal in beeld'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 28, color: p.ink2),
                  ),
                ),
                const SizedBox(width: 24),
                Text(
                  'app.divinenet.online',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: p.brand),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Klein label in de merkkleur ("MONTHLY RECAP").
class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(40)),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 2.4, color: p.brand),
      ),
    );
  }
}

/// Vlak met rand, zoals een paneel in de app.
class _Box extends StatelessWidget {
  const _Box({required this.child, this.padding = const EdgeInsets.all(36)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: p.line, width: 2),
      ),
      child: child,
    );
  }
}

/// Kerncijfer: groot getal met een label eronder.
class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.color, this.unit});
  final String value, label;
  final Color? color;

  /// Eenheid achter het getal, kleiner en in gewone letters ("dagen").
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return _Box(
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: value,
                style: numStyle(58, color: color ?? p.ink, height: 1.05),
                children: [
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(fontFamily: kSans, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: 0, color: color ?? p.ink),
                    ),
                ],
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 25, color: p.ink2),
          ),
        ],
      ),
    );
  }
}

/// Rij kerncijfers, even breed.
class _Stats extends StatelessWidget {
  const _Stats(this.items);
  final List<Widget> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(width: 20), Expanded(child: w)],
    ],
  );
}

/// Scorering, zoals in het maand- en weekoverzicht.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.size, required this.caption, required this.color, required this.track});
  final int score;
  final double size;
  final String caption;
  final Color color, track;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _Ring(score / 100, stroke: size * 0.075, track: track, fill: color),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$score', style: numStyle(size * 0.36, color: color, height: 1)),
            const SizedBox(height: 6),
            Text(
              caption,
              maxLines: 1,
              style: TextStyle(fontSize: size * 0.085, color: color.withValues(alpha: 0.82)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Ring extends CustomPainter {
  _Ring(this.fraction, {required this.stroke, required this.track, required this.fill});
  final double fraction, stroke;
  final Color track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (fraction > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), false, paint..color = fill);
  }

  @override
  bool shouldRepaint(_Ring old) => old.fraction != fraction || old.fill != fill || old.track != track || old.stroke != stroke;
}

/// Groot vlak in de merkkleur met links een titel en rechts de scorering.
class _Hero extends StatelessWidget {
  const _Hero({required this.eyebrow, required this.title, required this.sub, required this.score, required this.scoreCaption});
  final String eyebrow, title, sub;
  final int score;
  final String scoreCaption;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = p.onBrand;
    return Container(
      padding: const EdgeInsets.fromLTRB(52, 36, 40, 36),
      decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(48)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 2, color: on.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(fontSize: 104, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -3, color: on),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 31, color: on.withValues(alpha: 0.88)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          _ScoreRing(score: score, size: 224, caption: scoreCaption, color: on, track: on.withValues(alpha: 0.22)),
        ],
      ),
    );
  }
}

/// ▲ 3 / ▼ 2 tegenover de vorige periode, of null.
String? _delta(num now, num? before) {
  if (before == null) return null;
  final d = (now - before).round();
  if (d == 0) return '=';
  return '${d > 0 ? '▲' : '▼'} ${fmtInt(d.abs())}';
}

String _days(int n) => n == 1 ? tr('day', 'dag') : tr('days', 'dagen');

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Maand- of jaaroverzicht.
class RecapShareCard extends StatelessWidget {
  const RecapShareCard({super.key, required this.recap, this.show = const {}, this.profile});
  final Recap recap;
  final Set<String> show;
  final ShareProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = recap;
    final name = r.year ? '${r.from.year}' : _cap(DateFormat('MMMM', appLocale).format(r.from));
    final delta = _delta(r.avgScore, r.previous?.avgScore);
    final top = show.contains(ShareShow.topFood) && r.topFoods.isNotEmpty ? r.topFoods.first.$1 : null;
    return ShareCardFrame(
      kicker: r.year ? tr('Year in review', 'Jaaroverzicht') : tr('Monthly recap', 'Maandoverzicht'),
      profile: show.contains(ShareShow.profile) ? profile : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(
            eyebrow: r.year ? tr('My year', 'Mijn jaar') : '${tr('My month', 'Mijn maand')} · ${r.from.year}',
            title: name,
            sub: r.daysInPeriod <= 31
                ? tr('${r.daysLogged} of ${r.daysInPeriod} days logged', '${r.daysLogged} van ${r.daysInPeriod} dagen gelogd')
                : tr('${r.daysLogged} days logged', '${r.daysLogged} dagen gelogd'),
            score: r.avgScore,
            scoreCaption: delta == null ? tr('Nutrient score', 'Voedingsscore') : '$delta ${tr('vs before', 'vs. vorige')}',
          ),
          const SizedBox(height: 28),
          Expanded(
            child: _Box(
              padding: const EdgeInsets.fromLTRB(36, 30, 36, 30),
              child: r.year ? _YearBars(r: r) : _MonthGrid(r: r),
            ),
          ),
          if (top != null) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Icon(Icons.favorite_rounded, color: p.fat, size: 34),
                const SizedBox(width: 14),
                Text(tr('Most logged', 'Meest gelogd'), style: TextStyle(fontSize: 28, color: p.ink2)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    top,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _Stats([
            _Stat('${r.longestStreak}', tr('Longest streak', 'Langste reeks'), unit: _days(r.longestStreak)),
            _Stat(fmtInt(r.distinctFoods), tr('Different foods', 'Verschillende producten')),
            if (show.contains(ShareShow.energy) && r.avgKcal > 0)
              _Stat(fmtInt(r.avgKcal), tr('kcal a day', 'kcal per dag'))
            else
              _Stat(fmtInt(r.xp), tr('XP earned', 'XP verdiend'), color: p.brand),
          ]),
        ],
      ),
    );
  }
}

/// De maand dag per dag: een vakje per dag, hoe donkerder hoe hoger je Voedingsscore.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final first = DateTime(r.from.year, r.from.month);
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // maandag eerst
    final rows = ((lead + days) / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Day by day', 'Dag per dag'),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: p.ink),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            for (final (i, w) in weekdayShort.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, color: p.ink3),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final h = math.max(4.0, math.min(64.0, (c.maxHeight - gap * (rows - 1)) / rows));
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var row = 0; row < rows; row++) ...[
                    if (row > 0) const SizedBox(height: gap),
                    SizedBox(
                      height: h,
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++) ...[
                            if (col > 0) const SizedBox(width: gap),
                            Expanded(child: _dayCell(p, row * 7 + col - lead + 1, days, h)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayCell(Palette p, int day, int days, double h) {
    if (day < 1 || day > days) return const SizedBox.shrink();
    final key = DateFormat('yyyy-MM-dd').format(DateTime(r.from.year, r.from.month, day));
    final score = r.dayScores[key];
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: score == null ? p.track : _scoreColor(p, score), borderRadius: BorderRadius.circular(math.min(16, h / 3))),
      child: h < 30
          ? null
          : Text(
              '$day',
              style: numStyle(math.min(22, h * 0.4), color: score != null && score >= 55 ? p.onBrand : p.ink3, weight: FontWeight.w500),
            ),
    );
  }
}

/// Het jaar maand per maand: een staaf per maand met de gemiddelde Voedingsscore.
class _YearBars extends StatelessWidget {
  const _YearBars({required this.r});
  final Recap r;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sums = List.filled(12, 0), counts = List.filled(12, 0);
    for (final e in r.dayScores.entries) {
      final m = (int.tryParse(e.key.substring(5, 7)) ?? 1) - 1;
      sums[m] += e.value;
      counts[m]++;
    }
    final months = [for (var m = 1; m <= 12; m++) DateFormat('MMM', appLocale).format(DateTime(r.from.year, m)).substring(0, 1).toUpperCase()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Month by month', 'Maand per maand'),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: p.ink),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var m = 0; m < 12; m++) ...[
                  if (m > 0) const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: math.max(8.0, (c.maxHeight - 44) * (counts[m] == 0 ? 0 : sums[m] / counts[m] / 100)),
                          decoration: BoxDecoration(
                            color: counts[m] == 0 ? p.track : _scoreColor(p, sums[m] ~/ counts[m]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: Text(months[m], style: TextStyle(fontSize: 24, color: p.ink3)),
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
    );
  }
}

/// Reeks: "14 dagen op rij", met de laatste twee weken als vakjes.
class StreakShareCard extends StatelessWidget {
  const StreakShareCard({
    super.key,
    required this.days,
    required this.longest,
    required this.recent,
    this.totalDays,
    this.show = const {},
    this.profile,
  });

  /// Huidige reeks.
  final int days;
  final int longest;

  /// De laatste 14 dagen, oudste eerst: gelogd of niet.
  final List<bool> recent;
  final int? totalDays;
  final Set<String> show;
  final ShareProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ShareCardFrame(
      kicker: tr('Streak', 'Reeks'),
      profile: show.contains(ShareShow.profile) ? profile : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _flame.withValues(alpha: 0.14)),
                    child: const Icon(Icons.local_fire_department_rounded, color: _flame, size: 200),
                  ),
                  const SizedBox(height: 24),
                  Text('$days', style: numStyle(240, color: p.ink, height: 1)),
                  Text(
                    days == 1 ? tr('day in a row', 'dag op rij') : tr('days in a row', 'dagen op rij'),
                    style: TextStyle(fontSize: 64, fontWeight: FontWeight.w700, letterSpacing: -1.5, color: p.ink),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Logging what I eat, every single day', 'Elke dag loggen wat ik eet'), style: TextStyle(fontSize: 32, color: p.ink2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _Box(
            padding: const EdgeInsets.fromLTRB(36, 28, 36, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Last 14 days', 'Laatste 14 dagen'), style: TextStyle(fontSize: 26, color: p.ink2)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final (i, on) in recent.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(color: on ? _flame : p.track, borderRadius: BorderRadius.circular(14)),
                          child: on ? Icon(Icons.check_rounded, size: 30, color: p.bg) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _Stats([
            _Stat('$longest', tr('Longest streak', 'Langste reeks'), unit: _days(longest)),
            if (totalDays case final t?) _Stat(fmtInt(t), tr('Days logged', 'Dagen gelogd')),
            if (show.contains(ShareShow.profile) && profile != null) _Stat('${profile!.level}', 'Level', color: p.brand),
          ]),
        ],
      ),
    );
  }
}

/// Wat je ermee bereikte bij een badge, als zin ("Vitamin D on target on 90 days").
String badgeAchievement(String id, int value) {
  final (en, nl) = switch (id) {
    'days' => ('Logged on time on # days', 'Op # dagen op tijd gelogd'),
    'streak' => ('Logged # days in a row', '# dagen op rij gelogd'),
    'perfect' => ('A Nutrient score of 95+ on # days', 'Op # dagen een Voedingsscore van 95+'),
    'vitd' => ('Vitamin D on target on # days', 'Op # dagen vitamine D op doel'),
    'fiber' => ('Fiber goal reached on # days', 'Op # dagen het vezeldoel gehaald'),
    'iron' => ('Iron on target on # days', 'Op # dagen ijzer op doel'),
    'omega' => ('Omega balance for # days in a row', '# dagen op rij omega-balans'),
    'protein' => ('Protein goal reached on # days', 'Op # dagen het eiwitdoel gehaald'),
    'variety' => ('# different foods logged', '# verschillende producten gelogd'),
    'perfectweek' => ('# weeks with a score of 90+', '# weken met een score van 90+'),
    'scanner' => ('# products scanned', '# producten gescand'),
    'social' => ('# friends on MacroMatrix', '# vrienden op MacroMatrix'),
    'level' => ('Reached level #', 'Level # gehaald'),
    'battles' => ('# battles played', '# battles gespeeld'),
    'wins' => ('# battles won', '# battles gewonnen'),
    'winstreak' => ('# battles won in a row', '# battles op rij gewonnen'),
    'comeback' => ('# comeback wins', '# keer gewonnen na een achterstand'),
    _ => ('#', '#'),
  };
  return tr(en, nl).replaceAll('#', fmtInt(value));
}

/// Doel gehaald: een badge, of al je vitaminen en mineralen op een dag.
class GoalShareCard extends StatelessWidget {
  const GoalShareCard({
    super.key,
    required this.visual,
    required this.headline,
    this.sub,
    this.label,
    this.labelColor,
    this.show = const {},
    this.profile,
  });

  /// Groot beeld bovenaan (badge of raster van vitaminen).
  final Widget visual;
  final String headline;
  final String? sub;

  /// Bv. "Gold · Sunshine", in [labelColor].
  final String? label;
  final Color? labelColor;
  final Set<String> show;
  final ShareProfile? profile;

  /// Kaart voor een badge op een niveau.
  factory GoalShareCard.badge({required String category, required int tier, required int value, Set<String> show = const {}, ShareProfile? profile}) {
    final c = categoryById[category]!;
    return GoalShareCard(
      visual: BadgeIcon(category: category, tier: tier, size: 400),
      label: '${tierName(tier)} · ${c.name}',
      labelColor: tierColor(tier),
      headline: badgeAchievement(category, value),
      sub: tr('Badge earned on MacroMatrix', 'Badge verdiend op MacroMatrix'),
      show: show,
      profile: profile,
    );
  }

  /// Kaart voor een dag waarop je al je vitaminen en mineralen haalde ([reached] van [total]).
  /// [labels] = afkortingen van de stoffen die meetellen (A, C, D, ... Zn).
  factory GoalShareCard.allMicros({
    required int reached,
    required int total,
    required DateTime day,
    List<String>? labels,
    Set<String> show = const {},
    ShareProfile? profile,
  }) {
    final all = reached >= total;
    return GoalShareCard(
      visual: MicroGrid(reachedAll: all, labels: labels),
      label: _cap(DateFormat('EEEE d MMMM', appLocale).format(day)),
      headline: all
          ? tr('All $total vitamins and minerals on target', 'Alle $total vitaminen en mineralen op doel')
          : tr('$reached of $total vitamins and minerals on target', '$reached van de $total vitaminen en mineralen op doel'),
      sub: tr('From food, not guesswork', 'Uit wat ik at, gewoon gemeten'),
      show: show,
      profile: profile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ShareCardFrame(
      kicker: tr('Goal reached', 'Doel gehaald'),
      profile: show.contains(ShareShow.profile) ? profile : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: visual),
            ),
          ),
          const SizedBox(height: 40),
          if (label != null) ...[
            Text(
              label!.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2.4, color: labelColor ?? p.brand),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            headline,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 70, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -2, color: p.ink),
          ),
          if (sub != null) ...[
            const SizedBox(height: 18),
            Text(
              sub!,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 32, color: p.ink2),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Raster van de 25 vitaminen en mineralen, allemaal groen als je ze haalde.
class MicroGrid extends StatelessWidget {
  const MicroGrid({super.key, this.reachedAll = true, this.labels});
  final bool reachedAll;

  /// Afkortingen; standaard alle 25.
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all =
        labels ??
        [
          for (final (_, a) in [...stripVitamins, ...stripMinerals]) a,
        ];
    return SizedBox(
      width: 920,
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: [
          for (final abbr in all)
            Container(
              width: 168,
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: reachedAll ? p.okSoft : p.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: reachedAll ? p.okFill : p.line, width: 3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(abbr, style: numStyle(38, color: reachedAll ? p.ok : p.ink2)),
                  if (reachedAll) ...[const SizedBox(width: 8), Icon(Icons.check_rounded, color: p.ok, size: 32)],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Weekrapport: Voedingsscore, de dagen van de week en je sterkste stoffen.
class WeekShareCard extends StatelessWidget {
  const WeekShareCard({super.key, required this.report, required this.dayScores, this.streak = 0, this.show = const {}, this.profile});
  final WeeklyReport report;

  /// Voedingsscore per dag (maandag eerst), null als niet gelogd.
  final List<int?> dayScores;
  final int streak;
  final Set<String> show;
  final ShareProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = report;
    final f = DateFormat('d MMM', appLocale);
    final end = DateTime(r.monday.year, r.monday.month, r.monday.day + 6);
    final change = r.change;
    final best = r.best.take(3).toList();
    final weight = r.weightChange;
    return ShareCardFrame(
      kicker: tr('Weekly report', 'Weekrapport'),
      profile: show.contains(ShareShow.profile) ? profile : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(
            eyebrow: tr('My week', 'Mijn week'),
            title: '${f.format(r.monday)} – ${f.format(end)}',
            sub: tr('${r.days} of 7 days fully logged', '${r.days} van 7 dagen volledig gelogd'),
            score: r.score,
            scoreCaption: change == null
                ? tr('Nutrient score', 'Voedingsscore')
                : '${change > 0 ? '▲' : (change < 0 ? '▼' : '=')} ${change == 0 ? '' : change.abs()} ${tr('vs last week', 'vs. vorige week')}'
                      .replaceAll('  ', ' '),
          ),
          const SizedBox(height: 24),
          _Box(
            padding: const EdgeInsets.fromLTRB(36, 26, 36, 26),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        Text(weekdayShort[i], style: TextStyle(fontSize: 24, color: p.ink3)),
                        const SizedBox(height: 12),
                        Container(
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: dayScores[i] == null ? p.track : _scoreColor(p, dayScores[i]!),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: dayScores[i] == null
                              ? null
                              : Text('${dayScores[i]}', style: numStyle(30, color: dayScores[i]! >= 55 ? p.onBrand : p.ink2)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            // Sterkste stoffen: alleen als er plaats is (met profiel en alle vinkjes is het krap)
            child: LayoutBuilder(
              builder: (context, c) => c.maxHeight < 150
                  ? const SizedBox.shrink()
                  : _Box(
                      padding: const EdgeInsets.fromLTRB(36, 30, 36, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr('Strongest this week', 'Sterkst deze week'),
                            maxLines: 1,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: p.ink),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            // Zoveel stoffen als er passen (hoogstens 3)
                            child: LayoutBuilder(
                              builder: (context, c) => best.isEmpty
                                  ? Text(
                                      tr('Building up: more to come next week', 'Nog aan het opbouwen: volgende week meer'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 28, color: p.ink2),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [for (final (n, frac) in best.take((c.maxHeight / 56).floor())) _NutrientBar(n: n, frac: frac)],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 22),
          _Stats([
            _Stat('$streak', tr('Streak', 'Reeks'), unit: _days(streak), color: streak > 0 ? _flame : null),
            if (show.contains(ShareShow.energy) && r.kcalAvg != null) _Stat(fmtInt(r.kcalAvg!), tr('kcal a day', 'kcal per dag')),
            if (show.contains(ShareShow.weight) && weight != null)
              _Stat('${weight > 0 ? '+' : (weight < 0 ? '−' : '±')}${fmtGrouped(weight.abs())} kg', tr('Weight this week', 'Gewicht deze week')),
            if (r.health case final h?) _Stat('${h.score}', tr('Health score', 'Gezondheidsscore'), color: p.brand),
          ]),
        ],
      ),
    );
  }
}

class _NutrientBar extends StatelessWidget {
  const _NutrientBar({required this.n, required this.frac});
  final Nutrient n;
  final double frac;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        SizedBox(
          width: 330,
          child: Text(
            n.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 30, color: p.ink),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), minHeight: 20, backgroundColor: p.track, color: p.okFill),
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 130,
          child: Text(
            frac > 2 ? '200%+' : fmtPct(frac),
            textAlign: TextAlign.right,
            style: numStyle(30, color: p.ink2),
          ),
        ),
      ],
    );
  }
}
