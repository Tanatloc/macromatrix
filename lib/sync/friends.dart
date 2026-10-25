/// Vrienden: elkaar toevoegen met een code en elkaars wekelijkse gemiddelde volledigheidsscore zien.
///
/// Gedeeld wordt alleen een zelfgekozen naam en per week één getal (0–100) met het aantal gelogde dagen. Wie de
/// functie nooit opent, deelt niets. De score van deze en vorige week wordt bijgewerkt zodra het dagboek verandert.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../nutrition/badges.dart';
import '../nutrition/supporter.dart';
import '../state/app_state.dart';
import 'account.dart';
import 'challenges.dart';
import 'name_filter.dart';
import 'pro.dart';
import 'supporter_tracker.dart';
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
    this.supporter = false,
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

  /// Heeft Pro en toont het Supporter-badge (alleen bij bevestigde vrienden, uit friend_list_v2).
  final bool supporter;

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
    supporter: r['supporter'] == true,
  );
}

/// Iemand die je geblokkeerd hebt (uit friend_blocked_list).
class BlockedUser {
  const BlockedUser({required this.id, required this.name, this.avatar});
  final String id, name;
  final String? avatar;

  factory BlockedUser.fromRow(Map<String, dynamic> r) =>
      BlockedUser(id: r['other'] as String, name: (r['name'] as String?) ?? '', avatar: r['avatar'] as String?);
}

/// Redenen om iemand te melden (zoals de server ze kent).
const reportReasons = ['spam', 'harassment', 'inappropriate', 'other'];

/// De uitleg bij een uitkomst van friend_report.
String reportMessage(String result) => switch (result) {
  'reported' => tr('Thanks. We received your report and will look into it.', 'Bedankt. We kregen je melding en bekijken ze.'),
  'limit' => tr('You sent a lot of reports today. Try again tomorrow.', 'Je stuurde vandaag al veel meldingen. Probeer morgen opnieuw.'),
  _ => tr('That did not work.', 'Dat lukte niet.'),
};

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

  Battle copyWith({bool? accepted}) => Battle(
    id: id,
    week: week,
    challengedByMe: challengedByMe,
    accepted: accepted ?? this.accepted,
    other: other,
    otherName: otherName,
    otherAvatar: otherAvatar,
    otherLevel: otherLevel,
    otherTitle: otherTitle,
    myPoints: myPoints,
    myMid: myMid,
    otherPoints: otherPoints,
    otherMid: otherMid,
  );

  /// Afgelopen: de week is voorbij (vanaf maandag erna).
  bool get finished => accepted && !DateTime.now().isBefore(DateTime(week.year, week.month, week.day + 7));
  bool get live => accepted && !finished && !DateTime.now().isBefore(week);
  bool get pending => !accepted && !DateTime.now().isAfter(DateTime(week.year, week.month, week.day + 7));

  /// Aanvaard voor een week die nog moet beginnen (uitgedaagd voor volgende week, SO-8).
  bool get upcoming => accepted && DateTime.now().isBefore(week);

  /// Voor volgende week (of later), nog niet voor deze.
  bool get nextWeek => week.isAfter(mondayOf(DateTime.now()));
  BattleResult get result => myPoints > otherPoints ? BattleResult.won : (myPoints < otherPoints ? BattleResult.lost : BattleResult.draw);

  /// Na woensdag achter en toch gewonnen.
  bool get comeback => finished && result == BattleResult.won && myMid < otherMid;
}

/// Instelling met het hoogste aantal vrienden ooit (voor de badge Sociaal).
const socialBestSetting = 'social_best';

/// Lokale instelling met je verstuurde battle-uitdagingen die nog open stonden.
const sentBattlesSetting = '_battles_sent';

/// Antwoord op "vriend toevoegen": de uitkomst van de server ([result] null bij een fout) en een korte uitleg.
class AddResult {
  const AddResult(this.result, this.message);
  final String? result;
  final String message;

  /// Gelukt (of niets meer te doen): het codeveld mag leeg. Bij een tikfout blijft de code staan (S12).
  bool get clearField => result != null && result != 'not_found' && result != 'self';
}

