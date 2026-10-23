import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/badges.dart';
import '../../state/app_state.dart';
import '../../sync/friends.dart';
import '../theme.dart';
import 'kit.dart';

/// Icoon per categorie: blijft hetzelfde over alle niveaus.
const _icons = <String, IconData>{
  'days': Icons.menu_book_rounded,
  'streak': Icons.local_fire_department_rounded,
  'perfect': Icons.star_rounded,
  'vitd': Icons.wb_sunny_rounded,
  'fiber': Icons.grass_rounded,
  'iron': Icons.fitness_center_rounded,
  'omega': Icons.set_meal_rounded,
  'level': Icons.trending_up_rounded,
  'battles': Icons.sports_mma_rounded,
  'wins': Icons.emoji_events_rounded,
  'winstreak': Icons.shield_rounded,
  'comeback': Icons.replay_rounded,
  'protein': Icons.egg_alt_rounded,
  'variety': Icons.palette_rounded,
  'perfectweek': Icons.event_available_rounded,
  'scanner': Icons.qr_code_scanner_rounded,
  'social': Icons.groups_rounded,
};

/// Kleurverloop per niveau: brons, zilver, goud, platina, diamant.
const _tierColors = [
  [Color(0xFFD9A066), Color(0xFF8C5A2B)],
  [Color(0xFFE6EBF0), Color(0xFF8792A0)],
  [Color(0xFFFFE07A), Color(0xFFC79200)],
  [Color(0xFFB8F0F2), Color(0xFF2F8F9C)],
  [Color(0xFFDCCBFF), Color(0xFF5B34D6)],
];

Color tierColor(int tier) => tier < 1 ? const Color(0xFF9AA0A6) : _tierColors[tier - 1][1];

/// Badge van één categorie op een niveau. Hoe hoger het niveau, hoe rijker de vormgeving: kleur, rand, bolletjes,
/// glinstering (vanaf platina) en een gloed (diamant).
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key, required this.category, required this.tier, this.size = 44});
  final String category;
  final int tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final locked = tier < 1;
    final colors = locked ? [pal.track, pal.track] : _tierColors[tier - 1];
    final ring = locked ? 0.0 : size * (0.03 + 0.012 * tier);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              border: locked ? null : Border.all(color: Colors.white.withValues(alpha: 0.85), width: ring),
              boxShadow: [
                if (tier >= 5) BoxShadow(color: colors[1].withValues(alpha: 0.55), blurRadius: size * 0.25, spreadRadius: size * 0.02),
                if (tier >= 1 && tier < 5)
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: size * 0.08, offset: Offset(0, size * 0.03)),
              ],
            ),
            child: Icon(
              _icons[category] ?? Icons.star_rounded,
              size: size * 0.5,
              color: locked ? pal.ink3 : Colors.white,
              shadows: locked ? null : [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: size * 0.06)],
            ),
          ),
          if (tier >= 4)
            Positioned(
              top: -size * 0.04,
              right: -size * 0.04,
              child: Icon(Icons.auto_awesome, size: size * 0.32, color: tier >= 5 ? const Color(0xFFFFE07A) : Colors.white),
            ),
          if (!locked)
            Positioned(
              bottom: -size * 0.1,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: size * 0.06, vertical: size * 0.025),
                decoration: BoxDecoration(color: colors[1], borderRadius: BorderRadius.circular(size)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < tier; i++)
                      Container(
                        width: size * 0.07,
                        height: size * 0.07,
                        margin: EdgeInsets.symmetric(horizontal: size * 0.012),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uitleg van een categorie: alle niveaus met je voortgang.
void showBadgeCategory(BuildContext context, String id, {int? value, int? tier}) {
  final c = categoryById[id];
  if (c == null) return;
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final pal = ctx.pal;
      final t = tier ?? (value == null ? 0 : c.tierFor(value));
      return AlertDialog(
        icon: Align(
          child: BadgeIcon(category: id, tier: t, size: 72),
        ),
        title: Text(c.name, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tierName(t),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: tierColor(t)),
              ),
              if (value != null && t < 5) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value / c.thresholds[t]).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: pal.track,
                    color: tierColor(t + 1),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('$value / ${c.thresholds[t]} for ${tierName(t + 1)}', '$value / ${c.thresholds[t]} voor ${tierName(t + 1)}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: pal.ink3),
                ),
              ],
              const SizedBox(height: 12),
              for (var i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      BadgeIcon(category: id, tier: t >= i ? i : 0, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tierName(i),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t >= i ? tierColor(i) : pal.ink3),
                            ),
                            Text(c.goal(c.thresholds[i - 1]), style: TextStyle(fontSize: 12, color: pal.ink2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close', 'Sluiten')))],
      );
    },
  );
}

/// Showcase van iemand (categorie, niveau).
class ShowcaseRow extends StatelessWidget {
  const ShowcaseRow({super.key, required this.items, this.size = 30, this.spacing = 6});
  final List<(String, int)> items;
  final double size, spacing;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: spacing,
    runSpacing: spacing,
    children: [
      for (final (id, tier) in items)
        GestureDetector(
          onTap: () => showBadgeCategory(context, id, tier: tier),
          child: Tooltip(
            message: '${categoryById[id]?.name} · ${tierName(tier)}',
            child: Padding(
              padding: EdgeInsets.only(bottom: size * 0.1),
              child: BadgeIcon(category: id, tier: tier, size: size),
            ),
          ),
        ),
    ],
  );
}

