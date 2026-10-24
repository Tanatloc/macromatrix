/// Vrienden: elkaar toevoegen met een code en elkaars wekelijkse gemiddelde volledigheidsscore zien.
///
/// Gedeeld wordt alleen een zelfgekozen naam en per week één getal (0–100) met het aantal gelogde dagen. Wie de
/// functie nooit opent, deelt niets. De score van deze en vorige week wordt bijgewerkt zodra het dagboek verandert.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../nutrition/badges.dart';
import '../state/app_state.dart';
import 'account.dart';
import 'challenges.dart';
import '../i18n.dart';
import '../platform/battle_notify.dart';

enum FriendState { friend, incoming, outgoing }

class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.state,
    this.score,
    this.days,
    this.prevScore,
    this.prevDays,
    this.avatar,
    this.level = 1,
    this.title,
    this.badges = const [],
  });
  final String id;
  final String name;
  final String? avatar;
  final int level;

  /// Gekozen titel (sleutel) en showcase (categorie, niveau), alleen bij bevestigde vrienden.
  final String? title;
  final List<(String, int)> badges;
  final FriendState state;
  final int? score, days, prevScore, prevDays;

  factory Friend.fromRow(Map<String, dynamic> r) => Friend(
    id: r['other'] as String,
    name: (r['name'] as String?) ?? '',
    state: FriendState.values.byName(r['state'] as String),
    score: r['score'] as int?,
    days: r['days'] as int?,
    prevScore: r['prev_score'] as int?,
    prevDays: r['prev_days'] as int?,
    avatar: r['avatar'] as String?,
    level: (r['level'] as int?) ?? 1,
    title: r['title'] as String?,
    badges: decodeShowcase(r['badges'] as String?),
  );
}

enum BattleResult { won, lost, draw }

/// Een battle van één week (maandag tot en met zondag) tegen een vriend.
class Battle {
  const Battle({
    required this.id,
    required this.week,
    required this.challengedByMe,
    required this.accepted,
    required this.other,
    required this.otherName,
    this.otherAvatar,
    this.otherLevel = 1,
    this.otherTitle,
    this.myPoints = 0,
    this.myMid = 0,
    this.otherPoints = 0,
    this.otherMid = 0,
  });

  final String id;
  final DateTime week;
  final bool challengedByMe, accepted;
  final String other, otherName;
  final String? otherAvatar, otherTitle;
  final int otherLevel, myPoints, myMid, otherPoints, otherMid;

  factory Battle.fromRow(Map<String, dynamic> r) => Battle(
    id: r['id'] as String,
    week: DateTime.parse(r['week'] as String),
    challengedByMe: r['challenged_by_me'] as bool,
    accepted: r['accepted'] as bool,
    other: r['other'] as String,
    otherName: (r['other_name'] as String?) ?? '',
    otherAvatar: r['other_avatar'] as String?,
    otherLevel: (r['other_level'] as int?) ?? 1,
    otherTitle: r['other_title'] as String?,
    myPoints: (r['my_points'] as int?) ?? 0,
    myMid: (r['my_mid'] as int?) ?? 0,
    otherPoints: (r['other_points'] as int?) ?? 0,
    otherMid: (r['other_mid'] as int?) ?? 0,
  );

  /// Afgelopen: de week is voorbij (vanaf maandag erna).
  bool get finished => accepted && !DateTime.now().isBefore(DateTime(week.year, week.month, week.day + 7));
  bool get live => accepted && !finished && !DateTime.now().isBefore(week);
  bool get pending => !accepted && !DateTime.now().isAfter(DateTime(week.year, week.month, week.day + 7));
  BattleResult get result => myPoints > otherPoints ? BattleResult.won : (myPoints < otherPoints ? BattleResult.lost : BattleResult.draw);

  /// Na woensdag achter en toch gewonnen.
  bool get comeback => finished && result == BattleResult.won && myMid < otherMid;
}

/// Maandag van de week van [d] (lokale tijd).
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