/// De uitleg bij een uitkomst van friend_add. [name]: de naam van de vriend, als we die kennen.
String addMessage(String result, {String name = ''}) => switch (result) {
  'requested' => tr(
    'Request sent. As soon as they accept, you will see each other\'s score.',
    'Verzoek verstuurd. Zodra die persoon het aanvaardt, zien jullie elkaars score.',
  ),
  'accepted' =>
    name.isEmpty ? tr('You are now friends.', 'Jullie zijn nu vrienden.') : tr('You and $name are now friends.', 'Jij en $name zijn nu vrienden.'),
  'friends' =>
    name.isEmpty
        ? tr('You are already friends.', 'Jullie zijn al vrienden.')
        : tr('You\'re already friends with $name.', 'Je bent al vrienden met $name.'),
  'already' => tr('You already sent this person a request.', 'Je hebt die persoon al een verzoek gestuurd.'),
  'self' => tr('That is your own code.', 'Dat is je eigen code.'),
  // Bewust vaag: ook bij een blokkade, zonder dat te verraden (SO-7)
  _ => tr('Could not add a friend with this code. Check the letters and numbers.', 'Met deze code kon geen vriend toegevoegd worden. Controleer de letters en cijfers.'),
};

/// Verstuurde vriendschapsverzoeken van vroeger ([before], id → naam) tegenover de lijst van nu: wie intussen je
/// vriend is, aanvaardde je verzoek (SO-5). Geeft de meldingen terug.
List<String> acceptedRequestNotices(Map<String, String> before, List<Friend> now) => [
  for (final x in now)
    if (x.state == FriendState.friend && before.containsKey(x.id))
      () {
        final n = x.name.isNotEmpty ? x.name : before[x.id]!;
        return n.isEmpty
            ? tr('Your friend request was accepted.', 'Je vriendschapsverzoek werd aanvaard.')
            : tr('$n accepted your friend request.', '$n aanvaardde je vriendschapsverzoek.');
      }(),
];

/// Vergelijkt je open battle-uitdagingen van vroeger ([before], id → naam) met de lijst van nu. Geeft de meldingen
/// terug (geweigerd of aanvaard) en de uitdagingen die nu nog open staan. Wat je zelf introk ([cancelled]) of wat
/// gewoon verliep, geeft geen melding.
(List<String>, Map<String, String>) sentBattleNotices(Map<String, String> before, List<Battle> battles, {Set<String> cancelled = const {}}) {
  final byId = {for (final b in battles) b.id: b};
  final messages = <String>[];
  String name(String n) => n.isEmpty ? tr('Your friend', 'Je vriend') : n;
  for (final MapEntry(key: id, value: n) in before.entries) {
    final b = byId[id];
    if (b == null) {
      if (!cancelled.contains(id)) {
        messages.add(tr('${name(n)} declined your battle challenge.', '${name(n)} weigerde je uitdaging voor een battle.'));
      }
    } else if (b.upcoming) {
      messages.add(
        tr(
          '${name(b.otherName)} accepted your challenge: the battle starts on Monday.',
          '${name(b.otherName)} aanvaardde je uitdaging: de battle begint maandag.',
        ),
      );
    } else if (b.accepted && !b.finished) {
      messages.add(
        tr('${name(b.otherName)} accepted your challenge: the battle is on!', '${name(b.otherName)} aanvaardde je uitdaging: de battle is begonnen!'),
      );
    }
  }
  return (
    messages,
    {
      for (final b in battles)
        if (b.challengedByMe && b.pending) b.id: b.otherName,
    },
  );
}

/// Maandag van de week van [d] (lokale tijd).
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

class Friends extends ChangeNotifier {
  /// [pro]: voor de supporterbadges en -titels (zonder telt alles als geen Pro).
  Friends(this.state, this.account, {this.pro}) {
    state.addListener(_changed);
    account.addListener(_changed);
    pro?.addListener(_changed);
    _supporter = pro == null ? null : SupporterTracker(state.user, account, pro!);
    _supporter?.update();
    // Verzoeken en levels van vrienden ook ophalen als het tabblad dicht is (voor het bolletje op het tabblad)
    _background = Timer.periodic(const Duration(minutes: 2), (_) => _loadQuietly());
  }

  Timer? _background;

  void _loadQuietly() {
    if (enabled && account.signedIn && !loading) unawaited(load().catchError((_) {}));
  }

  final AppState state;
  final Account account;
  final Pro? pro;
  SupporterTracker? _supporter;

  /// Loopt Pro nu?
  bool get proActive => pro?.isPro ?? false;

  /// Je Pro-geschiedenis (eerste Pro-datum, maanden, wat je verdiende).
  SupporterRecord get supporterRecord => supporterRecordOf(state.user);

