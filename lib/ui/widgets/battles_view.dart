import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/badges.dart';
import '../../state/app_state.dart';
import '../../sync/friends.dart';
import '../screens/friends_screen.dart' show confirmBlock, showReportDialog;
import '../theme.dart';
import 'avatar.dart';
import 'badges_view.dart';
import 'kit.dart';
import 'pro_widgets.dart';
import '../../sync/pro.dart' show AvatarFrame;

String _name(String n) => n.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : n;

/// Uitleg hoe een battle werkt.
String get battleRules => tr(
  'A battle runs Monday to Sunday. Every day you log your food on time, your Nutrient score counts as points (up to 100 a day). '
      'Whoever has the most points on Sunday evening wins. You can have one battle a week with each friend, so several at once. '
      'Battles give no XP: you earn badges, titles and bragging rights.',
  'Een battle loopt van maandag tot en met zondag. Elke dag dat je op tijd je eten logt, telt je Voedingsscore als punten (max. 100 per dag). '
      'Wie zondagavond de meeste punten heeft, wint. Met elke vriend kan je één battle per week hebben, dus ook meerdere tegelijk. '
      'Battles geven geen XP: je verdient badges, titels en eer.',
);

/// Battles op het tabblad Vrienden: uitdagingen, lopende battles van deze week en de uitslagen van vorige week.
class BattlesPanel extends StatelessWidget {
  const BattlesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<Friends>();
    final pal = context.pal;
    final monday = mondayOf(DateTime.now());
    final lastMonday = DateTime(monday.year, monday.month, monday.day - 7);
    final incoming = f.battles.where((b) => b.pending && !b.challengedByMe).toList();
    final outgoing = f.battles.where((b) => b.pending && b.challengedByMe).toList();
    final live = f.battles.where((b) => b.live).toList();
    final last = f.battles.where((b) => b.finished && b.week == lastMonday).toList();
    final daysLeft = 7 - (DateTime.now().weekday - 1);

    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            'Battles',
            trailing: IconButton(
              tooltip: tr('How do battles work?', 'Hoe werken battles?'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.info_outline_rounded, size: 18, color: pal.ink3),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Battles'),
                  content: Text(battleRules),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Close', 'Sluiten')))],
                ),
              ),
            ),
          ),
          if (!f.battlesAvailable)
            Text(tr('Battles are not available yet.', 'Battles zijn nog niet beschikbaar.'), style: TextStyle(fontSize: 13, color: pal.ink3))
          else ...[
            // Uitnodiging: tekst boven, knoppen eronder (anders brak de zin op vier regels tussen de knoppen: S14)
            for (final b in incoming)
              Container(
                key: ValueKey('battle-invite-${b.id}'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: pal.brandSoft, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LevelAvatar(avatar: b.otherAvatar, level: b.otherLevel, size: 36, frame: f.frameFor(b.other)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr('${_name(b.otherName)} challenges you this week', '${_name(b.otherName)} daagt je uit deze week'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnswerButtons(onDecline: () => f.respondBattle(b, false), onAccept: () => f.respondBattle(b, true)),
                  ],
                ),
              ),
            for (final b in live) _LiveBattle(battle: b, daysLeft: daysLeft),
            // Je eigen uitdaging die nog open staat, met Annuleren (S06)
            for (final b in outgoing)
              Padding(
                key: ValueKey('battle-sent-${b.id}'),
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    AvatarImage(avatar: b.otherAvatar, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('Waiting for ${_name(b.otherName)} to accept', 'Wachten tot ${_name(b.otherName)} aanvaardt'),
                        style: TextStyle(fontSize: 13, color: pal.ink2),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => f.cancelBattle(b),
                      child: Text(tr('Cancel', 'Annuleren')),
                    ),
                  ],
                ),
              ),
            if (last.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr('Last week', 'Vorige week'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.ink2),
              ),
              for (final b in last) _ResultRow(battle: b),
            ],
            if (incoming.isEmpty && live.isEmpty && outgoing.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr(
                    'No battle this week. Tap a friend in the leaderboard to challenge them.',
                    'Geen battle deze week. Tik op een vriend in de ranglijst om die uit te dagen.',
                  ),
                  style: TextStyle(fontSize: 13, color: pal.ink3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LiveBattle extends StatelessWidget {
  const _LiveBattle({required this.battle, required this.daysLeft});
  final Battle battle;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<AppState>();
    final b = battle;
    // Eigen punten meteen uit het toestel, zodat je ze live ziet stijgen
    final mine = s.battlePoints(b.week).points;
    final total = (mine + b.otherPoints).clamp(1, 1 << 30);
    final ahead = mine > b.otherPoints, tied = mine == b.otherPoints;
    final friends = context.watch<Friends?>();
    final supporters = friends?.supporters ?? const <String>{};
    Widget side(
      String? avatar,
      int level,
      String name,
      int points,
      CrossAxisAlignment align, {
      bool supporter = false,
      AvatarFrame? frame,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          LevelAvatar(avatar: avatar, level: level, size: 40, frame: frame),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink),
                ),
              ),
              if (supporter) ...[const SizedBox(width: 4), const SupporterBadge(compact: true)],
            ],
          ),
          Text('$points', style: numStyle(22, color: pal.ink)),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: pal.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              side(
                s.avatar,
                s.level.level,
                tr('You', 'Jij'),
                mine,
                CrossAxisAlignment.start,
                supporter: proOf(context)?.supporter ?? false,
                frame: myFrameOf(context),
              ),
              Text(
                'VS',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.ink3),
              ),
              side(
                b.otherAvatar,
                b.otherLevel,
                _name(b.otherName),
                b.otherPoints,
                CrossAxisAlignment.end,
                supporter: supporters.contains(b.other),
                frame: friends?.frameFor(b.other),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (mine * 1000 ~/ total).clamp(1, 1000),
                    child: Container(color: pal.brand),
                  ),
                  Expanded(
                    flex: (b.otherPoints * 1000 ~/ total).clamp(1, 1000),
                    child: Container(color: pal.carbs),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              tied
                  ? tr('Neck and neck', 'Gelijke stand')
                  : (ahead
                        ? tr('You are ahead by ${mine - b.otherPoints}', 'Je staat ${mine - b.otherPoints} voor')
                        : tr('You are behind by ${b.otherPoints - mine}', 'Je staat ${b.otherPoints - mine} achter')),
              daysLeft == 1 ? tr('last day', 'laatste dag') : tr('$daysLeft days left', 'nog $daysLeft dagen'),
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: pal.ink2),
          ),
          const SizedBox(height: 4),
          // Battlepunten zijn een som (alleen op tijd gelogd), de ranglijst toont een gemiddelde: zeggen waarom de
          // getallen verschillen (S02)
          Text(
            tr(
              'Points: the sum of the day scores you logged on time this week. The leaderboard shows the average.',
              'Punten: de som van de dagscores die je deze week op tijd logde. De ranglijst toont het gemiddelde.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: pal.ink3),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.battle});
  final Battle battle;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final b = battle;
    final (text, color, icon) = switch (b.result) {
      BattleResult.won => (
        tr('You beat ${_name(b.otherName)}', 'Je won van ${_name(b.otherName)}') + (b.comeback ? tr(' (comeback!)', ' (comeback!)') : ''),
        pal.ok,
        Icons.emoji_events_rounded,
      ),
      BattleResult.lost => (tr('${_name(b.otherName)} won', '${_name(b.otherName)} won'), pal.ink2, Icons.flag_outlined),
      BattleResult.draw => (tr('Draw with ${_name(b.otherName)}', 'Gelijkspel met ${_name(b.otherName)}'), pal.ink2, Icons.handshake_outlined),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, color: pal.ink)),
          ),
          Text('${b.myPoints} – ${b.otherPoints}', style: numStyle(13.5, color: pal.ink2)),
        ],
      ),
    );
  }
}