class Friends extends ChangeNotifier {
  Friends(this.state, this.account) {
    state.addListener(_changed);
    account.addListener(_changed);
    // Verzoeken en levels van vrienden ook ophalen als het tabblad dicht is (voor het bolletje op het tabblad)
    _background = Timer.periodic(const Duration(minutes: 2), (_) => _loadQuietly());
  }

  Timer? _background;

  void _loadQuietly() {
    if (enabled && account.signedIn && !loading) unawaited(load().catchError((_) {}));
  }

  final AppState state;
  final Account account;

  /// Uitdagingen (alleen of met vrienden); ververst samen met de vriendenlijst.
  late final Challenges challenges = Challenges(state, account);

  /// Ingeschakeld zodra je de vriendenfunctie een keer geopend hebt (bewaard bij je account).
  bool get enabled => state.user.setting('friends')?['enabled'] == true;

  String? code;
  String name = '';
  List<Friend> list = const [];
  bool loading = false;

  /// Elke laadbeurt krijgt een nummer: een oudere die later terugkomt (bv. van bij het openen van het tabblad)
  /// mag de lijst van een nieuwere niet overschrijven, anders staat een aanvaard verzoek er weer.
  int _loadGen = 0;
  String? error;

  Timer? _debounce;
  final _pushed = <String, String>{};

  String? _uid;

  void _changed() {
    final uid = account.user?.id;
    if (uid != _uid) {
      if (uid != null) Timer(const Duration(seconds: 2), _loadQuietly);
      _uid = uid;
      _pushed.clear();
      _sentAvatar = null;
      _sentLevel = null;
      _sentExtra = null;
      battles = const [];
      code = null;
      name = '';
      list = const [];
    }
    if (!enabled || !account.signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => unawaited(pushScores().catchError((_) {})));
  }

  String? _sentAvatar;
  int? _sentLevel;
  String? _sentExtra;

  /// Battles (leeg als de databank ze nog niet kent).
  List<Battle> battles = const [];
  bool battlesAvailable = true;

  /// Afgelopen battles, oudste eerst, voor badges en rivaliteit.
  List<Battle> get finishedBattles => battles.where((b) => b.finished).toList()..sort((a, b) => a.week.compareTo(b.week));

  BattleRecord get record {
    final done = finishedBattles;
    var streak = 0, best = 0;
    for (final b in done) {
      streak = b.result == BattleResult.won ? streak + 1 : 0;
      if (streak > best) best = streak;
    }
    return BattleRecord(
      played: done.length,
      wins: done.where((b) => b.result == BattleResult.won).length,
      bestWinStreak: best,
      comebacks: done.where((b) => b.comeback).length,
    );
  }

  /// Onderlinge stand met een vriend: (gewonnen, verloren, gelijk).
  (int, int, int) rivalry(String friendId) {
    final mine = finishedBattles.where((b) => b.other == friendId);
    return (
      mine.where((b) => b.result == BattleResult.won).length,
      mine.where((b) => b.result == BattleResult.lost).length,
      mine.where((b) => b.result == BattleResult.draw).length,
    );
  }

  /// Battle van deze week met een vriend (lopend of nog niet aanvaard).
  Battle? currentBattleWith(String friendId) {
    final monday = mondayOf(DateTime.now());
    return battles.where((b) => b.other == friendId && b.week == monday && (b.accepted || b.pending)).firstOrNull;
  }

  /// Je waarde en niveau per badgecategorie.
  Map<String, int> get badgeValuesNow => badgeValues(
    days: state.dayStats,
    level: state.level,
    battles: record,
    friends: list.where((x) => x.state == FriendState.friend).length,
    scanned: state.scannedCount,
  );
  Map<String, int> get tiers => badgeTiers(badgeValuesNow);

  /// De 3 badges die vrienden zien.
  List<String> get showcase => showcaseOf(state.showcase, tiers);

