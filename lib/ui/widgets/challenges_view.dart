import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/challenges.dart';
import '../../state/app_state.dart';
import '../../state/challenge_days.dart';
import '../../sync/account.dart';
import '../../sync/challenges.dart';
import '../../sync/friends.dart';
import '../../sync/name_filter.dart';
import '../screens/friends_screen.dart' show SafetyMenu;
import '../theme.dart';
import 'avatar.dart';
import 'kit.dart';
import 'pro_widgets.dart';

String _name(String n) => n.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : n;

DateTime _today() {
  final n = logicalNow();
  return DateTime(n.year, n.month, n.day);
}

String _date(DateTime d) => DateFormat('EEE d MMM', appLocale).format(d);

/// Uitleg hoe een uitdaging werkt.
String get challengeRules => tr(
  'A challenge is a daily rule you keep up for a number of days, on your own or with friends. '
      'Your app checks each day against your diary. Friends only see whether you made the day, never what you ate.',
  'Een uitdaging is een regel per dag die je een aantal dagen volhoudt, alleen of met vrienden. '
      'Je app controleert elke dag in je dagboek. Vrienden zien alleen of je de dag haalde, nooit wat je at.',
);

/// Hoe vandaag ervoor staat, in één korte zin ("18 of 30 g today", "Done today").
String challengeTodayText(ChallengeProgress p) {
  final t = p.challenge.template;
  final today = _today();
  if (!p.challenge.startedOn(today)) {
    return p.challenge.start == today.plusDays(1)
        ? tr('Starts tomorrow', 'Begint morgen')
        : tr('Starts ${_date(p.challenge.start)}', 'Begint ${_date(p.challenge.start)}');
  }
  final status = p.statusOn(today);
  final input = p.todayInput ?? ChallengeDayInput.empty;
  final value = fmtChallengeAmount(t.nutrient, input.value);
  final target = challengeTarget(t, input);
  final goal = target == null ? null : fmtChallengeAmount(t.nutrient, target);
  switch (status) {
    case ChallengeDayStatus.met:
      return tr('Done today ($value)', 'Vandaag gehaald ($value)');
    case ChallengeDayStatus.missed:
      return t.rule == ChallengeRule.max
          ? tr('Over the limit today ($value of max $goal)', 'Vandaag over de grens ($value van max. $goal)')
          : tr('Not made today', 'Vandaag niet gehaald');
    case ChallengeDayStatus.open:
    case ChallengeDayStatus.upcoming:
    case null:
      if (!input.logged) return tr('Nothing logged yet today', 'Vandaag nog niets gelogd');
      if (t.rule == ChallengeRule.max) return tr('$value of max $goal so far', 'Tot nu toe $value van max. $goal');
      if (goal == null) return tr('No goal set for this nutrient', 'Geen doel ingesteld voor deze voedingsstof');
      return tr('$value of $goal today', 'Vandaag $value van $goal');
  }
}

/// Kleur en icoon van de stand van vandaag.
(IconData, Color) _statusLook(BuildContext context, ChallengeDayStatus? s) {
  final pal = context.pal;
  return switch (s) {
    ChallengeDayStatus.met => (Icons.check_circle_rounded, pal.ok),
    ChallengeDayStatus.missed => (Icons.cancel_rounded, pal.high),
    _ => (Icons.radio_button_unchecked_rounded, pal.ink3),
  };
}

