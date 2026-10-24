import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/avatar.dart';
import 'package:macromatrix/ui/widgets/avatar_frame.dart';

import 'pro_test.dart' show FakeProRemote, newPro, newState, pump;

/// Een server die ook randen kent.
class _FrameRemote extends FakeProRemote implements ProFrameRemote {
  final sent = <AvatarFrame?>[];

  @override
  Future<bool> setFrame(AvatarFrame? frame) async {
    sent.add(frame);
    status = status.withFrame(frame);
    return status.activeAt(DateTime.now());
  }
}

Future<void> _avatar(WidgetTester tester, Widget avatar, {bool reduceMotion = false, Brightness b = Brightness.light}) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(b),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: avatar)),
    ),
  ),
);

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  test('elke rand tekent zonder fouten, stil en in beweging, van 36 tot 84', () {
    for (final f in AvatarFrame.values) {
      for (final size in [36.0, 44.0, 56.0, 84.0]) {
        final border = (size * 0.07).clamp(2.0, 6.0);
        for (final anim in <Animation<double>?>[null, const AlwaysStoppedAnimation(0.0), const AlwaysStoppedAnimation(0.63)]) {
          for (final front in [false, true]) {
            final rec = ui.PictureRecorder();
            AvatarFramePainter(
              frame: f,
              color: levelColor(30),
              ring: size / 2,
              border: border,
              front: front,
              anim: anim,
            ).paint(Canvas(rec), Size.square(size + 6));
            rec.endRecording().dispose();
          }
        }
      }
    }
  });

  test('tinten houden de kleurtoon van het level', () {
    final c = levelColor(42);
    for (final l in [0.36, 0.5, 0.64, 0.8]) {
      final t = HSLColor.fromColor(frameTint(c, l));
      expect(t.hue, closeTo(HSLColor.fromColor(c).hue, 2.5));
      expect(t.lightness, closeTo(l, 0.01));
    }
  });

  testWidgets('een rand verandert de maat van de avatar niet (licht en donker)', (tester) async {
    for (final b in Brightness.values) {
      for (final size in [36.0, 56.0, 84.0]) {
        await _avatar(
          tester,
          LevelAvatar(key: const ValueKey('a'), avatar: 'preset:1', level: 30, size: size),
          b: b,
        );
        final plain = tester.getSize(find.byKey(const ValueKey('a')));
        for (final f in AvatarFrame.values) {
          await _avatar(
            tester,
            LevelAvatar(key: const ValueKey('a'), avatar: 'preset:1', level: 30, size: size, frame: f),
            b: b,
          );
          expect(tester.getSize(find.byKey(const ValueKey('a'))), plain);
          expect(find.byType(FramedRing), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  group('beweging', () {
    setUp(() => avatarFrameAnimations = true);
    tearDown(() => avatarFrameAnimations = false);

    testWidgets('beweegt normaal, maar staat stil met animaties beperken', (tester) async {
      for (final f in AvatarFrame.values) {
        await tester.pumpWidget(const SizedBox());
        await _avatar(tester, LevelAvatar(avatar: null, level: 5, frame: f));
        expect(tester.hasRunningAnimations, f.animated, reason: f.id);
        await tester.pump(const Duration(seconds: 1));

        await tester.pumpWidget(const SizedBox());
        await _avatar(tester, LevelAvatar(avatar: null, level: 5, frame: f), reduceMotion: true);
        expect(tester.hasRunningAnimations, isFalse, reason: f.id);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('op een deelkaart (animate: false) altijd stil', (tester) async {
      await _avatar(tester, const LevelAvatar(avatar: null, level: 5, frame: AvatarFrame.orbit, animate: false));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('in de tests staan randen standaard stil (pumpAndSettle blijft werken)', (tester) async {
    await _avatar(tester, const LevelAvatar(avatar: null, level: 5, frame: AvatarFrame.glow));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
  });

  group('Pro en je rand', () {
    test('de rand komt van de server en verdwijnt als Pro afloopt', () {
      expect(ProStatus.fromJson({'until': '2099-01-01T00:00:00Z', 'frame': 'laurel'}).frame, AvatarFrame.laurel);
      expect(ProStatus.fromJson({'until': '2099-01-01T00:00:00Z', 'frame': 'rainbow'}).frame, isNull);
      expect(ProStatus.fromJson({'until': '2099-01-01T00:00:00Z'}).frame, isNull);

      final s = newState();
      final server = _FrameRemote();
      final pro = newPro(s, server)..status = ProStatus(until: DateTime.now().add(const Duration(days: 3)), frame: AvatarFrame.glow);
      expect(pro.frame, AvatarFrame.glow);
      pro.status = ProStatus(until: DateTime.now().subtract(const Duration(minutes: 1)), frame: AvatarFrame.glow);
      expect(pro.frame, isNull);
    });

    testWidgets('zonder Pro: voorbeelden op slot, kiezen kan niet', (tester) async {
      final s = newState();
      final server = _FrameRemote();
      final pro = newPro(s, server);
      await pump(tester, s, pro, const ProScreen());
      await tester.ensureVisible(find.byKey(const ValueKey('frame-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Avatar frames are for supporters.'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(AvatarFrame.values.length));
      expect(find.text('Sparkle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('frame-glow')));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);
      expect(pro.frame, isNull);
    });

    testWidgets('met Pro: een rand kiezen gaat naar de server', (tester) async {
      final s = newState();
      final server = _FrameRemote()..status = ProStatus(until: DateTime.now().add(const Duration(days: 30)));
      final pro = newPro(s, server);
      await pro.refresh();
      await pump(tester, s, pro, const ProScreen());
      await tester.ensureVisible(find.byKey(const ValueKey('frame-picker')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      await tester.tap(find.byKey(const ValueKey('frame-orbit')));
      await tester.pumpAndSettle();
      expect(server.sent, [AvatarFrame.orbit]);
      expect(pro.frame, AvatarFrame.orbit);
      await tester.tap(find.byKey(const ValueKey('frame-none')));
      await tester.pumpAndSettle();
      expect(pro.frame, isNull);
    });
  });
}