  /// Titel en badges naar je vriendenprofiel (alleen als ze veranderden).
  Future<void> _pushExtra() async {
    final title = state.title;
    final b = encodeShowcase(showcase, tiers);
    final key = '$title|$b';
    if (key == _sentExtra) return;
    try {
      await account.client!.rpc('friend_extra', params: {'p_title': title, 'p_badges': b});
      _sentExtra = key;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
    }
  }

  /// Eigen naam (optioneel), avatar en level naar de server. Avatar en level alleen als ze veranderden.
  Future<List<Map<String, dynamic>>> _me([String? newName]) async {
    final client = account.client!;
    final avatar = state.avatar, level = state.level.level;
    final params = <String, dynamic>{
      'p_name': newName,
      'p_avatar': avatar == _sentAvatar ? null : (avatar ?? ''),
      // Level altijd meesturen: de server houdt het hoogste bij, zo herstelt een verkeerd level zich vanzelf
      'p_level': level,
    };
    List rows;
    try {
      rows = await client.rpc('friend_me', params: params) as List;
      _sentAvatar = avatar;
      _sentLevel = level;
    } on PostgrestException catch (e) {
      // Oudere databank zonder avatars en levels (migratie levels.sql nog niet uitgevoerd)
      if (e.code != 'PGRST202') rethrow;
      rows = await client.rpc('friend_me', params: {'p_name': newName}) as List;
    }
    return rows.cast<Map<String, dynamic>>();
  }