  /// Supportertitels: Supporter zodra je Pro hebt of had, Stichter als dat in het eerste jaar was.
  bool get hadPro => proActive || supporterRecord.hadPro;
  bool get founder => isFounder(supporterRecord.firstPro ?? (proActive ? DateTime.now() : null));

  /// Titels die je nu mag kiezen.
  List<ProfileTitle> get availableTitlesNow => availableTitles(tiers, supporter: hadPro, founder: founder);

  /// Uitdagingen (alleen of met vrienden); ververst samen met de vriendenlijst.
  late final Challenges challenges = Challenges(state, account);

  /// Ingeschakeld zodra je de vriendenfunctie een keer geopend hebt (bewaard bij je account).
  bool get enabled => state.user.setting('friends')?['enabled'] == true;

  String? code;
  String name = '';
  List<Friend> list = const [];

  /// Vrienden met een Supporter-badge (op id), voor de ranglijsten van battles en uitdagingen.
  Set<String> get supporters => {
    for (final x in list)
      if (x.supporter && x.state == FriendState.friend) x.id,
  };

  /// Supporterranden van vrienden, tegenstanders en medespelers (id → rand), uit friend_frames. Leeg zolang de
  /// migratie supporter_frame.sql niet op de server staat ([framesAvailable] false).
  Map<String, AvatarFrame> frames = const {};
  bool framesAvailable = true;

  /// De rand van iemand anders (null = geen). Voor jezelf: [myFrame].
  AvatarFrame? frameFor(String? id) => id == null ? null : frames[id];

  /// Je eigen rand: alleen zolang Pro loopt.
  AvatarFrame? get myFrame => pro?.frame;

  bool loading = false;

  /// Elke laadbeurt krijgt een nummer: een oudere die later terugkomt (bv. van bij het openen van het tabblad)
  /// mag de lijst van een nieuwere niet overschrijven, anders staat een aanvaard verzoek er weer.
  int _loadGen = 0;
  String? error;

  Timer? _debounce;
  final _pushed = <String, String>{};

  String? _uid;