/// Ring met het aantal gehaalde dagen tegenover wat je moet halen.
class ChallengeRing extends StatelessWidget {
  const ChallengeRing({super.key, required this.progress, this.size = 56});
  final ChallengeProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final color = progress.won ? pal.ok : (progress.lost ? pal.ink3 : pal.brand);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.ring,
              strokeWidth: 5,
              backgroundColor: pal.track,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${progress.met}', style: numStyle(size * 0.3, color: pal.ink, height: 1)),
              Text(
                '/${progress.need}',
                style: TextStyle(fontSize: size * 0.17, color: pal.ink3, height: 1.1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Uitdagingen op het tabblad Vrienden: uitnodigingen, lopende uitdagingen met ring, stand van vandaag en
/// ranglijst, en afgelopen uitdagingen met een badge. Werkt ook zonder account (alleen voor jezelf).
class ChallengesPanel extends StatelessWidget {
  const ChallengesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<Friends>();
    final s = context.watch<AppState>();
    return ListenableBuilder(
      listenable: f.challenges,
      builder: (context, _) {
        final c = f.challenges;
        final pal = context.pal;
        final today = _today();
        final all = s.challenges;
        final active = [
          for (final x in all)
            if (x.activeOn(today)) x,
        ]..sort((a, b) => a.start.compareTo(b.start));
        final finished = [
          for (final x in all)
            if (x.finishedOn(today)) x,
        ]..sort((a, b) => b.end.compareTo(a.end));
        final invites = c.invites;
        final signedIn = context.watch<Account>().signedIn;
        return Panel(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(
                tr('Challenges', 'Uitdagingen'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('How do challenges work?', 'Hoe werken uitdagingen?'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.info_outline_rounded, size: 18, color: pal.ink3),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: Text(tr('Challenges', 'Uitdagingen')),
                          content: Text(challengeRules),
                          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Close', 'Sluiten')))],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('New', 'Nieuw')),
                      onPressed: () => showNewChallengeSheet(context),
                    ),
                  ],
                ),
              ),
              if (c.error != null) Text(c.error!, style: TextStyle(fontSize: 13, color: pal.high)),
              if (signedIn && !c.groupAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr(
                      'Challenges with friends are not available yet. Challenges on your own work fine.',
                      'Uitdagingen met vrienden zijn nog niet beschikbaar. Alleen voor jezelf werkt al wel.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: pal.ink3),
                  ),
                ),
              for (final inv in invites) _InviteCard(invite: inv),
              for (final x in active) _ChallengeCard(key: ValueKey(x.id), challenge: x),
              if (active.isEmpty && invites.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr(
                      'No challenge running. Start one, like 30 days of 30 g fiber, on your own or with friends.',
                      'Geen lopende uitdaging. Start er een, zoals 30 dagen 30 g vezels, alleen of met vrienden.',
                    ),
                    style: TextStyle(fontSize: 13, color: pal.ink3),
                  ),
                ),
              if (finished.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr('Finished', 'Afgelopen'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.ink2),
                ),
                for (final x in finished.take(10)) _FinishedRow(key: ValueKey(x.id), challenge: x),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite});
  final RemoteChallenge invite;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = context.read<Friends>().challenges;
    final t = invite.template;
    final started = !invite.start.isAfter(_today());
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.brandSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('${_name(invite.invitedBy)} invites you to a challenge', '${_name(invite.invitedBy)} nodigt je uit voor een uitdaging'),
            style: TextStyle(fontSize: 12.5, color: pal.ink2),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                ),
              ),
              // De titel is vrije tekst van iemand anders: melden kan meteen hier (GP-7)
              if (c.reportAvailable)
                IconButton(
                  key: Key('challenge-report-invite-${invite.id}'),
                  tooltip: tr('Report this challenge', 'Deze uitdaging melden'),
                  icon: Icon(Icons.flag_outlined, size: 20, color: pal.ink3),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => showChallengeReportDialog(context, invite.id, t.name),
                ),
            ],
          ),
          Text(
            '${tr('Every day', 'Elke dag')} ${t.dailyRule} · ${t.durationText} · '
            '${started ? tr('started ${_date(invite.start)}', 'begonnen ${_date(invite.start)}') : tr('starts ${_date(invite.start)}', 'begint ${_date(invite.start)}')}',
            style: TextStyle(fontSize: 12.5, color: pal.ink3),
          ),
          const SizedBox(height: 6),
          AnswerButtons(onDecline: () => c.respond(invite, false), onAccept: () => c.respond(invite, true), acceptLabel: tr('Join', 'Meedoen')),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({super.key, required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = context.read<Friends>();
    final c = f.challenges;
    final p = c.progressOf(challenge);
    final today = _today();
    final day = p.dayNumber(today);
    final t = challenge.template;
    final status = p.statusOn(today);
    final (icon, color) = _statusLook(context, status);
    final hide = {for (final b in f.blocked) b.id};
    final board = challenge.group ? c.board(challenge, myName: f.name, hide: hide) : const <(int, ChallengeEntry)>[];
    final waiting = [
      for (final m in c.waitingFor(challenge))
        if (!hide.contains(m.id)) m,
    ];
    // Melden kan bij een groepsuitdaging van iemand anders (jouw eigen titel meld je niet)
    final canReport = challenge.group && !challenge.owner && challenge.remoteId != null && c.reportAvailable;
    final friends = [
      for (final x in f.list)
        if (x.state == FriendState.friend) x,
    ];
    final canInvite = c.canGroup && friends.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChallengeRing(progress: p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                    ),
                    Text(
                      [
                        if (day != null) tr('Day $day of ${t.days}', 'Dag $day van ${t.days}'),
                        if (t.need < t.days) tr('${t.need} days needed', '${t.need} dagen nodig'),
                        if (!challenge.group) tr('on your own', 'alleen'),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: pal.ink3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            challengeTodayText(p),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: pal.ink2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                key: Key('challenge-menu-${challenge.id}'),
                icon: Icon(Icons.more_vert_rounded, color: pal.ink3),
                itemBuilder: (_) => [
                  if (canInvite) PopupMenuItem(value: 0, child: Text(tr('Invite friends', 'Vrienden uitnodigen'))),
                  PopupMenuItem(value: 1, child: Text(tr('Stop challenge', 'Uitdaging stoppen'))),
                  if (canReport) PopupMenuItem(value: 2, child: Text(tr('Report challenge', 'Uitdaging melden'))),
                ],
                onSelected: (v) async {
                  if (v == 0) {
                    await showInviteSheet(context, challenge);
                    return;
                  }
                  if (v == 2) {
                    await showChallengeReportDialog(context, challenge.remoteId!, t.name);
                    return;
                  }
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(tr('Stop this challenge?', 'Deze uitdaging stoppen?')),
                      content: Text(
                        challenge.group
                            ? tr('You leave the challenge and drop off the leaderboard.', 'Je verlaat de uitdaging en verdwijnt van de ranglijst.')
                            : tr('The challenge disappears from your list.', 'De uitdaging verdwijnt uit je lijst.'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Cancel', 'Annuleren'))),
                        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Stop', 'Stoppen'))),
                      ],
                    ),
                  );
                  if (ok == true) await c.leave(challenge);
                },
              ),
            ],
          ),
          if (p.won && !p.finished)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Goal reached! Every extra day is a bonus.', 'Doel gehaald! Elke extra dag is mooi meegenomen.'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.ok),
              ),
            )
          else if (p.lost)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Out of reach this time, but every day you make still counts.', 'Deze keer niet meer haalbaar, maar elke gehaalde dag telt nog.'),
                style: TextStyle(fontSize: 12.5, color: pal.ink3),
              ),
            ),
          if (board.length > 1) ...[const SizedBox(height: 8), for (final (place, e) in board) _BoardRow(place: place, entry: e, days: t.days)],
          if (waiting.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Invited: ${waiting.map((m) => _name(m.name)).join(', ')}', 'Uitgenodigd: ${waiting.map((m) => _name(m.name)).join(', ')}'),
                style: TextStyle(fontSize: 12, color: pal.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.place, required this.entry, required this.days});
  final int place, days;
  final ChallengeEntry entry;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    const medals = [Color(0xFFE0A800), Color(0xFF9EA7B3), Color(0xFFB8733A)];
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: entry.me ? pal.brandSoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            // Een beker alleen bij minstens één gehaalde dag, niet bij 0 van 30 (S10)
            child: place <= 3 && entry.met > 0
                ? Icon(Icons.emoji_events_rounded, size: 18, color: medals[place - 1])
                : Text(
                    '$place',
                    textAlign: TextAlign.center,
                    style: numStyle(13, color: pal.ink3),
                  ),
          ),
          const SizedBox(width: 6),
          AvatarImage(avatar: entry.avatar, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.me ? (entry.name.isEmpty ? tr('You', 'Jij') : tr('${entry.name} (you)', '${entry.name} (jij)')) : _name(entry.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: entry.me ? FontWeight.w600 : FontWeight.w500, color: pal.ink),
                  ),
                ),
                // Supporter: jijzelf (Pro), of een vriend met het badge (deelnemers die geen vriend zijn, zien we niet)
                if (entry.me ? (proOf(context)?.supporter ?? false) : (context.watch<Friends?>()?.supporters.contains(entry.id) ?? false)) ...[
                  const SizedBox(width: 4),
                  const SupporterBadge(compact: true),
                ],
              ],
            ),
          ),
          Text(tr('${entry.met} of $days days', '${entry.met} van $days dagen'), style: TextStyle(fontSize: 12.5, color: pal.ink2)),
          // Blokkeren of melden, ook bij medespelers die geen vriend zijn (GP-7)
          if (!entry.me && (context.watch<Friends?>()?.blockAvailable ?? false))
            SafetyMenu(id: entry.id, name: entry.name, avatar: entry.avatar)
          else if (!entry.me)
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({super.key, required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = context.read<Friends>();
    final c = f.challenges;
    final p = c.progressOf(challenge);
    final t = challenge.template;
    final board = challenge.group ? c.board(challenge, myName: f.name) : const <(int, ChallengeEntry)>[];
    final myPlace = board.where((e) => e.$2.me).firstOrNull?.$1;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Tooltip(
            message: p.won ? tr('Challenge completed', 'Uitdaging voltooid') : tr('Challenge finished', 'Uitdaging afgelopen'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.won ? const Color(0x33E0A800) : pal.sunken),
              child: Icon(p.won ? Icons.workspace_premium_rounded : Icons.flag_outlined, size: 22, color: p.won ? const Color(0xFFE0A800) : pal.ink3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                Text(
                  [
                    p.won ? tr('Completed', 'Voltooid') : tr('Not completed', 'Niet gehaald'),
                    tr('${p.met} of ${t.days} days', '${p.met} van ${t.days} dagen'),
                    if (myPlace != null && board.length > 1) tr('place $myPlace of ${board.length}', 'plaats $myPlace van ${board.length}'),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: pal.ink3),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Remove from list', 'Uit de lijst halen'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: pal.ink3),
            onPressed: () => c.leave(challenge),
          ),
        ],
      ),
    );
  }
}

