import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../nutrition/levels.dart';
import '../../sync/pro.dart';
import '../theme.dart';
import '../../i18n.dart';
import 'avatar_frame.dart';
import 'avatar_frame_picker.dart';
import 'pro_widgets.dart';

/// Standaardavatars: een icoon op een kleur.
const avatarPresets = <(IconData, Color)>[
  (Icons.eco_rounded, Color(0xFF2E9E6B)),
  (Icons.local_fire_department_rounded, Color(0xFFE0702E)),
  (Icons.bolt_rounded, Color(0xFFD9A400)),
  (Icons.fitness_center_rounded, Color(0xFF3D5AD8)),
  (Icons.directions_run_rounded, Color(0xFF8A4FD8)),
  (Icons.self_improvement_rounded, Color(0xFF1F9BB5)),
  (Icons.pets_rounded, Color(0xFFB0572F)),
  (Icons.spa_rounded, Color(0xFFC94A87)),
  (Icons.restaurant_rounded, Color(0xFF5B6B2E)),
  (Icons.set_meal_rounded, Color(0xFF2F6FB0)),
  (Icons.egg_alt_rounded, Color(0xFFB8860B)),
  (Icons.favorite_rounded, Color(0xFFD23F4E)),
];

/// Namen van de standaardavatars (in dezelfde volgorde), onder het icoon en voor de schermlezer (S14).
const avatarPresetNames = <(String, String)>[
  ('Leaf', 'Blad'),
  ('Flame', 'Vlam'),
  ('Bolt', 'Bliksem'),
  ('Dumbbell', 'Halter'),
  ('Runner', 'Loper'),
  ('Yoga', 'Yoga'),
  ('Paw', 'Pootje'),
  ('Flower', 'Bloem'),
  ('Plate', 'Bord'),
  ('Fish', 'Vis'),
  ('Egg', 'Ei'),
  ('Heart', 'Hartje'),
];

String avatarPresetName(int i) => tr(avatarPresetNames[i].$1, avatarPresetNames[i].$2);

/// Kleur van de rand voor een level (zie levelHue).
Color levelColor(int level) => HSLColor.fromAHSL(1, levelHue(level), 0.62, 0.5).toColor();

final _photoCache = <String, Uint8List>{};

/// Alleen de afbeelding (foto of standaardavatar), rond.
class AvatarImage extends StatelessWidget {
  const AvatarImage({super.key, required this.avatar, required this.size});
  final String? avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = avatar;
    if (a != null && a.startsWith('jpg:')) {
      final bytes = _photoCache.putIfAbsent(a, () => base64Decode(a.substring(4)));
      return ClipOval(
        child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final i = a != null && a.startsWith('preset:') ? (int.tryParse(a.substring(7)) ?? 0) % avatarPresets.length : null;
    final (icon, color) = i == null ? (Icons.person_rounded, context.pal.ink3) : avatarPresets[i];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Avatar met een rand in de kleur van je level, sterren (één per 25 levels) en je level in een bolletje.
///
/// Met [frame] een supporterrand eromheen (zie avatar_frame.dart). De ring blijft de levelkleur en de maat van de
/// avatar verandert niet, zodat lijsten niet verspringen.
class LevelAvatar extends StatelessWidget {
  const LevelAvatar({super.key, required this.avatar, required this.level, this.size = 56, this.onTap, this.frame, this.animate = true});
  final String? avatar;
  final int level;
  final double size;
  final VoidCallback? onTap;
  final AvatarFrame? frame;

  /// false: de rand staat altijd stil (bv. op een deelkaart).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final ring = levelColor(level);
    final stars = starsFor(level);
    final border = (size * 0.07).clamp(2.0, 6.0);
    final badge = (size * 0.36).clamp(16.0, 30.0);
    final star = (size * 0.22).clamp(9.0, 18.0);
    final child = SizedBox(
      width: size + 6,
      height: size + 6 + (stars > 0 ? star * 0.45 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          _framed(
            Container(
              width: size,
              height: size,
              margin: const EdgeInsets.all(3),
              padding: EdgeInsets.all(border),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [ring, HSLColor.fromColor(ring).withLightness(0.68).toColor(), ring]),
              ),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: pal.surface),
                padding: EdgeInsets.all(border * 0.4),
                child: AvatarImage(avatar: avatar, size: size),
              ),
            ),
            ring,
            border,
          ),
          if (stars > 0)
            Positioned(
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < stars; i++)
                    Icon(
                      Icons.star_rounded,
                      size: star,
                      color: const Color(0xFFF2B705),
                      shadows: const [Shadow(blurRadius: 2, color: Colors.black38)],
                    ),
                ],
              ),
            ),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: BoxConstraints(minWidth: badge, minHeight: badge),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: ring,
                borderRadius: BorderRadius.circular(badge),
                border: Border.all(color: pal.surface, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$level',
                style: TextStyle(fontSize: badge * 0.48, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : Semantics(
            button: true,
            label: tr('Change profile photo', 'Profielfoto wijzigen'),
            child: GestureDetector(onTap: onTap, child: child),
          );
  }

  Widget _framed(Widget ringWidget, Color ring, double border) {
    final f = frame;
    if (f == null) return ringWidget;
    return FramedRing(frame: f, color: ring, size: size, border: border, animate: animate, child: ringWidget);
  }
}