/// Titel kiezen uit de titels die je vrijspeelde.
Future<void> pickTitle(BuildContext context) async {
  final s = context.read<AppState>();
  final tiers = context.read<Friends>().tiers;
  final available = availableTitles(tiers);
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final pal = ctx.pal;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(tr('Your title', 'Je titel'), style: Theme.of(ctx).textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  tr('Shown with your avatar for friends.', 'Zichtbaar bij je avatar voor vrienden.'),
                  style: TextStyle(fontSize: 13, color: pal.ink2),
                ),
              ),
              for (final t in titles)
                Builder(
                  builder: (ctx) {
                    final open = available.contains(t);
                    final c = t.category == null ? null : categoryById[t.category];
                    return ListTile(
                      enabled: open,
                      leading: c == null ? const Icon(Icons.person_rounded) : BadgeIcon(category: c.id, tier: open ? t.tier : 0, size: 34),
                      title: Text(t.name),
                      subtitle: open || c == null ? null : Text('${c.name} · ${tierName(t.tier)}: ${c.goal(c.thresholds[t.tier - 1])}'),
                      trailing: s.title == t.id ? Icon(Icons.check_circle_rounded, color: pal.brand) : null,
                      onTap: () => Navigator.pop(ctx, t.id),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
  if (picked != null) s.setTitle(picked);
}

/// Showcase kiezen: tot 3 verdiende badges die vrienden zien.
Future<void> pickShowcase(BuildContext context) async {
  final s = context.read<AppState>();
  final f = context.read<Friends>();
  final tiers = f.tiers;
  final chosen = [...f.showcase];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final pal = ctx.pal;
        final earned = badgeCategories.where((c) => (tiers[c.id] ?? 0) > 0).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Showcase', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  tr('Choose up to 3 badges your friends see.', 'Kies tot 3 badges die je vrienden zien.'),
                  style: TextStyle(fontSize: 13, color: pal.ink2),
                ),
                const SizedBox(height: 14),
                if (earned.isEmpty)
                  Text(tr('You have no badges yet.', 'Je hebt nog geen badges.'), style: TextStyle(color: pal.ink3))
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      for (final c in earned)
                        GestureDetector(
                          onTap: () => setSheet(() {
                            if (chosen.contains(c.id)) {
                              chosen.remove(c.id);
                            } else if (chosen.length < 3) {
                              chosen.add(c.id);
                            }
                          }),
                          child: Container(
                            width: 76,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: chosen.contains(c.id) ? pal.brandSoft : Colors.transparent,
                              border: Border.all(color: chosen.contains(c.id) ? pal.brand : pal.line),
                            ),
                            child: Column(
                              children: [
                                BadgeIcon(category: c.id, tier: tiers[c.id]!, size: 44),
                                const SizedBox(height: 8),
                                Text(
                                  c.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(fontSize: 11, color: pal.ink),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    s.setShowcase(chosen);
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Save (${chosen.length}/3)', 'Bewaren (${chosen.length}/3)')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Je showcase en al je badges met hun niveau.
class BadgesCard extends StatefulWidget {
  const BadgesCard({super.key});

  @override
  State<BadgesCard> createState() => _BadgesCardState();
}

class _BadgesCardState extends State<BadgesCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = context.watch<Friends>();
    context.watch<AppState>();
    final values = f.badgeValuesNow;
    final tiers = badgeTiers(values);
    final showcase = f.showcase;
    final total = tiers.values.fold(0, (a, b) => a + b);
    final groups = [
      (BadgeGroup.logging, tr('Logging', 'Loggen')),
      (BadgeGroup.nutrition, tr('Nutrition', 'Voeding')),
      (BadgeGroup.level, 'Level'),
      (BadgeGroup.battle, 'Battles'),
    ];
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            'Badges',
            trailing: Text(
              tr('$total / ${badgeCategories.length * 5} tiers', '$total / ${badgeCategories.length * 5} niveaus'),
              style: TextStyle(fontSize: 12, color: pal.ink3),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: showcase.isEmpty
                    ? Text(
                        tr('Log your food to earn your first badge.', 'Log je eten om je eerste badge te verdienen.'),
                        style: TextStyle(fontSize: 13, color: pal.ink3),
                      )
                    : ShowcaseRow(items: [for (final id in showcase) (id, tiers[id]!)], size: 44, spacing: 12),
              ),
              if (showcase.isNotEmpty) OutlinedButton(onPressed: () => pickShowcase(context), child: const Text('Showcase')),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? tr('Hide all badges', 'Alle badges verbergen') : tr('All badges', 'Alle badges')),
            ),
          ),
          if (_all)
            for (final (g, label) in groups) ...[
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.ink2),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (final c in badgeCategories.where((c) => c.group == g))
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => showBadgeCategory(context, c.id, value: values[c.id] ?? 0),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            BadgeIcon(category: c.id, tier: tiers[c.id]!, size: 46),
                            const SizedBox(height: 9),
                            Text(
                              c.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(fontSize: 11, height: 1.2, color: tiers[c.id]! > 0 ? pal.ink : pal.ink3),
                            ),
                            Text(
                              tierName(tiers[c.id]!),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: tierColor(tiers[c.id]!)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}
