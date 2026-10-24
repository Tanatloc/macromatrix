/// De roadmap: wat er misschien komt, en supporters (Pro) stemmen mee.
///
/// Iedereen met een account ziet de lijst met de status en het aantal stemmen. Alleen supporters stemmen, met
/// hoogstens [roadmapVotesMax] stemmen tegelijk op wat nog niet klaar is. Loopt Pro af, dan blijft je stem staan
/// maar telt ze niet mee (de server telt alleen stemmen van huidige supporters).
///
/// Staat de migratie 20261031000000_early_access.sql nog niet op de server, dan is [Roadmap.available] false en
/// toont het scherm vriendelijk dat het er nog niet is.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../i18n.dart';
import 'account.dart';
import 'challenges.dart' show isMissingTable;

/// Stemmen tegelijk per supporter. Moet gelijk zijn aan roadmap_vote() op de server.
const roadmapVotesMax = 3;

/// De roadmap bestaat (nog) niet op de server.
class RoadmapMissing implements Exception {
  const RoadmapMissing();
  @override
  String toString() => 'RoadmapMissing';
}

enum RoadmapStatus { idea, planned, building, done }

/// Een item op de roadmap.
@immutable
class RoadmapItem {
  const RoadmapItem({
    required this.id,
    required this.titleEn,
    this.titleNl = '',
    this.descEn = '',
    this.descNl = '',
    this.status = RoadmapStatus.idea,
    this.sort = 100,
    this.votes = 0,
    this.mine = false,
  });

  final String id, titleEn, titleNl, descEn, descNl;
  final RoadmapStatus status;
  final int sort;

  /// Stemmen van de huidige supporters.
  final int votes;

  /// Jij stemde erop.
  final bool mine;

  String get title => tr(titleEn, titleNl.isEmpty ? titleEn : titleNl);
  String get description => tr(descEn, descNl.isEmpty ? descEn : descNl);
  bool get done => status == RoadmapStatus.done;

  factory RoadmapItem.fromJson(Map j) => RoadmapItem(
    id: j['id'] as String,
    titleEn: j['title_en'] as String? ?? '',
    titleNl: j['title_nl'] as String? ?? '',
    descEn: j['desc_en'] as String? ?? '',
    descNl: j['desc_nl'] as String? ?? '',
    status: RoadmapStatus.values.asNameMap()[j['status']] ?? RoadmapStatus.idea,
    sort: (j['sort'] as num?)?.toInt() ?? 100,
    votes: (j['votes'] as num?)?.toInt() ?? 0,
    mine: j['mine'] == true,
  );

  RoadmapItem copyWith({int? votes, bool? mine}) => RoadmapItem(
    id: id,
    titleEn: titleEn,
    titleNl: titleNl,
    descEn: descEn,
    descNl: descNl,
    status: status,
    sort: sort,
    votes: votes ?? this.votes,
    mine: mine ?? this.mine,
  );
}

/// Antwoord van roadmap_vote, plus [failed] (geen verbinding of een storing) en [missing] (geen migratie).
enum VoteResult { ok, notPro, limit, closed, notFound, failed, missing }

VoteResult voteResultFrom(Object? s) => switch (s) {
  'ok' => VoteResult.ok,
  'not_pro' => VoteResult.notPro,
  'limit' => VoteResult.limit,
  'closed' => VoteResult.closed,
  'not_found' => VoteResult.notFound,
  _ => VoteResult.failed,
};

/// Wat de app van de server nodig heeft. Gooit [RoadmapMissing] als de migratie er nog niet staat.
abstract class RoadmapRemote {
  Future<List<RoadmapItem>> list();
  Future<VoteResult> vote(String item, bool on);
}

class SupabaseRoadmapRemote implements RoadmapRemote {
  SupabaseRoadmapRemote(this.client);
  final SupabaseClient client;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const RoadmapMissing();
      rethrow;
    }
  }

  @override
  Future<List<RoadmapItem>> list() => _guard(() async {
    final rows = await client.rpc('roadmap_list');
    return [
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['id'] is String) RoadmapItem.fromJson(r),
    ];
  });

  @override
  Future<VoteResult> vote(String item, bool on) =>
      _guard(() async => voteResultFrom(await client.rpc('roadmap_vote', params: {'p_item': item, 'p_on': on})));
}

class Roadmap extends ChangeNotifier {
  Roadmap(this.account, {RoadmapRemote? Function()? remote}) : _remoteFor = remote;

  final Account? account;
  final RoadmapRemote? Function()? _remoteFor;

  /// De server, alleen als je ingelogd bent (of de nagebootste in tests).
  RoadmapRemote? get remote {
    if (_remoteFor != null) return _remoteFor();
    final c = account?.client;
    return c == null || account?.user == null ? null : SupabaseRoadmapRemote(c);
  }

  List<RoadmapItem> items = const [];

  /// false zodra blijkt dat de server geen roadmap kent (migratie nog niet uitgevoerd).
  bool available = true;

  /// Het laden lukte niet (geen verbinding of een storing).
  bool failed = false;

  bool loading = false;

  /// Al eens geladen (om de eerste keer een laadteken te tonen).
  bool loaded = false;

  bool _disposed = false;

  /// Het scherm kan dicht zijn voor de server antwoordt.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Items waarvoor een stem onderweg is (de knop even uit).
  final Set<String> busy = {};

  /// Stemmen die je nog over hebt (stemmen op wat klaar is, tellen niet mee).
  int get votesLeft {
    final used = items.where((i) => i.mine && !i.done).length;
    return (roadmapVotesMax - used).clamp(0, roadmapVotesMax);
  }

  Future<void> refresh() async {
    final r = remote;
    if (r == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      items = await r.list();
      available = true;
      failed = false;
    } on RoadmapMissing {
      available = false;
    } catch (e) {
      debugPrint('roadmap: $e');
      failed = true;
    } finally {
      loading = false;
      loaded = true;
      notifyListeners();
    }
  }

  void _replace(RoadmapItem item) {
    items = [for (final i in items) i.id == item.id ? item : i];
  }

  /// Je stem op [item] aan of uit zetten. Meteen zichtbaar; lukt het niet, dan terug zoals het was.
  Future<VoteResult> toggle(RoadmapItem item) async {
    item = items.firstWhere((i) => i.id == item.id, orElse: () => item);
    final r = remote;
    if (r == null) return VoteResult.failed;
    if (busy.contains(item.id)) return VoteResult.failed;
    final on = !item.mine;
    // Lokaal al nakijken, zodat de teller niet even naar boven springt
    if (on && votesLeft <= 0) return VoteResult.limit;
    if (item.done) return VoteResult.closed;
    busy.add(item.id);
    _replace(item.copyWith(mine: on, votes: (item.votes + (on ? 1 : -1)).clamp(0, 1 << 30)));
    notifyListeners();
    VoteResult res;
    try {
      res = await r.vote(item.id, on);
    } on RoadmapMissing {
      available = false;
      res = VoteResult.missing;
    } catch (e) {
      debugPrint('roadmap vote: $e');
      res = VoteResult.failed;
    }
    busy.remove(item.id);
    if (res != VoteResult.ok) _replace(item);
    notifyListeners();
    // Het item is weg of al klaar: de lijst vers ophalen
    if (res == VoteResult.notFound || res == VoteResult.closed) await refresh();
    return res;
  }
}