/// Een nieuwe uitdaging kiezen: een ingebouwd sjabloon of een eigen regel, wanneer hij begint en wie meedoet.
Future<void> showNewChallengeSheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _NewChallengeSheet());

class _NewChallengeSheet extends StatefulWidget {
  const _NewChallengeSheet();

  @override
  State<_NewChallengeSheet> createState() => _NewChallengeSheetState();
}

class _NewChallengeSheetState extends State<_NewChallengeSheet> {
  String _pick = builtinChallenges.first.id;
  String _nutrient = 'fiber';
  ChallengeRule _rule = ChallengeRule.min;
  final _amount = TextEditingController(text: '25');
  final _days = TextEditingController(text: '14');
  final _need = TextEditingController();
  final _title = TextEditingController();
  bool _tomorrow = false;
  final _invite = <String>{};
  bool _busy = false;

  /// Wat misliep bij het starten (bv. een titel die de server weigert), onder de knop.
  String? _error;

  /// Gestart: dan mag het blad dicht zonder te vragen.
  bool _done = false;

  /// Iets ingevuld of gekozen dat verloren gaat bij sluiten?
  bool get _dirty =>
      _invite.isNotEmpty ||
      (_pick == 'custom' &&
          (_nutrient != 'fiber' ||
              _rule != ChallengeRule.min ||
              _amount.text != '25' ||
              _days.text != '14' ||
              _need.text.isNotEmpty ||
              _title.text.isNotEmpty));