/// Een foto vierkant bijsnijden en verkleinen tot 192 px (JPEG). Draait in een aparte isolate.
Uint8List shrinkAvatar(Uint8List data) {
  final src = img.decodeImage(data);
  if (src == null) throw const FormatException('no image');
  final side = src.width < src.height ? src.width : src.height;
  final square = img.copyCrop(src, x: (src.width - side) ~/ 2, y: (src.height - side) ~/ 2, width: side, height: side);
  return img.encodeJpg(img.copyResize(square, width: 192, height: 192, interpolation: img.Interpolation.average), quality: 82);
}

/// Avatar kiezen: een standaardavatar of een eigen foto. Geeft de nieuwe waarde terug, of null bij annuleren.
Future<String?> pickAvatar(BuildContext context, String? current) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) {
    final pal = ctx.pal;
    final isPro = proOf(ctx)?.isPro ?? false;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Profile photo', 'Profielfoto'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('Your friends see this photo next to your score.', 'Je vrienden zien deze foto bij je score.'),
              style: TextStyle(fontSize: 13, color: pal.ink2),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr('Choose your own photo', 'Eigen foto kiezen')),
              onPressed: () async {
                final picked = await FilePicker.pickFiles(dialogTitle: tr('Choose a photo', 'Kies een foto'), type: FileType.image);
                if (picked.isEmpty) return;
                final data = await picked.single.readAsBytes();
                try {
                  final small = await compute(shrinkAvatar, data);
                  if (ctx.mounted) Navigator.pop(ctx, 'jpg:${base64Encode(small)}');
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr('That photo could not be opened. Try a JPG or PNG.', 'Die foto kon niet geopend worden. Probeer een JPG of PNG.'),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              tr('Or pick an avatar', 'Of kies een avatar'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.ink),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < avatarPresets.length; i++)
                  Semantics(
                    button: true,
                    selected: current == 'preset:$i',
                    label: avatarPresetName(i),
                    excludeSemantics: true,
                    child: InkWell(
                      key: ValueKey('avatar-preset-$i'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, 'preset:$i'),
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: current == 'preset:$i' ? pal.ink : Colors.transparent, width: 2),
                              ),
                              child: AvatarImage(avatar: 'preset:$i', size: 52),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              avatarPresetName(i),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: pal.ink2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // De rand kies je hier ook, naast je foto (zonder Pro op slot, met een knop naar Pro)
            const SizedBox(height: 18),
            const AvatarFramePicker(),
            if (!isPro)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('avatar-sheet-pro'),
                  onPressed: () => openProScreen(ctx),
                  child: Text(tr('About Supporter', 'Over Supporter')),
                ),
              ),
          ],
        ),
      ),
    );
  },
);
