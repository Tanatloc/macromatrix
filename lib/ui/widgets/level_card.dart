import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nutrition/levels.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../../nutrition/badges.dart';
import 'avatar.dart';
import 'badges_view.dart';
import 'kit.dart';
import 'pro_widgets.dart';
import '../../i18n.dart';

/// Je avatar, level en XP, met uitleg hoe je XP verdient.
class LevelCard extends StatefulWidget {
  const LevelCard({super.key});

  @override
  State<LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<LevelCard> {
  bool _help = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final info = s.level;
    final today = info.dayOf(dayKey(logicalNow()));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LevelAvatar(
                avatar: s.avatar,
                level: info.level,
                size: 72,
                frame: myFrameOf(context),
                onTap: () async {
                  final v = await pickAvatar(context, s.avatar);
                  if (v != null) s.setAvatar(v);
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Level ${info.level}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.ink),
                          ),
                        ),
                        // Supporter (Pro): hetzelfde badge dat je vrienden naast je naam zien
                        if (proOf(context)?.supporter ?? false) ...[const SizedBox(width: 8), const SupporterBadge()],
                      ],
                    ),
                    InkWell(
                      onTap: () => pickTitle(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              titleById[s.title]?.name ?? '',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: levelColor(info.level)),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_outlined, size: 14, color: pal.ink3),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(value: info.progress, minHeight: 10, backgroundColor: pal.track, color: levelColor(info.level)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        '${fmtInt(info.xp - info.levelStart)} / ${fmtInt(info.nextLevel - info.levelStart)} XP · ${fmtInt(info.nextLevel - info.xp)} to level ${info.level + 1}',
                        '${fmtInt(info.xp - info.levelStart)} / ${fmtInt(info.nextLevel - info.levelStart)} XP · nog ${fmtInt(info.nextLevel - info.xp)} tot level ${info.level + 1}',
                      ),
                      style: TextStyle(fontSize: 12, color: pal.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: pal.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  today == null
                      ? tr('Log your food today to earn XP.', 'Log vandaag je eten om XP te verdienen.')
                      : tr(
                          'Today: +${today.xp} XP${today.bonus ? ' (×1.5 for your streak)' : ''}',
                          'Vandaag: +${today.xp} XP${today.bonus ? ' (×1,5 voor je reeks)' : ''}',
                        ),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: pal.ink),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _help = !_help),
                child: Text(_help ? tr('Close', 'Sluiten') : tr('How does it work?', 'Hoe werkt het?')),
              ),
            ],
          ),
          if (_help)
            Text(
              tr(
                '• Every day you log your food, you earn XP equal to that day\'s Nutrient score (0 to 100).\n'
                    '• From $streakBonusDays days in a row you get 1.5 times as much.\n'
                    '• Only what you log in the app counts: imported data and days you fill in later give no XP.\n'
                    '• Each level needs a bit more XP. Your border changes colour slightly with every level, and every 25 levels you earn a star '
                    '(up to 4, at level 100). Reaching level 100 takes about a year of logging well every day.\n'
                    '• Tap your photo to change it.',
                '• Elke dag dat je je eten logt, krijg je XP gelijk aan je Voedingsscore van die dag (0 tot 100).\n'
                    '• Vanaf $streakBonusDays dagen op rij krijg je 1,5 keer zoveel.\n'
                    '• Alleen wat je in de app logt, telt: geïmporteerde gegevens en dagen die je pas later invult, geven geen XP.\n'
                    '• Elk level vraagt wat meer XP. Je rand krijgt bij elk level een iets andere kleur, en per 25 levels krijg je een ster '
                    '(maximaal 4, bij level 100). Level 100 haal je met ongeveer een jaar elke dag goed loggen.\n'
                    '• Tik op je foto om ze te wijzigen.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.5, color: pal.ink2),
            ),
        ],
      ),
    );
  }
}