  void _changed() {
    _supporter?.update();
    final uid = account.user?.id;
    if (uid != _uid) {
      if (uid != null) Timer(const Duration(seconds: 2), _loadQuietly);
      _uid = uid;
      _pushed.clear();
      _sentAvatar = null;
      _sentLevel = null;
      _sentExtra = null;
      battles = const [];
      blocked = const [];
      frames = const {};
      framesAvailable = true;
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

  /// Wie je geblokkeerd hebt. [blockAvailable] is false zolang de migratie block_report.sql niet op de server
  /// staat: dan verbergt het scherm Blokkeren en Melden.
  List<BlockedUser> blocked = const [];
  bool blockAvailable = true;

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
  Battle? currentBattleWith(String friendId) => battleWith(friendId, mondayOf(DateTime.now()));

  /// Battle van volgende week met een vriend (aanvaard of nog niet).
  Battle? nextBattleWith(String friendId) => battleWith(friendId, mondayOf(DateTime.now()).plusDays(7));

  Battle? battleWith(String friendId, DateTime monday) =>
      battles.where((b) => b.other == friendId && b.week == monday && (b.accepted || b.pending)).firstOrNull;

  /// Hoogste aantal vrienden dat je ooit tegelijk had (bewaard bij je account). De badge Sociaal blijft zo staan
  /// als je een vriend verwijdert (S11).
  int get socialBest {
    final now = list.where((x) => x.state == FriendState.friend).length;
    final kept = (state.user.setting(socialBestSetting)?['n'] as num?)?.toInt() ?? 0;
    return now > kept ? now : kept;
  }

  /// Het hoogste aantal vrienden bewaren zodra het stijgt.
  void _keepSocialBest() {
    final now = list.where((x) => x.state == FriendState.friend).length;
    final kept = (state.user.setting(socialBestSetting)?['n'] as num?)?.toInt() ?? 0;
    if (now > kept) state.user.setSetting(socialBestSetting, {'n': now});
  }

  /// Je waarde en niveau per badgecategorie, met de supporterbadges (alleen met Pro; zie supporter.dart).
  Map<String, int> get badgeValuesNow => {
    ...badgeValues(days: state.dayStats, level: state.level, battles: record, friends: socialBest, scanned: state.scannedCount),
    ...supporterValues(
      active: proActive,
      record: supporterRecord,
      now: DateTime.now(),
      customFoods: proActive ? state.user.customFoodCount() : 0,
      offShared: proActive ? offSharedCount(state.user) : 0,
      recipes: proActive ? state.user.recipeCount() : 0,
    ),
  };
  Map<String, int> get tiers => badgeTiers(badgeValuesNow);

  /// De badges die vrienden zien: je eigen keuze (ook als die kleiner is dan 3), anders je hoogste 3 (S08).
  List<String> get showcase => showcaseOf(state.showcase, tiers, fill: !state.showcaseChosen);

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
    for (final m in [monday, monday.plusDays(-7)]) {
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
      // Een geweigerde naam (woordfilter op de server) krijgt een eigen, vriendelijke uitleg
      error =
          moderationMessage(e) ??
          tr('That did not work. Check your connection and try again.', 'Dat lukte niet. Controleer je verbinding en probeer opnieuw.');
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
      final week = {'p_week': dayKey(mondayOf(DateTime.now()))};
      List rows;
      try {
        // Met het Supporter-badge; een databank zonder de migratie pro.sql kent alleen friend_list
        rows = await client.rpc('friend_list_v2', params: week) as List;
      } on PostgrestException catch (e) {
        if (!isMissingTable(e)) rethrow;
        rows = await client.rpc('friend_list', params: week) as List;
      }
      if (gen != _loadGen) return;
      final sent = {
        for (final x in list)
          if (x.state == FriendState.outgoing) x.id: x.name,
      };
      list = [for (final r in rows) Friend.fromRow((r as Map).cast<String, dynamic>())];
      notices.addAll(acceptedRequestNotices(sent, list));
      _keepSocialBest();
      await _loadFrames(client, gen);
      try {
        final bl = await client.rpc('friend_blocked_list') as List;
        if (gen != _loadGen) return;
        blocked = [for (final r in bl) BlockedUser.fromRow((r as Map).cast<String, dynamic>())];
        blockAvailable = true;
      } on PostgrestException catch (e) {
        if (!isMissingTable(e)) rethrow;
        blocked = const [];
        blockAvailable = false;
      }
      try {
        final bs = await client.rpc('battle_list') as List;
        if (gen != _loadGen) return;
        battles = [for (final r in bs) Battle.fromRow((r as Map).cast<String, dynamic>())];
        battlesAvailable = true;
        _checkSentBattles();
        // Wat je hier al ziet, hoeft geen melding meer; en meldingen voor nieuwe uitdagingen inplannen
        final challenged = [
          for (final b in battles)
            if (b.pending && !b.challengedByMe) b.id,
        ];
        BattleNotify.markSeen(state, challenged);
        // Toestemming voor meldingen pas als iemand je uitdaagt (niet al bij je eerste start)
        if (challenged.isNotEmpty) unawaited(BattleNotify.askPermission());
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

  /// De supporterranden ophalen. Een server zonder de migratie (PGRST202): geen randen, geen foutmelding.
  Future<void> _loadFrames(SupabaseClient client, int gen) async {
    if (!framesAvailable) return;
    try {
      final rows = await client.rpc('friend_frames') as List;
      if (gen != _loadGen) return;
      frames = {
        for (final r in rows.cast<Map>())
          if (r['other'] is String && AvatarFrame.parse(r['frame']) != null) r['other'] as String: AvatarFrame.parse(r['frame'])!,
      };
    } catch (e) {
      // Randen zijn versiering: een storing hier mag de vriendenlijst niet tegenhouden (de vorige blijven staan)
      if (isMissingTable(e)) {
        frames = const {};
        framesAvailable = false;
      } else {
        debugPrint('vrienden randen: $e');
      }
    }
  }

  /// Je naam voor vrienden wijzigen. Een naam met een geweigerd woord gaat niet naar de server: dan staat de
  /// uitleg meteen in [error] (de server weigert hetzelfde, zie name_filter.dart).
  Future<void> setName(String n) async {
    final t = n.trim();
    if (textBlocked(t.length > 40 ? t.substring(0, 40) : t)) {
      error = nameNotAllowedText;
      notifyListeners();
      return;
    }
    await load(newName: n);
  }

  /// Korte meldingen voor het vriendenscherm (bv. een geweigerde battle). Het scherm toont ze één keer.
  final List<String> notices = [];

  /// Meldingen ophalen en wissen.
  List<String> takeNotices() {
    final out = [...notices];
    notices.clear();
    return out;
  }

  /// Battles die je zelf introk: daarvoor geen melding "geweigerd".
  final _cancelled = <String>{};

  /// Je verstuurde battle-uitdagingen die nog open stonden (id → naam), bewaard op dit toestel. Verdwijnt er een
  /// van de server zonder dat je ze introk, dan weigerde de ander; staat ze aanvaard, dan begint de battle (S06).
  void _checkSentBattles() {
    final before = {
      for (final e in ((state.user.setting(sentBattlesSetting)?['open'] as Map?) ?? const {}).entries) e.key as String: e.value as String,
    };
    final (messages, open) = sentBattleNotices(before, battles, cancelled: _cancelled);
    notices.addAll(messages);
    _cancelled.removeWhere((id) => !open.containsKey(id));
    if (!mapEquals(before, open)) state.user.setSetting(sentBattlesSetting, {'open': open});
  }

  /// Een vriend toevoegen met een code. Geeft het antwoord van de server terug ([AddResult.result] null bij een fout).
  Future<AddResult> add(String code) async {
    final client = account.client;
    if (client == null) return const AddResult(null, '');
    final friendsBefore = {
      for (final x in list)
        if (x.state == FriendState.friend) x.id,
    };
    final r = await _run(() async {
      try {
        // Met wie en of jullie al vrienden zijn; een databank zonder de migratie kent alleen friend_add
        final rows = await client.rpc('friend_add_v2', params: {'p_code': code}) as List;
        final row = (rows.first as Map).cast<String, dynamic>();
        return (row['result'] as String, row['other'] as String?);
      } on PostgrestException catch (e) {
        if (!isMissingTable(e)) rethrow;
        return (await client.rpc('friend_add', params: {'p_code': code}) as String, null);
      }
    });
    if (r == null) return const AddResult(null, '');
    await load();
    var (result, other) = r;
    final friendsNow = {
      for (final x in list)
        if (x.state == FriendState.friend) x.id,
    };
    // Oude server: die zegt "accepted" (of "already") ook als jullie al lang vrienden zijn (S05)
    if (other == null) {
      final fresh = friendsNow.difference(friendsBefore);
      if (result == 'accepted' && fresh.isEmpty) result = 'friends';
      if (result == 'already' && !list.any((x) => x.state == FriendState.outgoing)) result = 'friends';
      if (fresh.length == 1) other = fresh.first;
    }
    final name = list.where((x) => x.id == other).firstOrNull?.name ?? '';
    return AddResult(result, addMessage(result, name: name));
  }

  /// Een vriend uitdagen voor deze week, of met [nextWeek] voor volgende week (vanaf maandag; SO-8). Geeft een korte
  /// uitleg terug.
  Future<String?> challenge(String friendId, {bool nextWeek = false}) async {
    final monday = mondayOf(DateTime.now()).plusDays(nextWeek ? 7 : 0);
    final r = await _run(
      () async => await account.client!.rpc('battle_challenge', params: {'p_other': friendId, 'p_week': dayKey(monday)}) as String,
    );
    if (r == null) return null;
    await load();
    final name = list.where((x) => x.id == friendId).firstOrNull?.name ?? '';
    return switch (r) {
      'created' when nextWeek =>
        name.isEmpty
            ? tr('Challenge sent for next week. The battle starts on Monday if they accept.', 'Uitdaging voor volgende week verstuurd. De battle begint maandag als die persoon aanvaardt.')
            : tr(
                'Challenge sent to $name for next week. The battle starts on Monday if they accept.',
                'Uitdaging voor volgende week verstuurd naar $name. De battle begint maandag als die aanvaardt.',
              ),
      'created' =>
        name.isEmpty
            ? tr('Challenge sent. The battle starts as soon as they accept.', 'Uitdaging verstuurd. De battle begint zodra die persoon aanvaardt.')
            : tr(
                'Challenge sent to $name. The battle starts as soon as they accept.',
                'Uitdaging verstuurd naar $name. De battle begint zodra die aanvaardt.',
              ),
      'accepted' when nextWeek => tr(
        'They had already challenged you for next week: the battle starts on Monday.',
        'Die persoon had jou al uitgedaagd voor volgende week: de battle begint maandag.',
      ),
      'accepted' => tr('They had already challenged you: the battle is on!', 'Die persoon had jou al uitgedaagd: de battle is begonnen!'),
      'exists' when nextWeek => tr('You already have a battle with this friend next week.', 'Je hebt volgende week al een battle met deze vriend.'),
      'exists' => tr('You already have a battle with this friend this week.', 'Je hebt deze week al een battle met deze vriend.'),
      _ => tr('That did not work.', 'Dat lukte niet.'),
    };
  }

  Future<void> respondBattle(Battle b, bool accept) async {
    final ok = await _run(() async {
      await account.client!.rpc('battle_respond', params: {'p_id': b.id, 'p_accept': accept});
      return true;
    });
    // Meteen tonen: de uitnodiging verdwijnt, of de battle staat er (ook voor het herladen klaar is)
    if (ok == true) {
      battles = [
        for (final x in battles)
          if (x.id != b.id) x else if (accept) x.copyWith(accepted: true),
      ];
      notifyListeners();
    }
    await load();
  }

  Future<void> cancelBattle(Battle b) async {
    _cancelled.add(b.id);
    final ok = await _run(() async {
      await account.client!.rpc('battle_cancel', params: {'p_id': b.id});
      return true;
    });
    if (ok == true) {
      battles = [
        for (final x in battles)
          if (x.id != b.id) x,
      ];
      notifyListeners();
    }
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
          if (x.id != f.id) x else if (accept) Friend(id: x.id, name: x.name, state: FriendState.friend, avatar: x.avatar, level: x.level),
      ];
      notifyListeners();
    }
    await load();
  }

  Future<void> remove(Friend f) async {
    final ok = await _run(() async {
      await account.client!.rpc('friend_remove', params: {'p_other': f.id});
      return true;
    });
    // Meteen weg uit de lijst (verwijderde vriend of ingetrokken verzoek)
    if (ok == true) {
      list = [
        for (final x in list)
          if (x.id != f.id) x,
      ];
      notifyListeners();
    }
    await load();
  }

  /// Voert een functie voor blokkeren of melden uit. Kent de server ze niet (migratie nog niet uitgevoerd), dan
  /// verdwijnen de knoppen en geeft dit null terug.
  Future<T?> _blockRpc<T>(Future<T> Function() f) => _run<T?>(() async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (!isMissingTable(e)) rethrow;
      blockAvailable = false;
      return null;
    }
  });

