/// Uitdagingen met vrienden: de server-kant.
///
/// Een uitdaging alleen voor jezelf staat enkel in de app (state/challenge_days.dart) en werkt zonder account. Voor
/// een groepsuitdaging komt er een rij op de server met de deelnemers; elke app zet daar per dag alleen of de dag
/// gehaald is (ja/nee), zoals battles alleen punten doorsturen. Nooit wat je at.
///
/// Staat de migratie 20261025000000_challenges.sql nog niet op de server, dan is [Challenges.groupAvailable]
/// false en werken uitdagingen alleen voor jezelf, zonder fouten.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../i18n.dart';
import '../nutrition/challenges.dart';
import '../state/app_state.dart';
import '../state/challenge_days.dart';
import 'account.dart';
import 'api.dart';
import 'name_filter.dart';

/// De tabellen of functies voor uitdagingen bestaan (nog) niet op de server.
class ChallengesMissing implements Exception {
  const ChallengesMissing();
  @override
  String toString() => 'ChallengesMissing';
}

/// Foutcodes van PostgREST en Postgres voor een ontbrekende functie of tabel.
const _missingCodes = {'PGRST202', 'PGRST205', '42P01', '42883'};

bool isMissingTable(Object e) => e is PostgrestException && _missingCodes.contains(e.code);

/// De server kent challenge_report nog niet (migratie moderation.sql niet uitgevoerd). Apart van
/// [ChallengesMissing]: uitdagingen zelf werken dan gewoon.
class ChallengeReportMissing implements Exception {
  const ChallengeReportMissing();
  @override
  String toString() => 'ChallengeReportMissing';
}

/// Een deelnemer zoals de server hem kent.
class RemoteMember {
  const RemoteMember({required this.id, required this.name, this.avatar, this.level = 1, this.accepted = true, this.met = 0, this.me = false});
  final String id, name;
  final String? avatar;
  final int level, met;
  final bool accepted, me;
}

/// Een groepsuitdaging zoals de server ze kent (meegedaan of uitgenodigd).
class RemoteChallenge {
  const RemoteChallenge({
    required this.id,
    required this.template,
    required this.start,
    this.ownerIsMe = false,
    this.invitedBy = '',
    this.members = const [],
  });
  final String id;
  final ChallengeTemplate template;
  final DateTime start;
  final bool ownerIsMe;
  final String invitedBy;
  final List<RemoteMember> members;

  RemoteMember? get me => members.where((m) => m.me).firstOrNull;
  bool get joined => me?.accepted ?? false;

  /// Uit de rijen van challenge_list (één rij per deelnemer).
  static List<RemoteChallenge> fromRows(List<Map<String, dynamic>> rows) {
    final byId = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byId.putIfAbsent(r['id'] as String, () => []).add(r);
    }
    return [
      for (final e in byId.entries)
        () {
          final r = e.value.first;
          final days = (r['days'] as num).toInt();
          return RemoteChallenge(
            id: e.key,
            template: ChallengeTemplate(
              id: (r['template'] as String?) ?? 'custom',
              title: r['title'] as String?,
              nutrient: r['nutrient'] as String,
              rule: switch (r['rule']) {
                'max' => ChallengeRule.max,
                'goal' => ChallengeRule.goal,
                _ => ChallengeRule.min,
              },
              amount: (r['amount'] as num?)?.toDouble() ?? 0,
              days: days,
              need: ((r['need'] as num?)?.toInt() ?? days).clamp(1, days),
            ),
            start: DateTime.parse(r['start_day'] as String),
            ownerIsMe: r['owner_is_me'] == true,
            invitedBy: (r['invited_by_name'] as String?) ?? '',
            members: [
              for (final m in e.value)
                if (m['member'] != null)
                  RemoteMember(
                    id: m['member'] as String,
                    name: (m['member_name'] as String?) ?? '',
                    avatar: m['member_avatar'] as String?,
                    level: (m['member_level'] as num?)?.toInt() ?? 1,
                    accepted: m['member_accepted'] == true,
                    met: (m['member_met'] as num?)?.toInt() ?? 0,
                    me: m['is_me'] == true,
                  ),
            ],
          );
        }(),
    ];
  }
}

/// Wat de app van de server nodig heeft. Gooit [ChallengesMissing] als de migratie er nog niet staat.
abstract class ChallengeRemote {
  Future<String> create(ChallengeTemplate t, DateTime start, List<String> invite);
  Future<String> invite(String id, String friend);
  Future<void> respond(String id, bool accept);
  Future<void> leave(String id);
  Future<List<RemoteChallenge>> list();

