import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../../sync/friends.dart';
import '../../sync/name_filter.dart';
import '../theme.dart';
import '../widgets/account_card.dart';
import '../../nutrition/badges.dart';
import '../widgets/avatar.dart';
import '../widgets/badges_view.dart';
import '../widgets/battles_view.dart';
import '../widgets/challenges_view.dart';
import '../widgets/kit.dart';
import '../widgets/pro_widgets.dart';
import '../../i18n.dart';
import '../../sync/pro.dart' show AvatarFrame;

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
  final _codeFocus = FocusNode();
  final _name = TextEditingController();
  bool _editingName = false;

  /// Uitleg onder het naamveld als de naam geweigerd werd (woordfilter, GP-8).
  String? _nameError;
  _Rank _rank = _Rank.week;
  Timer? _poll;

  /// Bezig met toevoegen (los van het laden van de lijst, zodat de knop niet grijs blijft hangen: S04).
  bool _adding = false;

  /// Uitleg onder het codeveld bij een foute of eigen code (geen melding over "Jouw code" heen: S12).
  String? _codeError;

  late final Friends _friends = context.read<Friends>();
  Friends get _f => _friends;

  @override
  void initState() {
    super.initState();
    _friends.addListener(_onFriends);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(FriendsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _poll?.cancel();
  }

  /// Nieuwe meldingen van Friends (bv. een geweigerde battle) tonen zolang het tabblad zichtbaar is.
  void _onFriends() {
    if (mounted && widget.active && _f.notices.isNotEmpty) _flushNotices();
  }

  void _flushNotices() {
    // Na de frame: een melding kan binnenkomen terwijl een ander scherm aan het opbouwen is
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      for (final m in _f.takeNotices()) {
        _say(m);
      }
    });
  }

  void _start() {
    // Niet tijdens het opbouwen laden: load() meldt meteen "bezig", en een melding midden in een bouwbeurt ging
    // verloren, waarna het scherm na eigen acties niet meer bijwerkte (S01)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startNow();
    });
  }

  void _startNow() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_f.loading) _f.load();
    });
    _flushNotices();
    _f.load().then((_) {
      if (mounted && _f.code != null && _f.name.isEmpty) setState(() => _editingName = true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _friends.removeListener(_onFriends);
    _code.dispose();
    _codeFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _say(String? m) {
    if (m != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add(Friends f) async {
    if (_code.text.trim().isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _codeError = null;
    });
    try {
      final r = await f.add(_code.text);
      if (!mounted) return;
      if (r.clearField) {
        _code.clear();
        _say(r.message);
      } else {
        // Tikfout of eigen code: de code blijft staan en is geselecteerd, zodat je één teken kan verbeteren
        setState(() => _codeError = r.result == null ? f.error : r.message);
        _code.selection = TextSelection(baseOffset: 0, extentOffset: _code.text.length);
        _codeFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _saveName(Friends f) async {
    if (_name.text.trim().isEmpty) return;
    // Meteen feedback, zonder op de server te wachten (die weigert hetzelfde)
    if (textBlocked(_name.text)) {
      setState(() => _nameError = nameNotAllowedText);
      return;
    }
    await f.setName(_name.text);
    if (!mounted) return;
    setState(() {
      _nameError = f.error == nameNotAllowedText ? f.error : null;
      if (f.error == null) _editingName = false;
    });
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
    // Ingelogd kan alleen met een geconfigureerde server
    if (!a.signedIn) {
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
          name: f.name,
          avatar: s.avatar,
          level: lvl.level,
          score: mine?.score,
          days: mine?.days,
          me: true,
          title: s.title,
          showcase: [for (final id in f.showcase) (id, f.tiers[id] ?? 1)],
          supporter: proOf(context)?.supporter ?? false,
          frame: myFrameOf(context),
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
            supporter: x.supporter,
            frame: f.frameFor(x.id),
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
                    frame: myFrameOf(context),
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
                                    errorText: _nameError,
                                    errorMaxLines: 3,
                                  ),
                                  onChanged: (_) {
                                    if (_nameError != null) setState(() => _nameError = null);
                                  },
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
                              if (proOf(context)?.supporter ?? false) ...[const SizedBox(width: 6), const SupporterBadge()],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            LevelAvatar(avatar: x.avatar, level: x.level, size: 40),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                x.name.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : x.name,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                              ),
                            ),
                            if (f.blockAvailable) SafetyMenu(id: x.id, name: x.name, avatar: x.avatar),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Grote, gescheiden knoppen: Weigeren is geen klein tekstlinkje naast Aanvaarden (S14)
                        AnswerButtons(onDecline: () => f.respond(x, false), onAccept: () => f.respond(x, true)),
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
                height: 44,
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
                  onBlock: r.friend == null || !f.blockAvailable
                      ? null
                      : () => confirmBlock(context, r.friend!.id, r.friend!.name, avatar: r.friend!.avatar),
                  onReport: r.friend == null || !f.blockAvailable ? null : () => showReportDialog(context, r.friend!.id, r.friend!.name),
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
                    'Week score: average Nutrient score of the days you logged this week. Friends never see what you eat.',
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
                    trailing: TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => f.remove(x),
                      child: Text(tr('Withdraw', 'Intrekken')),
                    ),
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
                            'Add me on MacroMatrix (macromatrix.eu) with my code ${f.code!.substring(0, 4)}-${f.code!.substring(4)}',
                            'Voeg me toe in MacroMatrix (macromatrix.eu) met mijn code ${f.code!.substring(0, 4)}-${f.code!.substring(4)}',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('friend-code'),
                      controller: _code,
                      focusNode: _codeFocus,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(hintText: tr('Your friend\'s code', 'Code van je vriend'), errorText: _codeError, errorMaxLines: 3),
                      onChanged: (_) {
                        if (_codeError != null) setState(() => _codeError = null);
                      },
                      onSubmitted: (_) => _add(f),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Luistert naar het veld zelf: zodra er een code staat, kan je tikken (S04)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _code,
                    builder: (context, v, _) => FilledButton(
                      key: const Key('friend-add'),
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                      onPressed: _adding || v.text.trim().isEmpty ? null : () => _add(f),
                      child: Text(tr('Add', 'Toevoegen')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Geblokkeerden onderaan, met Deblokkeren
        if (f.blockAvailable && f.blocked.isNotEmpty) ...[const SizedBox(height: 10), const BlockedPanel()],
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
    this.supporter = false,
    this.frame,
  });
  final String? title;

  /// Supporterrand rond de avatar.
  final AvatarFrame? frame;

  /// Supporter-badge naast de naam.
  final bool supporter;
  final List<(String, int)> showcase;
  final String name;
  final String? avatar;
  final int level;
  final int? score, days, prev;
  final bool me;
  final Friend? friend;
}

class RankTile extends StatelessWidget {
  const RankTile({super.key, required this.row, required this.place, required this.byLevel, this.onRemove, this.onTap, this.onBlock, this.onReport});

  // Beker alleen voor wie iets haalde: niet bij '–' of 0 (S10). Op level heeft iedereen een stand.
  bool get medal => place <= 3 && (byLevel || (row.score ?? 0) > 0);
  final RankRow row;
  final VoidCallback? onTap;
  final int place;
  final bool byLevel;
  final VoidCallback? onRemove;

  /// Blokkeren en melden in het menu (null: niet tonen, bv. als de server het nog niet kent).
  final VoidCallback? onBlock, onReport;

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
                child: medal
                    ? Icon(Icons.emoji_events_rounded, color: medals[place - 1], size: 22)
                    : Text(
                        '$place',
                        textAlign: TextAlign.center,
                        style: numStyle(15, color: pal.ink3),
                      ),
              ),
              const SizedBox(width: 6),
              LevelAvatar(avatar: r.avatar, level: r.level, size: 44, frame: r.frame),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            // Nog geen naam: gewoon "Jij", niet "Jij (jij)"
                            r.me ? (r.name.isEmpty ? tr('You', 'Jij') : tr('${r.name} (you)', '${r.name} (jij)')) : r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ),
                        if (showSupporterBadge(supporter: r.supporter, title: r.title))
                          const Padding(padding: EdgeInsets.only(left: 4, bottom: 2), child: SupporterBadge(compact: true)),
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
                  // Groot genoeg voor een dikke vinger, ook met de compacte dichtheid op een pc (S14)
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48), visualDensity: VisualDensity.standard),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 0, child: Text(tr('Remove friend', 'Vriend verwijderen'))),
                    if (onBlock != null) PopupMenuItem(value: 1, child: Text(tr('Block', 'Blokkeren'))),
                    if (onReport != null) PopupMenuItem(value: 2, child: Text(tr('Report', 'Melden'))),
                  ],
                  onSelected: (v) => switch (v) {
                    1 => onBlock!(),
                    2 => onReport!(),
                    _ => onRemove!(),
                  },
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