  /// Escape, de terugknop of naast het blad tikken met ingevulde velden: eerst vragen (S07).
  Future<void> _confirmClose() async {
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Discard this challenge?', 'Deze uitdaging weggooien?')),
        content: Text(tr('What you filled in will be lost.', 'Wat je invulde, gaat verloren.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Keep editing', 'Verder invullen'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Discard', 'Weggooien'))),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _done = true);
      nav.pop();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _days.dispose();
    _need.dispose();
    _title.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Het gekozen sjabloon, of null als de eigen regel nog niet klopt.
  ChallengeTemplate? get _template {
    if (_pick != 'custom') return builtinChallenges.firstWhere((t) => t.id == _pick);
    final days = _num(_days)?.round();
    final amount = _rule == ChallengeRule.goal ? 0.0 : _num(_amount);
    if (days == null || days < 1 || days > 90 || amount == null || amount < 0) return null;
    final need = _need.text.trim().isEmpty ? days : _num(_need)?.round();
    if (need == null || need < 1 || need > days) return null;
    final title = _title.text.trim();
    // Een titel met een geweigerd woord: niet starten (de server weigert hetzelfde, GP-8)
    if (textBlocked(title)) return null;
    return ChallengeTemplate(
      id: 'custom',
      nutrient: _nutrient,
      rule: _rule,
      amount: amount,
      days: days,
      need: need,
      title: title.isEmpty ? null : title,
    );
  }

  Future<void> _start() async {
    final t = _template;
    if (t == null) return;
    final c = context.read<Friends>().challenges;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final start = _today().plusDays(_tomorrow ? 1 : 0);
    setState(() => _busy = true);
    String? msg;
    if (_invite.isEmpty) {
      c.startSolo(t, start);
      msg = Challenges.startedText(start);
    } else {
      msg = await c.startGroup(t, start, _invite.toList());
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = msg == null ? c.error : null;
    });
    if (msg != null) {
      _done = true;
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = context.watch<Friends>();
    final signedIn = context.watch<Account>().signedIn;
    final friends = [
      for (final x in f.list)
        if (x.state == FriendState.friend) x,
    ];
    final t = _template;

    Widget option(String id, String title, String sub) => RadioListTile<String>(
      value: id,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.ink),
      ),
      subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: pal.ink3)),
    );