  /// Per dag gehaald of niet (dag als "jjjj-mm-dd").
  Future<void> pushDays(String id, Map<String, bool> days);

  /// Een uitdaging melden om haar titel. Geeft reported, limit of not_found; gooit [ChallengeReportMissing] als de
  /// server de functie niet kent.
  Future<String> report(String id, String? note);
}

String _rule(ChallengeRule r) => r.name;

class SupabaseChallengeRemote implements ChallengeRemote {
  SupabaseChallengeRemote(this.client, this.uid);
  final Rpc client;
  final String uid;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const ChallengesMissing();
      rethrow;
    }
  }

  @override
  Future<String> create(ChallengeTemplate t, DateTime start, List<String> invite) => _guard(
    () async => await client.rpc(
      'challenge_create',
      params: {
        'p_template': t.id,
        'p_title': t.title,
        'p_nutrient': t.nutrient,
        'p_rule': _rule(t.rule),
        'p_amount': t.amount,
        'p_days': t.days,
        'p_need': t.need,
        'p_start': dayKey(start),
        'p_invite': invite,
      },
    ) as String,
  );

  @override
  Future<String> invite(String id, String friend) =>
      _guard(() async => await client.rpc('challenge_invite', params: {'p_id': id, 'p_other': friend}) as String);

  @override
  Future<void> respond(String id, bool accept) => _guard(() => client.rpc('challenge_respond', params: {'p_id': id, 'p_accept': accept}));

  @override
  Future<void> leave(String id) => _guard(() => client.rpc('challenge_leave', params: {'p_id': id}));

  @override
  Future<List<RemoteChallenge>> list() => _guard(() async {
    final rows = await client.rpc('challenge_list') as List;
    return RemoteChallenge.fromRows([for (final r in rows) (r as Map).cast<String, dynamic>()]);
  });

  @override
  Future<String> report(String id, String? note) async {
    try {
      return await client.rpc('challenge_report', params: {'p_id': id, 'p_note': note}) as String;
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const ChallengeReportMissing();
      rethrow;
    }
  }

  @override
  Future<void> pushDays(String id, Map<String, bool> days) => _guard(() async {
    if (days.isEmpty) return;
    final c = client;
    // Supabase: rechtstreeks in de tabel (RLS); de eigen server heeft er een functie voor
    if (c is! SupabaseRpc) return c.rpc('challenge_days_put', params: {'p_challenge': id, 'p_days': days});
    final now = DateTime.now().toUtc().toIso8601String();
    await c.client.from('challenge_days').upsert([
      for (final e in days.entries) {'challenge_id': id, 'user_id': uid, 'day': e.key, 'met': e.value, 'updated_at': now},
    ], onConflict: 'challenge_id,user_id,day');
  });
}

/// Uitdagingen: lokaal (alleen jij) en, met een account, samen met vrienden.
class Challenges extends ChangeNotifier {
  Challenges(this.state, this.account, {ChallengeRemote? Function()? remote}) : _remoteFor = remote {
    state.addListener(_changed);
    account.addListener(_changed);
  }

  final AppState state;
  final Account account;
  final ChallengeRemote? Function()? _remoteFor;

  /// De server, alleen als je ingelogd bent (of de nagebootste in tests).
  ChallengeRemote? get remote {
    if (_remoteFor != null) return _remoteFor();
    final c = account.api, u = account.user;
    return c == null || u == null ? null : SupabaseChallengeRemote(c, u.id);
  }

  /// false zodra blijkt dat de server geen uitdagingen kent (migratie nog niet uitgevoerd).
  bool groupAvailable = true;

  /// false zodra blijkt dat de server challenge_report niet kent: dan verdwijnt "Uitdaging melden".
  bool reportAvailable = true;

  /// Samen met vrienden kan: ingelogd en de server kent uitdagingen.
  bool get canGroup => remote != null && groupAvailable;

  /// Groepsuitdagingen van de server, op id.
  Map<String, RemoteChallenge> remoteById = const {};

  /// Uitnodigingen die je nog niet aanvaard of geweigerd hebt.
  List<RemoteChallenge> get invites => [
    for (final r in remoteById.values)
      if (!r.joined && !Challenge(id: '', template: r.template, start: r.start).finishedOn(logicalNow())) r,
  ];

  bool loading = false;
  String? error;

  Timer? _debounce;
  final _pushed = <String, bool>{};

  String? _uid;