String _who(String name) => name.isEmpty ? tr('this person', 'deze persoon') : name;

/// Vragen of je iemand echt wil blokkeren, en dan blokkeren. Geeft true terug als het lukte.
Future<bool> confirmBlock(BuildContext context, String id, String name, {String? avatar}) async {
  final f = context.read<Friends>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Block ${_who(name)}?', '${name.isEmpty ? 'Deze persoon' : name} blokkeren?')),
      content: Text(
        tr(
          'You will no longer be friends, open battles and challenge invites between you disappear, and neither of you '
              'can send the other a friend request. They are not told that you blocked them. You can unblock them later.',
          'Jullie zijn dan geen vrienden meer, open battles en uitnodigingen voor uitdagingen tussen jullie verdwijnen, en '
              'niemand van jullie kan de ander nog een verzoek sturen. Die persoon krijgt geen bericht. Je kan later deblokkeren.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel', 'Annuleren'))),
        FilledButton(key: const Key('block-confirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr('Block', 'Blokkeren'))),
      ],
    ),
  );
  if (ok != true) return false;
  final done = await f.block(id, name: name, avatar: avatar);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        done
            ? tr('${name.isEmpty ? 'They are' : '$name is'} blocked.', '${_who(name)} is geblokkeerd.')
            : (f.error ?? tr('That did not work.', 'Dat lukte niet.')),
      ),
    ),
  );
  return done;
}