    return PopScope(
      canPop: _done || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                Text(
                  tr('New challenge', 'Nieuwe uitdaging'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.ink),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _pick,
                  onChanged: (v) => setState(() => _pick = v ?? _pick),
                  child: Column(
                    children: [
                      for (final b in builtinChallenges) option(b.id, b.name, '${tr('Every day', 'Elke dag')} ${b.dailyRule} · ${b.durationText}'),
                      option(
                        'custom',
                        tr('Your own challenge', 'Eigen uitdaging'),
                        tr('Pick a nutrient, a daily rule and how long', 'Kies een voedingsstof, een regel per dag en hoe lang'),
                      ),
                    ],
                  ),
                ),
                if (_pick == 'custom') ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _nutrient,
                    decoration: InputDecoration(labelText: tr('Nutrient', 'Voedingsstof'), isDense: true),
                    items: [for (final k in challengeNutrients) DropdownMenuItem(value: k, child: Text(challengeNutrientName(k)))],
                    onChanged: (v) => setState(() => _nutrient = v ?? _nutrient),
                  ),
                  const SizedBox(height: 10),
                  Segmented<ChallengeRule>(
                    height: 44,
                    items: [
                      (ChallengeRule.min, tr('At least', 'Minstens')),
                      (ChallengeRule.max, tr('At most', 'Hoogstens')),
                      (ChallengeRule.goal, tr('My goal', 'Mijn doel')),
                    ],
                    selected: _rule,
                    onChanged: (v) => setState(() => _rule = v),
                  ),
                  const SizedBox(height: 10),
                  // De hoeveelheid op een eigen regel, zodat geen enkel label afgekapt wordt ("Amount a d…": S07)
                  if (_rule != ChallengeRule.goal) ...[
                    TextField(
                      key: const Key('challenge-amount'),
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('Per day', 'Per dag'),
                        suffixText: _nutrient == vegKey ? tr('portions', 'porties') : challengeNutrientUnit(_nutrient),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _days,
                          keyboardType: TextInputType.number,
                          key: const Key('challenge-days'),
                          decoration: InputDecoration(labelText: tr('Days', 'Dagen'), isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _need,
                          keyboardType: TextInputType.number,
                          key: const Key('challenge-need'),
                          decoration: InputDecoration(labelText: tr('Needed', 'Nodig'), hintText: _days.text, isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _title,
                    maxLength: 60,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: tr('Name (optional)', 'Naam (mag leeg)'),
                      counterText: '',
                      isDense: true,
                      errorText: textBlocked(_title.text) ? titleNotAllowedText : null,
                      errorMaxLines: 3,
                    ),
                  ),
                  if (textBlocked(_title.text))
                    const SizedBox.shrink()
                  else if (t != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${tr('Every day', 'Elke dag')} ${t.dailyRule} · ${t.durationText}',
                        style: TextStyle(fontSize: 12.5, color: pal.ink2),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        tr('Fill in an amount and 1 to 90 days.', 'Vul een hoeveelheid en 1 tot 90 dagen in.'),
                        style: TextStyle(fontSize: 12.5, color: pal.high),
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  tr('Start', 'Begin'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink2),
                ),
                const SizedBox(height: 6),
                Segmented<bool>(
                  height: 44,
                  items: [(false, tr('Today', 'Vandaag')), (true, tr('Tomorrow', 'Morgen'))],
                  selected: _tomorrow,
                  onChanged: (v) => setState(() => _tomorrow = v),
                ),
                const SizedBox(height: 14),
                Text(
                  tr('Invite friends', 'Vrienden uitnodigen'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink2),
                ),
                const SizedBox(height: 6),
                if (!signedIn)
                  Text(
                    tr(
                      'Log in to do challenges with friends. On your own works without an account.',
                      'Log in om uitdagingen met vrienden te doen. Alleen voor jezelf kan zonder account.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: pal.ink3),
                  )
                else if (!f.challenges.groupAvailable)
                  Text(
                    tr('Challenges with friends are not available yet.', 'Uitdagingen met vrienden zijn nog niet beschikbaar.'),
                    style: TextStyle(fontSize: 12.5, color: pal.ink3),
                  )
                else if (friends.isEmpty)
                  Text(
                    tr('No friends yet. Add friends with their code first.', 'Nog geen vrienden. Voeg eerst vrienden toe met hun code.'),
                    style: TextStyle(fontSize: 12.5, color: pal.ink3),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final x in friends)
                        PillChip(
                          label: _name(x.name),
                          check: true,
                          selected: _invite.contains(x.id),
                          onTap: () => setState(() => _invite.contains(x.id) ? _invite.remove(x.id) : _invite.add(x.id)),
                        ),
                    ],
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: t == null || _busy ? null : _start,
                  child: Text(_invite.isEmpty ? tr('Start challenge', 'Uitdaging starten') : tr('Start and invite', 'Starten en uitnodigen')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      key: const Key('challenge-start-error'),
                      style: TextStyle(fontSize: 13, color: pal.high),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vrienden uitnodigen voor een lopende uitdaging.
Future<void> showInviteSheet(BuildContext context, Challenge challenge) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _InviteSheet(challenge: challenge),
);

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.challenge});
  final Challenge challenge;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _pick = <String>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = context.watch<Friends>();
    final c = f.challenges;
    final members = {for (final m in c.remoteById[widget.challenge.remoteId]?.members ?? const <RemoteMember>[]) m.id};
    final friends = [
      for (final x in f.list)
        if (x.state == FriendState.friend && !members.contains(x.id)) x,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Invite friends', 'Vrienden uitnodigen'),
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.ink),
            ),
            Text(widget.challenge.template.name, style: TextStyle(fontSize: 13, color: pal.ink3)),
            const SizedBox(height: 12),
            if (friends.isEmpty)
              Text(
                tr('All your friends are already invited.', 'Al je vrienden zijn al uitgenodigd.'),
                style: TextStyle(fontSize: 13, color: pal.ink3),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final x in friends)
                    PillChip(
                      label: _name(x.name),
                      check: true,
                      selected: _pick.contains(x.id),
                      onTap: () => setState(() => _pick.contains(x.id) ? _pick.remove(x.id) : _pick.add(x.id)),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _pick.isEmpty || _busy
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(context);
                      setState(() => _busy = true);
                      final msg = await c.invite(widget.challenge, _pick.toList());
                      if (!mounted) return;
                      setState(() => _busy = false);
                      nav.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            msg ??
                                c.error ??
                                tr('Challenges with friends are not available yet.', 'Uitdagingen met vrienden zijn nog niet beschikbaar.'),
                          ),
                        ),
                      );
                    },
              child: Text(tr('Send invitations', 'Uitnodigingen versturen')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Op Vandaag: per lopende uitdaging één regel met hoe vandaag ervoor staat. Leest alleen het dagboek, dus geen
/// account of verbinding nodig.
class ChallengeTodayStrip extends StatelessWidget {
  const ChallengeTodayStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final today = _today();
    final list = [
      for (final c in s.activeChallenges)
        if (c.startedOn(today)) c,
    ];
    if (list.isEmpty) return const SizedBox.shrink();
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in list.take(3))
            () {
              final p = s.challengeProgressOf(c);
              final (icon, color) = _statusLook(context, p.statusOn(today));
              return Semantics(
                label: '${c.template.name}: ${challengeTodayText(p)}',
                excludeSemantics: true,
                child: Container(
                  key: ValueKey('challenge-today-${c.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: pal.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${c.template.name} · ${challengeTodayText(p)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: pal.ink2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${p.met}/${p.need}', style: numStyle(12, color: pal.ink3)),
                    ],
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Een uitdaging melden om haar titel: bevestigen, eventueel een korte notitie, en de uitkomst als melding (GP-7).
Future<void> showChallengeReportDialog(BuildContext context, String remoteId, String title) async {
  final c = context.read<Friends>().challenges;
  final messenger = ScaffoldMessenger.of(context);
  final note = await showDialog<String>(
    context: context,
    builder: (_) => _ChallengeReportDialog(title: title),
  );
  if (note == null) return;
  final res = await c.report(remoteId, note: note);
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (res) {
        null => c.error ?? tr('That did not work.', 'Dat lukte niet.'),
        'not_found' => tr('This challenge no longer exists.', 'Deze uitdaging bestaat niet meer.'),
        final r => reportMessage(r),
      }),
    ),
  );
}

class _ChallengeReportDialog extends StatefulWidget {
  const _ChallengeReportDialog({required this.title});
  final String title;

  @override
  State<_ChallengeReportDialog> createState() => _ChallengeReportDialogState();
}

class _ChallengeReportDialogState extends State<_ChallengeReportDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AlertDialog(
      title: Text(tr('Report this challenge?', 'Deze uitdaging melden?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Report "${widget.title}" for an inappropriate name. We look at every report; the creator is not told who reported it.',
                'Meld "${widget.title}" om een ongepaste naam. We bekijken elke melding; wie de uitdaging maakte, hoort niet wie meldde.',
              ),
              style: TextStyle(fontSize: 13.5, color: pal.ink2),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('challenge-report-note'),
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(hintText: tr('Anything else we should know? (optional)', 'Nog iets dat we moeten weten? (optioneel)')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel', 'Annuleren'))),
        FilledButton(
          key: const Key('challenge-report-send'),
          onPressed: () => Navigator.pop(context, _note.text),
          child: Text(tr('Report', 'Melden')),
        ),
      ],
    );
  }
}