/// Profiel van een vriend: level, titel, badges, jullie onderlinge stand en een knop om uit te dagen.
Future<void> showFriendSheet(BuildContext context, Friend x) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => _FriendSheet(friendId: x.id),
);

class _FriendSheet extends StatelessWidget {
  const _FriendSheet({required this.friendId});
  final String friendId;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<Friends>();
    final pal = context.pal;
    final x = f.list.where((e) => e.id == friendId).firstOrNull;
    if (x == null) return const SizedBox(height: 120);
    final (won, lost, draw) = f.rivalry(x.id);
    final current = f.currentBattleWith(x.id);
    final history = f.finishedBattles.where((b) => b.other == x.id).toList().reversed.take(8).toList();
    final title = titleById[x.title]?.name;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Center(
              child: LevelAvatar(avatar: x.avatar, level: x.level, size: 84, frame: f.frameFor(x.id)),
            ),
            const SizedBox(height: 8),
            Text(
              _name(x.name),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.ink),
            ),
            if (x.supporter)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Center(child: SupporterBadge()),
              ),
            Text(
              ['Level ${x.level}', ?title].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: levelColor(x.level)),
            ),
            const SizedBox(height: 16),
            // Rivaliteit
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.line),
              ),
              child: Column(
                children: [
                  Text(tr('Your rivalry', 'Jullie rivaliteit'), style: TextStyle(fontSize: 12.5, color: pal.ink3)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('You', 'Jij'), style: TextStyle(fontSize: 15, color: pal.ink2)),
                      const SizedBox(width: 12),
                      Text('$won – $lost', style: numStyle(30, color: pal.ink)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _name(x.name),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: pal.ink2),
                        ),
                      ),
                    ],
                  ),
                  if (draw > 0) Text(tr('$draw draw${draw == 1 ? '' : 's'}', '$draw keer gelijk'), style: TextStyle(fontSize: 12, color: pal.ink3)),
                  if (won + lost + draw == 0) Text(tr('No battles yet.', 'Nog geen battles.'), style: TextStyle(fontSize: 12.5, color: pal.ink3)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (f.battlesAvailable)
              current == null
                  ? FilledButton.icon(
                      icon: const Icon(Icons.sports_mma_rounded),
                      label: Text(tr('Challenge to a battle this week', 'Uitdagen voor een battle deze week')),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(context);
                        final m = await f.challenge(x.id);
                        // Verstuurd: het blad sluiten, zodat je op de Battles-kaart meteen "Wachten op …" ziet
                        if (m != null && context.mounted) nav.pop();
                        messenger.showSnackBar(SnackBar(content: Text(m ?? f.error ?? tr('That did not work.', 'Dat lukte niet.'))));
                      },
                    )
                  : Text(
                      current.accepted
                          ? tr('You have a battle going this week.', 'Jullie hebben deze week een battle.')
                          : (current.challengedByMe
                                ? tr('Challenge sent, waiting for an answer.', 'Uitdaging verstuurd, wachten op antwoord.')
                                : tr('They challenged you: accept it under Battles.', 'Die persoon daagde je uit: aanvaard het bij Battles.')),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: pal.ink2),
                    ),
            if (x.badges.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Badges',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink),
              ),
              const SizedBox(height: 8),
              ShowcaseRow(items: x.badges, size: 48, spacing: 16),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                tr('Past battles', 'Vorige battles'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink),
              ),
              for (final b in history) _ResultRow(battle: b),
            ],
            // Blokkeren en melden (verborgen zolang de server het niet kent)
            if (f.blockAvailable) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    key: const Key('sheet-report'),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(tr('Report', 'Melden')),
                    style: TextButton.styleFrom(foregroundColor: pal.ink2, minimumSize: const Size(48, 48)),
                    onPressed: () => showReportDialog(context, x.id, x.name),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const Key('sheet-block'),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: Text(tr('Block', 'Blokkeren')),
                    style: TextButton.styleFrom(foregroundColor: pal.high, minimumSize: const Size(48, 48)),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      // Geblokkeerd: het blad sluiten (die persoon staat niet meer in je lijst)
                      if (await confirmBlock(context, x.id, x.name, avatar: x.avatar)) nav.pop();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
