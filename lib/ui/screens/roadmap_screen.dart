import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../sync/account.dart';
import '../../sync/features.dart';
import '../../sync/roadmap.dart';
import '../theme.dart';
import '../widgets/feature_gate.dart';
import '../widgets/kit.dart';
import '../widgets/pro_widgets.dart';

void openRoadmapScreen(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoadmapScreen()));

/// "What's next": wat er misschien komt, met de status en het aantal stemmen. Supporters stemmen mee (hoogstens
/// [roadmapVotesMax] tegelijk); de rest ziet een rustige regel met een link naar Pro. Daarboven wat nu in vroege
/// toegang is, met de dag waarop het voor iedereen komt.
class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key, this.roadmap});

  /// Voor tests; anders gemaakt met het account uit de Provider.
  final Roadmap? roadmap;

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  late final Roadmap _roadmap = widget.roadmap ?? Roadmap(context.read<Account?>());

  @override
  void initState() {
    super.initState();
    _roadmap.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _roadmap.refresh();
      featuresOf(context, listen: false)?.refresh();
    });
  }

  @override
  void dispose() {
    _roadmap.removeListener(_changed);
    if (widget.roadmap == null) _roadmap.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(RoadmapItem item) async {
    final res = await _roadmap.toggle(item);
    if (!mounted) return;
    final msg = switch (res) {
      VoteResult.ok => null,
      VoteResult.limit => tr(
        'You have used all $roadmapVotesMax votes. Take one back to vote on this.',
        'Je gebruikt al je $roadmapVotesMax stemmen. Neem er een terug om hierop te stemmen.',
      ),
      VoteResult.closed => tr('This one is done, so voting is closed.', 'Dit is klaar, dus stemmen kan niet meer.'),
      VoteResult.notPro => tr('Voting is for supporters.', 'Stemmen is voor supporters.'),
      VoteResult.notFound => tr('This item is no longer on the list.', 'Dit staat niet meer op de lijst.'),
      VoteResult.missing => null,
      VoteResult.failed => tr(
        'That did not work. Check your connection and try again.',
        'Dat lukte niet. Controleer je verbinding en probeer opnieuw.',
      ),
    };
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg, key: const ValueKey('roadmap-message'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isPro = proOf(context)?.isPro ?? false;
    final features = featuresOf(context);
    final early = features?.inEarlyAccess ?? const <FeatureFlag>[];
    final r = _roadmap;
    final signedIn = r.remote != null;

    final children = <Widget>[];
    if (!signedIn) {
      children.add(_note(context, 'roadmap-signed-out', tr('Log in to see what is coming next.', 'Log in om te zien wat er komt.')));
    } else if (!r.available) {
      children.add(
        _note(
          context,
          'roadmap-missing',
          tr('The roadmap is not available yet. Check back soon.', 'De roadmap is er nog niet. Kom binnenkort eens terug.'),
        ),
      );
    } else {
      children.add(_intro(context, isPro));
      if (early.isNotEmpty) {
        children
          ..add(const SizedBox(height: 12))
          ..add(_early(context, early, features!));
      }
      children.add(const SizedBox(height: 12));
      if (!r.loaded && r.loading) {
        children.add(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      } else if (r.failed && r.items.isEmpty) {
        children.add(
          Panel(
            key: const ValueKey('roadmap-failed'),
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Could not load the list. Check your connection.', 'De lijst laden lukte niet. Controleer je verbinding.'),
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink2),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: r.refresh, child: Text(tr('Try again', 'Opnieuw proberen'))),
                ),
              ],
            ),
          ),
        );
      } else if (r.items.isEmpty) {
        children.add(_note(context, 'roadmap-empty', tr('Nothing on the list yet.', 'Nog niets op de lijst.')));
      } else {
        for (final item in r.items) {
          children
            ..add(_item(context, item, isPro))
            ..add(const SizedBox(height: 10));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr("What's next", 'Wat komt er'))),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([r.refresh(), if (features != null) features.refresh()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Narrow(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(BuildContext context, String key, String text) => Panel(
    key: ValueKey(key),
    shadow: false,
    color: context.pal.surface2,
    child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: context.pal.ink2)),
  );

  /// Bovenaan: hoe stemmen werkt, of (zonder Pro) een rustige regel met een link naar Pro.
  Widget _intro(BuildContext context, bool isPro) {
    final p = context.pal;
    final left = _roadmap.votesLeft;
    if (isPro) {
      return Panel(
        key: const ValueKey('roadmap-intro'),
        shadow: false,
        color: p.brandSoft,
        borderColor: p.brandSoft,
        child: Row(
          children: [
            Icon(Icons.favorite_rounded, color: p.brand, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(
                  'Thank you for supporting MacroMatrix. Tap the heart on what you would like most.',
                  'Bedankt om MacroMatrix te steunen. Tik op het hartje bij wat je het liefst wilt.',
                ),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              left == 1 ? tr('1 vote left', 'nog 1 stem') : tr('$left votes left', 'nog $left stemmen'),
              key: const ValueKey('roadmap-votes-left'),
              style: numStyle(12.5, color: p.brand),
            ),
          ],
        ),
      );
    }
    return Panel(
      key: const ValueKey('roadmap-locked'),
      shadow: false,
      color: p.surface2,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.favorite_border_rounded, color: p.ink3, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Supporters vote on what comes next.', 'Supporters stemmen over wat er komt.'),
              style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink2),
            ),
          ),
          TextButton(
            key: const ValueKey('roadmap-about-pro'),
            onPressed: () => openProScreen(context),
            child: Text(tr('About Supporter', 'Over Supporter')),
          ),
        ],
      ),
    );
  }

  /// Wat nu in vroege toegang is, met de dag waarop het voor iedereen komt.
  Widget _early(BuildContext context, List<FeatureFlag> early, Features features) {
    final p = context.pal;
    return Panel(
      key: const ValueKey('roadmap-early'),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('In early access', 'In vroege toegang'), subtitle: tr('Supporters already have these.', 'Supporters hebben deze al.')),
          const SizedBox(height: 6),
          for (final f in early)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.title,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                        ),
                        if (f.publicFrom != null)
                          Text(
                            tr(
                              'For everyone on ${DateFormat('d MMMM', appLocale).format(f.publicFrom!.toLocal())}',
                              'Voor iedereen op ${DateFormat('d MMMM', appLocale).format(f.publicFrom!.toLocal())}',
                            ),
                            style: TextStyle(fontSize: 12.5, color: p.ink3),
                          ),
                      ],
                    ),
                  ),
                  if (features.isEarly(f.id)) const EarlyAccessChip(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, RoadmapItem item, bool isPro) {
    final p = context.pal;
    final canVote = isPro && !item.done;
    final busy = _roadmap.busy.contains(item.id);
    return Panel(
      key: ValueKey('roadmap-item-${item.id}'),
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusChip(item.status),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.description, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 52,
            child: Column(
              children: [
                if (canVote)
                  IconButton(
                    key: ValueKey('roadmap-vote-${item.id}'),
                    tooltip: item.mine ? tr('Take back your vote', 'Je stem terugnemen') : tr('Vote', 'Stemmen'),
                    isSelected: item.mine,
                    onPressed: busy ? null : () => _toggle(item),
                    icon: Icon(Icons.favorite_border_rounded, color: p.ink3),
                    selectedIcon: Icon(Icons.favorite_rounded, color: p.brand),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(item.mine ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: p.ink3),
                  ),
                Semantics(
                  label: tr('${item.votes} votes', '${item.votes} stemmen'),
                  child: ExcludeSemantics(
                    child: Text(
                      '${item.votes}',
                      key: ValueKey('roadmap-count-${item.id}'),
                      style: numStyle(14, color: item.mine ? p.brand : p.ink2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final RoadmapStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (label, bg, fg) = switch (status) {
      RoadmapStatus.idea => (tr('Idea', 'Idee'), p.sunken, p.ink2),
      RoadmapStatus.planned => (tr('Planned', 'Gepland'), p.lowSoft, p.low),
      RoadmapStatus.building => (tr('In progress', 'In de maak'), p.brandSoft, p.brand),
      RoadmapStatus.done => (tr('Done', 'Klaar'), p.okSoft, p.ok),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }
}

/// Tegel in de instellingen naar "What's next".
class RoadmapTile extends StatelessWidget {
  const RoadmapTile({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Panel(
      key: const ValueKey('roadmap-tile'),
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => openRoadmapScreen(context),
      child: Row(
        children: [
          Icon(Icons.map_outlined, color: pal.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr("What's next", 'Wat komt er'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                Text(
                  tr('See what we are working on and what may come next', 'Zie waar we aan werken en wat er misschien komt'),
                  style: TextStyle(fontSize: 12.5, color: pal.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: pal.ink3),
        ],
      ),
    );
  }
}