  /// Iemand blokkeren: de vriendschap of het verzoek verdwijnt, net als open battles en uitnodigingen tussen jullie.
  /// Geeft true terug als het lukte.
  Future<bool> block(String id, {String name = '', String? avatar}) async {
    final ok = await _blockRpc(() async {
      await account.client!.rpc('friend_block', params: {'p_other': id});
      return true;
    });
    if (ok != true) return false;
    // Meteen tonen: weg uit de lijst en de battles, en bij de geblokkeerden
    list = [
      for (final x in list)
        if (x.id != id) x,
    ];
    battles = [
      for (final b in battles)
        if (b.other != id || b.finished) b,
    ];
    if (!blocked.any((b) => b.id == id)) blocked = [BlockedUser(id: id, name: name, avatar: avatar), ...blocked];
    notifyListeners();
    await load();
    return true;
  }

  /// Een blokkade opheffen. Vrienden worden jullie pas opnieuw met een nieuw verzoek.
  Future<bool> unblock(String id) async {
    final ok = await _blockRpc(() async {
      await account.client!.rpc('friend_unblock', params: {'p_other': id});
      return true;
    });
    if (ok != true) return false;
    blocked = [
      for (final b in blocked)
        if (b.id != id) b,
    ];
    notifyListeners();
    await load();
    return true;
  }

  /// Iemand melden met een reden uit [reportReasons] en een optionele notitie (max. 500 tekens).
  /// Geeft de uitkomst van de server terug (reported, limit, ...), of null bij een fout.
  Future<String?> report(String id, String reason, {String? note}) {
    final n = note?.trim() ?? '';
    return _blockRpc(
      () async => await account.client!.rpc(
        'friend_report',
        params: {'p_other': id, 'p_reason': reason, 'p_note': n.isEmpty ? null : (n.length > 500 ? n.substring(0, 500) : n)},
      ) as String,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _background?.cancel();
    challenges.dispose();
    state.removeListener(_changed);
    account.removeListener(_changed);
    pro?.removeListener(_changed);
    super.dispose();
  }
}