/// Iemand melden: een reden kiezen en eventueel een korte notitie.
Future<void> showReportDialog(BuildContext context, String id, String name) async {
  final f = context.read<Friends>();
  final messenger = ScaffoldMessenger.of(context);
  final r = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _ReportDialog(name: name),
  );
  if (r == null) return;
  final (reason, note) = r;
  final res = await f.report(id, reason, note: note);
  messenger.showSnackBar(SnackBar(content: Text(res == null ? (f.error ?? tr('That did not work.', 'Dat lukte niet.')) : reportMessage(res))));
}

/// Tekst bij een reden uit [reportReasons].
String reportReasonLabel(String reason) => switch (reason) {
  'spam' => tr('Spam', 'Spam'),
  'harassment' => tr('Harassment or bullying', 'Pesten of lastigvallen'),
  'inappropriate' => tr('Inappropriate name or photo', 'Ongepaste naam of foto'),
  _ => tr('Something else', 'Iets anders'),
};

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.name});
  final String name;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;
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
      title: Text(tr('Report ${_who(widget.name)}', '${widget.name.isEmpty ? 'Deze persoon' : widget.name} melden')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('What is wrong? We look at every report.', 'Wat is er mis? We bekijken elke melding.'),
              style: TextStyle(fontSize: 13.5, color: pal.ink2),
            ),
            const SizedBox(height: 6),
            for (final r in reportReasons)
              ListTile(
                key: Key('report-$r'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _reason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: _reason == r ? pal.brand : pal.ink3,
                ),
                title: Text(reportReasonLabel(r)),
                onTap: () => setState(() => _reason = r),
              ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('report-note'),
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
          key: const Key('report-send'),
          onPressed: _reason == null ? null : () => Navigator.pop(context, (_reason!, _note.text)),
          child: Text(tr('Report', 'Melden')),
        ),
      ],
    );
  }
}

/// Klein menu met Blokkeren en Melden (bv. bij een binnenkomend verzoek).
class SafetyMenu extends StatelessWidget {
  const SafetyMenu({super.key, required this.id, required this.name, this.avatar});
  final String id, name;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PopupMenuButton<int>(
      key: Key('safety-$id'),
      tooltip: tr('More', 'Meer'),
      icon: Icon(Icons.more_vert_rounded, color: pal.ink3),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48), visualDensity: VisualDensity.standard),
      itemBuilder: (_) => [
        PopupMenuItem(value: 1, child: Text(tr('Block', 'Blokkeren'))),
        PopupMenuItem(value: 2, child: Text(tr('Report', 'Melden'))),
      ],
      onSelected: (v) => v == 1 ? confirmBlock(context, id, name, avatar: avatar) : showReportDialog(context, id, name),
    );
  }
}

/// Wie je geblokkeerd hebt, met een knop om te deblokkeren.
class BlockedPanel extends StatelessWidget {
  const BlockedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<Friends>();
    final pal = context.pal;
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Blocked', 'Geblokkeerd')),
          Text(
            tr('You cannot send each other friend requests.', 'Jullie kunnen elkaar geen vriendschapsverzoek sturen.'),
            style: TextStyle(fontSize: 12.5, color: pal.ink3),
          ),
          for (final x in f.blocked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AvatarImage(avatar: x.avatar, size: 40),
              title: Text(x.name.isEmpty ? tr('Someone without a name', 'Iemand zonder naam') : x.name),
              trailing: TextButton(
                key: Key('unblock-${x.id}'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await f.unblock(x.id);
                  if (!ok) messenger.showSnackBar(SnackBar(content: Text(f.error ?? tr('That did not work.', 'Dat lukte niet.'))));
                },
                child: Text(tr('Unblock', 'Deblokkeren')),
              ),
            ),
        ],
      ),
    );
  }
}