  void _changed() {
    final uid = account.user?.id;
    if (uid != _uid) {
      // Ander account: niets van het vorige onthouden
      _uid = uid;
      _pushed.clear();
      remoteById = const {};
      groupAvailable = true;
      reportAvailable = true;
    }
    if (remote == null || !groupAvailable) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => unawaited(pushDays().catchError((_) {})));
  }

  /// Werkt [f] uit; een ontbrekende tabel zet de groepsfunctie stil, andere fouten worden een korte melding.
  Future<T?> _run<T>(Future<T> Function() f) async {
    error = null;
    try {
      return await f();
    } on ChallengesMissing {
      groupAvailable = false;
      return null;
    } catch (e) {
      // Een geweigerde titel (woordfilter op de server) krijgt een eigen, vriendelijke uitleg
      error =
          moderationMessage(e) ??
          tr('That did not work. Check your connection and try again.', 'Dat lukte niet. Controleer je verbinding en probeer opnieuw.');
      debugPrint('uitdagingen: $e');
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Stand van een uitdaging (uit je eigen dagboek).
  ChallengeProgress progressOf(Challenge c) => state.challengeProgressOf(c);

  /// Ranglijst: jij (met je stand van nu) en de andere deelnemers zoals de server ze kent. [hide]: wie je
  /// geblokkeerd hebt (de server laat ze ook weg, maar zo verdwijnen ze meteen).
  List<(int, ChallengeEntry)> board(Challenge c, {String myName = '', Set<String> hide = const {}}) {
    final mine = progressOf(c).met;
    final r = c.remoteId == null ? null : remoteById[c.remoteId];
    return rankChallenge([
      ChallengeEntry(id: 'me', name: myName, avatar: state.avatar, level: state.level.level, met: mine, me: true),
      for (final m in r?.members ?? const <RemoteMember>[])
        if (!m.me && !hide.contains(m.id)) ChallengeEntry(id: m.id, name: m.name, avatar: m.avatar, level: m.level, met: m.met, accepted: m.accepted),
    ]);
  }

  /// Een groepsuitdaging (of uitnodiging) melden om haar titel, met een optionele notitie (max. 500 tekens).
  /// Geeft de uitkomst van de server (reported, limit, not_found), of null bij een fout of zonder de functie.
  Future<String?> report(String remoteId, {String? note}) async {
    final r = remote;
    if (r == null || !reportAvailable) return null;
    final n = note?.trim() ?? '';
    error = null;
    try {
      return await r.report(remoteId, n.isEmpty ? null : (n.length > 500 ? n.substring(0, 500) : n));
    } on ChallengeReportMissing {
      reportAvailable = false;
      return null;
    } catch (e) {
      error = tr('That did not work. Check your connection and try again.', 'Dat lukte niet. Controleer je verbinding en probeer opnieuw.');
      debugPrint('uitdaging melden: $e');
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Uitgenodigd maar nog niet aanvaard.
  List<RemoteMember> waitingFor(Challenge c) => [
    for (final m in remoteById[c.remoteId]?.members ?? const <RemoteMember>[])
      if (!m.accepted) m,
  ];

  /// Alleen voor jezelf: meteen klaar, zonder server.
  Challenge startSolo(ChallengeTemplate t, DateTime start) {
    final c = state.addChallenge(t, start);
    notifyListeners();
    return c;
  }

  /// Korte bevestiging na het starten: een uitdaging die pas later begint, is nog niet "gestart" (S13).
  static String startedText(DateTime start, {bool invited = false}) {
    final n = logicalNow();
    final later = start.isAfter(DateTime(n.year, n.month, n.day));
    if (!later) {
      return invited
          ? tr('Challenge started. Your friends get an invitation.', 'Uitdaging gestart. Je vrienden krijgen een uitnodiging.')
          : tr('Challenge started. Good luck!', 'Uitdaging gestart. Succes!');
    }
    return invited
        ? tr('Challenge set for tomorrow. Your friends get an invitation.', 'Uitdaging staat klaar voor morgen. Je vrienden krijgen een uitnodiging.')
        : tr('Challenge set for tomorrow. Good luck!', 'Uitdaging staat klaar voor morgen. Succes!');
  }

  /// Met vrienden: op de server aanmaken en meteen uitnodigen. Kent de server geen uitdagingen, dan wordt het een
  /// uitdaging voor jezelf. Geeft een korte uitleg terug.
  Future<String?> startGroup(ChallengeTemplate t, DateTime start, List<String> friends) async {
    final r = remote;
    if (r == null || !groupAvailable) {
      startSolo(t, start);
      return tr('Challenge started. Inviting friends is not available yet.', 'Uitdaging gestart. Vrienden uitnodigen kan nog niet.');
    }
    final id = await _run(() => r.create(t, start, friends));
    if (id == null) {
      if (!groupAvailable) {
        startSolo(t, start);
        return tr('Challenge started. Inviting friends is not available yet.', 'Uitdaging gestart. Vrienden uitnodigen kan nog niet.');
      }
      return null;
    }
    state.addChallenge(t, start, remoteId: id);
    await load();
    return startedText(start, invited: friends.isNotEmpty);
  }

  /// Vrienden uitnodigen. Een uitdaging voor jezelf wordt dan een groepsuitdaging (zelfde start en regel).
  Future<String?> invite(Challenge c, List<String> friends) async {
    final r = remote;
    if (r == null || !groupAvailable || friends.isEmpty) return null;
    var id = c.remoteId;
    if (id == null) {
      id = await _run(() => r.create(c.template, c.start, friends));
      if (id == null) return null;
      state.updateChallenge(c.copyWith(remoteId: id));
    } else {
      final remoteId = id;
      final results = await _run(() async => [for (final f in friends) await r.invite(remoteId, f)]);
      if (results == null) return null;
    }
    await load();
    return friends.length == 1 ? tr('Invitation sent.', 'Uitnodiging verstuurd.') : tr('Invitations sent.', 'Uitnodigingen verstuurd.');
  }

  /// Een uitnodiging aannemen (komt bij je uitdagingen) of weigeren.
  Future<void> respond(RemoteChallenge inv, bool accept) async {
    final r = remote;
    if (r == null) return;
    final ok = await _run(() async {
      await r.respond(inv.id, accept);
      return true;
    });
    if (ok == true && accept && !state.challenges.any((c) => c.remoteId == inv.id)) {
      state.addChallenge(inv.template, inv.start, remoteId: inv.id, owner: false);
    }
    await load();
  }

  /// Stoppen (lopend) of uit de lijst halen (afgelopen). Bij een groepsuitdaging ook op de server.
  Future<void> leave(Challenge c) async {
    final r = remote;
    if (c.remoteId != null && r != null && groupAvailable) {
      final ok = await _run(() async {
        await r.leave(c.remoteId!);
        return true;
      });
      if (ok != true && groupAvailable) return;
    }
    state.removeChallenge(c.id);
    notifyListeners();
  }

  /// Uitnodigingen en de stand van je vrienden ophalen, en je eigen dagen doorsturen.
  Future<void> load() async {
    final r = remote;
    if (r == null || loading) return;
    loading = true;
    try {
      final list = await _run(r.list);
      if (list == null) return;
      remoteById = {for (final x in list) x.id: x};
      _reconcile(list);
      await _run(pushDays);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Lokale lijst gelijk trekken met de server: een groepsuitdaging die je op een ander toestel aanvaardde komt
  /// erbij; een die op de server niet meer bestaat (of die je verliet) gaat weg.
  void _reconcile(List<RemoteChallenge> list) {
    final local = state.challenges;
    final joined = {
      for (final x in list)
        if (x.joined) x.id: x,
    };
    var changed = false;
    final next = <Challenge>[];
    for (final c in local) {
      if (c.remoteId != null && !joined.containsKey(c.remoteId)) {
        // Afgelopen uitdagingen verdwijnen na 60 dagen van de server: lokaal houden we ze (met hun badge)
        if (c.finishedOn(logicalNow())) {
          next.add(c);
        } else {
          changed = true;
        }
        continue;
      }
      next.add(c);
    }
    if (changed) state.saveChallenges(next);
    for (final x in joined.values) {
      if (!local.any((c) => c.remoteId == x.id)) state.addChallenge(x.template, x.start, remoteId: x.id, owner: x.ownerIsMe);
    }
  }

  /// Per groepsuitdaging de dagen tot en met vandaag doorsturen (alleen wat veranderde).
  Future<void> pushDays() async {
    final r = remote;
    if (r == null || !groupAvailable) return;
    for (final c in state.challenges) {
      final id = c.remoteId;
      if (id == null) continue;
      final rc = remoteById[id];
      if (rc != null && !rc.joined) continue;
      final days = state.challengeProgressOf(c).pushable();
      final changed = {
        for (final e in days.entries)
          if (_pushed['$id|${e.key}'] != e.value) e.key: e.value,
      };
      if (changed.isEmpty) continue;
      try {
        await r.pushDays(id, changed);
      } on ChallengesMissing {
        groupAvailable = false;
        notifyListeners();
        return;
      }
      for (final e in changed.entries) {
        _pushed['$id|${e.key}'] = e.value;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    state.removeListener(_changed);
    account.removeListener(_changed);
    super.dispose();
  }
}
