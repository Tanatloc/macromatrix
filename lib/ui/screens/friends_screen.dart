import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../../sync/friends.dart';
import '../theme.dart';
import '../widgets/account_card.dart';
import '../../nutrition/badges.dart';
import '../widgets/avatar.dart';
import '../widgets/badges_view.dart';
import '../widgets/battles_view.dart';
import '../widgets/challenges_view.dart';
import '../widgets/kit.dart';
import '../../i18n.dart';

enum _Rank { week, level }

/// Vrienden (eigen tabblad): jij, verzoeken, een ranglijst op weekscore of level, en iemand toevoegen met een code.
/// Zolang het tabblad zichtbaar is ([active]), worden de gegevens van je vrienden elke 20 seconden ververst.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.active = true});
  final bool active;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _editingName = false;
  _Rank _rank = _Rank.week;
  Timer? _poll;

  Friends get _f => context.read<Friends>();

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(FriendsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _poll?.cancel();
  }

  void _start() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_f.loading) _f.load();
    });
    _f.load().then((_) {
      if (mounted && _f.code != null && _f.name.isEmpty) setState(() => _editingName = true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _say(String? m) {
    if (m != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add(Friends f) async {
    if (_code.text.trim().isEmpty) return;
    final m = await f.add(_code.text);
    if (f.error == null) _code.clear();
    _say(m);
  }

  Future<void> _saveName(Friends f) async {
    if (_name.text.trim().isEmpty) return;
    await f.setName(_name.text);
    if (f.error == null) setState(() => _editingName = false);
  }

  Future<void> _remove(Friends f, Friend x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Remove ${x.name.isEmpty ? 'this friend' : x.name}?', '${x.name.isEmpty ? 'Deze vriend' : x.name} verwijderen?')),
        content: Text(tr('You will no longer see each other\'s score and level.', 'Jullie zien elkaars score en level dan niet meer.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Remove', 'Verwijderen'))),
        ],
      ),
    );
    if (ok == true) await f.remove(x);
  }

  @override
  Widget build(BuildContext context) {
    final f = context.watch<Friends>();
    final a = context.watch<Account>();
    final s = context.watch<AppState>();
    final pal = context.pal;

    // Op een pc in twee kolommen ([right] naast [left]), op een gsm onder elkaar
    final List<Widget> body;
    var right = const <Widget>[];
    if (!Account.configured || !a.signedIn) {
      body = [
        Panel(
          shadow: false,
          child: Text(
            tr(
              'Log in to add friends and compare your scores and levels.',
              'Log in om vrienden toe te voegen en jullie scores en levels te vergelijken.',
            ),
            style: TextStyle(color: pal.ink2),
          ),
        ),
        if (Account.configured) ...[const SizedBox(height: 12), const AccountCard()],
        // Uitdagingen voor jezelf werken zonder account
        const SizedBox(height: 12),
        const ChallengesPanel(),
      ];
    } else if (f.code == null) {
      body = [
        if (f.loading)
          const Center(
            child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
          )
        else ...[
          Text(f.error ?? tr('Friends are not available yet.', 'Vrienden zijn nog niet beschikbaar.'), style: TextStyle(color: pal.ink2)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: f.load, child: Text(tr('Try again', 'Opnieuw proberen'))),
        ],
      ];
    } else {
      final friends = f.list.where((x) => x.state == FriendState.friend).toList();
      final incoming = f.list.where((x) => x.state == FriendState.incoming).toList();
      final outgoing = f.list.where((x) => x.state == FriendState.outgoing).toList();
      final mine = s.weekScore(mondayOf(DateTime.now()));
      final lvl = s.level;

      // Ranglijst: jij en je vrienden samen
      final rows = <RankRow>[
        RankRow(
          name: f.name.isEmpty ? tr('You', 'Jij') : f.name,
          avatar: s.avatar,
          level: lvl.level,
          score: mine?.score,
          days: mine?.days,
          me: true,
          title: s.title,
          showcase: [for (final id in f.showcase) (id, f.tiers[id] ?? 1)],
        ),
        for (final x in friends)
          RankRow(
            name: x.name.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : x.name,
            avatar: x.avatar,
            level: x.level,
            score: x.score,
            days: x.days,
            prev: x.prevScore,
            friend: x,
            title: x.title,
            showcase: x.badges,
          ),
      ];
      rows.sort(
        (p, q) => _rank == _Rank.week
            ? ((q.score ?? -1).compareTo(p.score ?? -1) != 0 ? (q.score ?? -1).compareTo(p.score ?? -1) : q.level.compareTo(p.level))
            : (q.level.compareTo(p.level) != 0 ? q.level.compareTo(p.level) : (q.score ?? -1).compareTo(p.score ?? -1)),
      );

      body = [
        if (f.error != null) ...[Text(f.error!, style: TextStyle(color: pal.high)), const SizedBox(height: 10)],
        // Jij
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LevelAvatar(
                    avatar: s.avatar,
                    level: lvl.level,
                    size: 64,
                    onTap: () async {
                      final v = await pickAvatar(context, s.avatar);
                      if (v != null) s.setAvatar(v);
                    },
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_editingName)
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _name,
                                  autofocus: f.name.isNotEmpty,
                                  maxLength: 40,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    hintText: tr('Your name for friends', 'Je naam voor vrienden'),
                                    counterText: '',
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => _saveName(f),
                                ),
                              ),
                              IconButton(tooltip: tr('Save', 'Bewaren'), icon: Icon(Icons.check_rounded), onPressed: () => _saveName(f)),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  f.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.ink),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('Change name', 'Naam wijzigen'),
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.edit_outlined, size: 18, color: pal.ink3),
                                onPressed: () => setState(() {
                                  _name.text = f.name;
                                  _editingName = true;
                                }),
                              ),
                            ],
                          ),
                        Text(
                          'Level ${lvl.level}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: levelColor(lvl.level)),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: lvl.progress, minHeight: 6, backgroundColor: pal.track, color: levelColor(lvl.level)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stat(label: tr('Week score', 'Weekscore'), value: mine == null ? '–' : '${mine.score}'),
                  ),
                  Expanded(
                    child: _Stat(label: tr('Days this week', 'Dagen deze week'), value: '${mine?.days ?? 0}'),
                  ),
                  Expanded(
                    child: _Stat(label: tr('Streak', 'Reeks'), value: '${s.streak.current}'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const BattlesPanel(),
        const SizedBox(height: 10),
        const ChallengesPanel(),
        // Verzoeken
        if (incoming.isNotEmpty) ...[
          const SizedBox(height: 10),
          Panel(
            shadow: false,
            color: pal.brandSoft,
            borderColor: pal.brandSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelTitle(
                  incoming.length == 1
                      ? tr('1 friend request', '1 vriendschapsverzoek')
                      : tr('${incoming.length} friend requests', '${incoming.length} vriendschapsverzoeken'),
                ),
                for (final x in incoming)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        LevelAvatar(avatar: x.avatar, level: x.level, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            x.name.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : x.name,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ),
                        TextButton(onPressed: () => f.respond(x, false), child: Text(tr('Decline', 'Weigeren'))),
                        FilledButton(onPressed: () => f.respond(x, true), child: Text(tr('Accept', 'Aanvaarden'))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ];
      right = [
        // Ranglijst
        Panel(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(tr('Leaderboard', 'Ranglijst')),
              const SizedBox(height: 8),
              Segmented<_Rank>(
                height: 32,
                items: [(_Rank.week, tr('This week', 'Deze week')), (_Rank.level, 'Level')],
                selected: _rank,
                onChanged: (v) => setState(() => _rank = v),
              ),
              const SizedBox(height: 6),
              for (final (i, r) in rows.indexed)
                RankTile(
                  row: r,
                  place: i + 1,
                  byLevel: _rank == _Rank.level,
                  onTap: r.friend == null ? null : () => showFriendSheet(context, r.friend!),
                  onRemove: r.friend == null ? null : () => _remove(f, r.friend!),
                ),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(
                      'No friends yet. Share your code below and compare every week who eats most completely.',
                      'Nog geen vrienden. Deel je code hieronder en vergelijk elke week wie het volledigst eet.',
                    ),
                    style: TextStyle(fontSize: 13, color: pal.ink3),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(
                    'Week score: average Voedingsscore of the days you logged this week. Friends never see what you eat.',
                    'Weekscore: gemiddelde Voedingsscore van de dagen die je deze week logde. Vrienden zien nooit wat je eet.',
                  ),
                  style: TextStyle(fontSize: 11.5, color: pal.ink3),
                ),
              ),
            ],
          ),
        ),
        if (outgoing.isNotEmpty) ...[
          const SizedBox(height: 10),
          Panel(
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelTitle(tr('Sent', 'Verstuurd')),
                for (final x in outgoing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AvatarImage(avatar: x.avatar, size: 40),
                    title: Text(x.name.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : x.name),
                    subtitle: Text(tr('waiting for acceptance', 'wacht op aanvaarding')),
                    trailing: TextButton(onPressed: () => f.remove(x), child: Text(tr('Withdraw', 'Intrekken'))),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        // Toevoegen
        Panel(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(tr('Add a friend', 'Vriend toevoegen')),
              const SizedBox(height: 4),
              Text(tr('Your code', 'Jouw code'), style: TextStyle(fontSize: 13, color: pal.ink2)),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      '${f.code!.substring(0, 4)}-${f.code!.substring(4)}',
                      style: numStyle(24).copyWith(letterSpacing: 2, color: pal.ink),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(tr('Copy', 'Kopiëren')),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: tr(
                            'Add me on MacroMatrix (app.divinenet.online) with my code ${f.code!.substring(0, 4)}-${f.code!.substring(4)}',
                            'Voeg me toe in MacroMatrix (app.divinenet.online) met mijn code ${f.code!.substring(0, 4)}-${f.code!.substring(4)}',
                          ),
                        ),
                      );
                      _say(tr('Code copied: paste it in a message to your friend', 'Code gekopieerd: plak ze in een bericht naar je vriend'));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(hintText: tr('Your friend\'s code', 'Code van je vriend')),
                      onSubmitted: (_) => _add(f),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: f.loading ? null : () => _add(f), child: Text(tr('Add', 'Toevoegen'))),
                ],
              ),
            ],
          ),
        ),
      ];
    }

    // Op een pc even breed als Vandaag en Profiel, zodat de kop niet verspringt tussen de tabbladen
    final maxWidth = isDesktop(context) ? wideMaxWidth : 760.0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: f.load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Narrow(
                maxWidth: maxWidth,
                child: PageHeader(eyebrow: tr('Together', 'Samen'), title: tr('Friends', 'Vrienden')),
              ),
              Narrow(
                maxWidth: maxWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SplitColumns(left: body, right: right),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: numStyle(20)),
        Text(label, style: TextStyle(fontSize: 11.5, color: pal.ink3)),
      ],
    );
  }
}