  /// Score van deze en vorige week naar de server (alleen wat veranderd is).
  Future<void> pushScores() async {
    final client = account.client;
    if (client == null || !account.signedIn) return;
    if (state.avatar != _sentAvatar || state.level.level != _sentLevel) await _me();
    await _pushExtra();
    final monday = mondayOf(DateTime.now());
    for (final m in [monday, monday.subtract(const Duration(days: 7))]) {
      final week = dayKey(m);
      final s = state.weekScore(m);
      final value = s == null ? '-' : '${s.score}/${s.days}/${state.battlePoints(m)}';
      if (_pushed[week] == value) continue;
      if (s == null) {
        await client.from('weekly_scores').delete().eq('week', week);
      } else {
        final row = {
          'user_id': account.user!.id,
          'week': week,
          'score': s.score,
          'days': s.days,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        final pts = state.battlePoints(m);
        try {
          await client.from('weekly_scores').upsert({...row, 'points': pts.points, 'mid_points': pts.mid}, onConflict: 'user_id,week');
        } on PostgrestException catch (e) {
          // Oudere databank zonder battles (migratie battles.sql nog niet uitgevoerd)
          if (e.code != 'PGRST204') rethrow;
          await client.from('weekly_scores').upsert(row, onConflict: 'user_id,week');
        }
      }
      _pushed[week] = value;
    }
  }

  Future<T?> _run<T>(Future<T> Function() f) async {
    error = null;
    try {
      return await f();
    } catch (e) {
      error = tr('That did not work. Check your connection and try again.', 'Dat lukte niet. Controleer je verbinding en probeer opnieuw.');
      debugPrint('vrienden: $e');
      return null;
    } finally {
      notifyListeners();
    }
  }

  bool _notifySetup = false;

  /// Eigen code en naam ophalen (maakt ze aan bij de eerste keer), score doorsturen en de lijst laden.
  Future<void> load({String? newName}) async {
    final client = account.client;
    if (client == null || !account.signedIn) return;
    loading = true;
    final gen = ++_loadGen;
    notifyListeners();
    await _run(() async {
      final me = (await _me(newName)).first;
      code = me['code'] as String;
      name = me['name'] as String;
      if (!enabled) state.user.setSetting('friends', {'enabled': true});
      await pushScores();
      final rows = await client.rpc('friend_list', params: {'p_week': dayKey(mondayOf(DateTime.now()))}) as List;
      if (gen != _loadGen) return;
      list = [for (final r in rows) Friend.fromRow((r as Map).cast<String, dynamic>())];
      try {
        final bs = await client.rpc('battle_list') as List;
        if (gen != _loadGen) return;
        battles = [for (final r in bs) Battle.fromRow((r as Map).cast<String, dynamic>())];
        battlesAvailable = true;
        // Wat je hier al ziet, hoeft geen melding meer; en meldingen voor nieuwe uitdagingen inplannen
        BattleNotify.markSeen(state, [
          for (final b in battles)
            if (b.pending && !b.challengedByMe) b.id,
        ]);
        if (!_notifySetup) {
          _notifySetup = true;
          unawaited(BattleNotify.setup(state, account));
        }
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        battlesAvailable = false;
      }
      // Badges kunnen veranderd zijn door afgelopen battles
      await _pushExtra();
    });
    // Uitdagingen vangen hun eigen fouten op (en een server zonder de migratie)
    await challenges.load();
    if (gen == _loadGen) loading = false;
    notifyListeners();
  }

  Future<void> setName(String n) => load(newName: n);

  /// Geeft een korte uitleg terug voor de gebruiker.
  Future<String?> add(String code) async {
    final client = account.client;
    if (client == null) return null;
    final r = await _run(() async => await client.rpc('friend_add', params: {'p_code': code}) as String);
    if (r == null) return null;
    await load();
    return switch (r) {
      'requested' => tr(
        'Request sent. As soon as they accept, you will see each other\'s score.',
        'Verzoek verstuurd. Zodra die persoon het aanvaardt, zien jullie elkaars score.',
      ),
      'accepted' => tr('You are now friends.', 'Jullie zijn nu vrienden.'),
      'already' => tr('You already sent this person a request.', 'Je hebt die persoon al een verzoek gestuurd.'),
      'self' => tr('That is your own code.', 'Dat is je eigen code.'),
      _ => tr(
        'No account found with that code. Check the letters and numbers.',
        'Geen account gevonden met die code. Controleer de letters en cijfers.',
      ),
    };
  }

  /// Een vriend uitdagen voor deze week. Geeft een korte uitleg terug.
  Future<String?> challenge(String friendId) async {
    final r = await _run(
      () async => await account.client!.rpc('battle_challenge', params: {'p_other': friendId, 'p_week': dayKey(mondayOf(DateTime.now()))}) as String,
    );
    if (r == null) return null;
    await load();
    return switch (r) {
      'created' => tr(
        'Challenge sent. The battle starts as soon as they accept.',
        'Uitdaging verstuurd. De battle begint zodra die persoon aanvaardt.',
      ),
      'accepted' => tr('They had already challenged you: the battle is on!', 'Die persoon had jou al uitgedaagd: de battle is begonnen!'),
      'exists' => tr('You already have a battle with this friend this week.', 'Je hebt deze week al een battle met deze vriend.'),
      _ => tr('That did not work.', 'Dat lukte niet.'),
    };
  }

  Future<void> respondBattle(Battle b, bool accept) async {
    await _run(() => account.client!.rpc('battle_respond', params: {'p_id': b.id, 'p_accept': accept}));
    await load();
  }

  Future<void> cancelBattle(Battle b) async {
    await _run(() => account.client!.rpc('battle_cancel', params: {'p_id': b.id}));
    await load();
  }

  Future<void> respond(Friend f, bool accept) async {
    final ok = await _run(() async {
      await account.client!.rpc('friend_respond', params: {'p_other': f.id, 'p_accept': accept});
      return true;
    });
    // Meteen tonen: het verzoek verdwijnt en een aanvaarde vriend staat in de lijst, ook voor het herladen klaar is
    if (ok == true) {
      list = [
        for (final x in list)
          if (x.id != f.id)
            x
          else if (accept)
            Friend(id: x.id, name: x.name, state: FriendState.friend, avatar: x.avatar, level: x.level),
      ];
      notifyListeners();
    }
    await load();
  }

  Future<void> remove(Friend f) async {
    await _run(() => account.client!.rpc('friend_remove', params: {'p_other': f.id}));
    await load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _background?.cancel();
    challenges.dispose();
    state.removeListener(_changed);
    account.removeListener(_changed);
    super.dispose();
  }
}
