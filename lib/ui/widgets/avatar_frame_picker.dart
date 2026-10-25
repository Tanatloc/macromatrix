/// Je supporterrand kiezen: een voorbeeld van elke rand rond je eigen avatar, op je eigen level.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../state/app_state.dart';
import '../../sync/pro.dart';
import '../theme.dart';
import 'avatar.dart';
import 'kit.dart';
import 'pro_widgets.dart';

/// Paneel "Avatarrand". Met Pro kies je er een; zonder Pro zie je de voorbeelden op slot, met een korte uitleg.
class AvatarFramePicker extends StatelessWidget {
  const AvatarFramePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pro = proOf(context);
    final s = context.watch<AppState?>();
    final isPro = pro?.isPro ?? false;
    final unavailable = pro != null && !pro.frameAvailable;
    final enabled = isPro && !unavailable;
    final current = pro?.frame;

    Widget option(AvatarFrame? f, double width) {
      final selected = enabled && f == current;
      final label = f?.label ?? tr('None', 'Geen');
      return Semantics(
        button: enabled,
        selected: selected,
        label: enabled ? label : tr('$label, for supporters', '$label, voor supporters'),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('frame-${f?.id ?? 'none'}'),
          borderRadius: BorderRadius.circular(14),
          onTap: enabled && !selected ? () => pro!.setFrame(f) : null,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? p.brand : Colors.transparent, width: 2),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: enabled ? 1 : 0.6,
                      child: LevelAvatar(avatar: s?.avatar, level: s?.level.level ?? 1, size: 48, frame: f),
                    ),
                    if (!enabled && f != null)
                      Positioned(
                        left: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                          child: Icon(Icons.lock_outline_rounded, size: 13, color: p.ink3),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: enabled ? p.ink : p.ink3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final String note;
    if (unavailable) {
      note = tr('Avatar frames are not available yet.', 'Avatarranden zijn nog niet beschikbaar.');
    } else if (!isPro) {
      note = tr('Avatar frames are for supporters.', 'Avatarranden zijn voor supporters.');
    } else if (pro?.status.showBadge == false && pro?.debugPro == null) {
      note = tr(
        'Your friends see your frame while the Supporter badge is shown.',
        'Je vrienden zien je rand zolang het Supporter-badge zichtbaar is.',
      );
    } else {
      note = tr(
        'Your friends see it in the leaderboard, in battles and on your profile. Your level colour stays the same.',
        'Je vrienden zien hem in de ranglijst, bij battles en op je profiel. De kleur van je level blijft dezelfde.',
      );
    }

    return Panel(
      key: const ValueKey('frame-picker'),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Avatar frame', 'Avatarrand'), trailing: isPro ? null : const ProTag()),
          const SizedBox(height: 4),
          Row(
            children: [
              // Groot voorbeeld van je gekozen rand: klein lijken de rustige randen op "Geen" (SU-9)
              if (enabled) ...[
                ExcludeSemantics(
                  child: Padding(
                    key: const ValueKey('frame-preview'),
                    padding: const EdgeInsets.fromLTRB(8, 10, 18, 10),
                    child: LevelAvatar(avatar: s?.avatar, level: s?.level.level ?? 1, size: 88, frame: current),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  note,
                  key: const ValueKey('frame-note'),
                  style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Zo veel kolommen als er passen, minstens 4 op een gsm, en de vakjes vullen de breedte (SU-9)
          LayoutBuilder(
            builder: (context, box) {
              const gap = 4.0;
              final cols = math.max(4, ((box.maxWidth + gap) / (84 + gap)).floor());
              final width = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: 6,
                children: [option(null, width), for (final f in AvatarFrame.values) option(f, width)],
              );
            },
          ),
        ],
      ),
    );
  }
}