class RankRow {
  RankRow({
    required this.name,
    required this.avatar,
    required this.level,
    this.score,
    this.days,
    this.prev,
    this.me = false,
    this.friend,
    this.title,
    this.showcase = const [],
  });
  final String? title;
  final List<(String, int)> showcase;
  final String name;
  final String? avatar;
  final int level;
  final int? score, days, prev;
  final bool me;
  final Friend? friend;
}

class RankTile extends StatelessWidget {
  const RankTile({super.key, required this.row, required this.place, required this.byLevel, this.onRemove, this.onTap});
  final RankRow row;
  final VoidCallback? onTap;
  final int place;
  final bool byLevel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = row;
    const medals = [Color(0xFFE0A800), Color(0xFF9EA7B3), Color(0xFFB8733A)];
    final trend = (r.score != null && r.prev != null) ? r.score! - r.prev! : null;
    final sub = byLevel
        ? (r.score == null ? tr('nothing logged this week', 'deze week nog niets gelogd') : tr('week score ${r.score}', 'weekscore ${r.score}'))
        : (r.days == null
              ? tr('nothing logged this week', 'deze week nog niets gelogd')
              : tr(
                  '${r.days} ${r.days == 1 ? 'day' : 'days'} logged · level ${r.level}',
                  '${r.days} ${r.days == 1 ? 'dag' : 'dagen'} gelogd · level ${r.level}',
                ));
    final titleName = titleById[r.title]?.name;
    return Material(
      color: r.me ? pal.brandSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: place <= 3
                    ? Icon(Icons.emoji_events_rounded, color: medals[place - 1], size: 22)
                    : Text(
                        '$place',
                        textAlign: TextAlign.center,
                        style: numStyle(15, color: pal.ink3),
                      ),
              ),
              const SizedBox(width: 6),
              LevelAvatar(avatar: r.avatar, level: r.level, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.me ? tr('${r.name} (you)', '${r.name} (jij)') : r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ),
                        for (final (id, tier) in r.showcase)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 2),
                            child: BadgeIcon(category: id, tier: tier, size: 18),
                          ),
                      ],
                    ),
                    if (titleName != null)
                      Text(
                        titleName,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: levelColor(r.level)),
                      ),
                    Text(sub, style: TextStyle(fontSize: 12, color: pal.ink3)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(byLevel ? 'Lv ${r.level}' : (r.score?.toString() ?? '–'), style: numStyle(20, color: pal.ink)),
                  if (!byLevel && trend != null && trend != 0)
                    Text(
                      '${trend > 0 ? '▲' : '▼'} ${trend.abs()}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: trend > 0 ? pal.ok : pal.low),
                    ),
                ],
              ),
              if (onRemove != null)
                PopupMenuButton<int>(
                  icon: Icon(Icons.more_vert_rounded, color: pal.ink3),
                  itemBuilder: (_) => [PopupMenuItem(value: 0, child: Text(tr('Remove friend', 'Vriend verwijderen')))],
                  onSelected: (_) => onRemove!(),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
