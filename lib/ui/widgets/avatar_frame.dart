/// Supporterranden rond de avatar (zie [AvatarFrame] in sync/pro.dart).
///
/// Vaste regel: de ring zelf houdt altijd de kleur van je level ([levelColor]), zodat levels in één oogopslag
/// herkenbaar blijven. Een rand verandert alleen de stijl, de beweging en de versiering, en gebruikt daarvoor de
/// levelkleur of een lichtere of donkerdere tint ervan (alleen de HSL-lichtheid verandert, nooit de kleurtoon).
///
/// Zuinig: één CustomPainter en hoogstens één AnimationController per avatar, met een trage cyclus, achter een
/// RepaintBoundary. Met "animaties beperken" in het systeem (of [avatarFrameAnimations] uit) staat de rand stil.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sync/pro.dart';

/// Randen mogen bewegen. Staat uit in de tests (test/flutter_test_config.dart), zodat pumpAndSettle niet blijft
/// wachten op een animatie die nooit stopt.
bool avatarFrameAnimations = true;

/// Duur van één cyclus per rand.
Duration framePeriod(AvatarFrame f) => switch (f) {
  AvatarFrame.glow => const Duration(milliseconds: 3200),
  AvatarFrame.orbit => const Duration(milliseconds: 3000),
  AvatarFrame.sparkle => const Duration(milliseconds: 2600),
  AvatarFrame.laurel => Duration.zero,
};

/// Dezelfde kleur met een andere lichtheid (zelfde kleurtoon).
Color frameTint(Color c, double lightness) => HSLColor.fromColor(c).withLightness(lightness.clamp(0.0, 1.0)).toColor();

/// Tekent een rand achter ([front] false) of boven ([front] true) de ring. [ring] is de straal van de buitenkant van
/// de ring, [border] de dikte ervan. Zonder [anim] staat de rand stil.
class AvatarFramePainter extends CustomPainter {
  AvatarFramePainter({required this.frame, required this.color, required this.ring, required this.border, required this.front, this.anim})
    : super(repaint: anim);

  final AvatarFrame frame;
  final Color color;
  final double ring, border;
  final bool front;
  final Animation<double>? anim;

  bool get _moving => anim != null;
  double get _t => anim?.value ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (frame) {
      case AvatarFrame.glow:
        _glow(canvas, c);
      case AvatarFrame.orbit:
        _orbit(canvas, c);
      case AvatarFrame.sparkle:
        if (front) _sparkle(canvas, c);
      case AvatarFrame.laurel:
        if (front) _laurel(canvas, c);
    }
  }

  // --- Gloed: een zachte halo in de levelkleur die traag aanzwelt en weer afneemt

  void _glow(Canvas canvas, Offset c) {
    final p = _moving ? 0.5 - 0.5 * math.cos(2 * math.pi * _t) : 0.65;
    final g = (ring * 0.26).clamp(4.0, 10.0);
    if (!front) {
      canvas.drawCircle(
        c,
        ring + g * (0.1 + 0.3 * p),
        Paint()
          ..color = color.withValues(alpha: 0.38 + 0.4 * p)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g * 0.5),
      );
      return;
    }
    // Een dun licht randje op de ring dat mee aanzwelt
    canvas.drawCircle(
      c,
      ring - border * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, border * 0.35)
        ..color = frameTint(color, 0.8).withValues(alpha: 0.2 + 0.45 * p),
    );
  }

  // --- Omloop: een helder lichtje met een staart dat rond de ring draait

  void _orbit(Canvas canvas, Offset c) {
    if (!front) {
      // Dun spoor net buiten de ring
      canvas.drawCircle(
        c,
        ring + math.max(1.5, border * 0.45),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, border * 0.3)
          ..color = color.withValues(alpha: 0.4),
      );
      return;
    }
    // Stil: het lichtje linksboven (rechtsboven zit het levelbolletje)
    final head = _moving ? -math.pi / 2 + 2 * math.pi * _t : -math.pi * 0.8;
    const tail = math.pi * 0.8;
    final rc = ring - border / 2;
    final rect = Rect.fromCircle(center: c, radius: rc);
    final light = frameTint(color, 0.88);
    const n = 24;
    for (var i = 0; i < n; i++) {
      final k = 1 - i / n;
      final a1 = head - tail * i / n;
      canvas.drawArc(
        rect,
        a1 - tail / n - 0.01,
        tail / n + 0.01,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = border * (0.45 + 0.5 * k)
          ..color = light.withValues(alpha: 0.95 * math.pow(k, 1.6)),
      );
    }
    final h = c + Offset(math.cos(head), math.sin(head)) * rc;
    canvas.drawCircle(
      h,
      border * 1.5,
      Paint()
        ..color = frameTint(color, 0.62).withValues(alpha: 0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, border * 0.8),
    );
    canvas.drawCircle(h, math.max(1.5, border * 0.7), Paint()..color = frameTint(color, 0.97));
  }

  // --- Fonkeling: een paar sterretjes en puntjes op de ring die om beurten oplichten

  /// Hoeken (radialen, 0 = rechts, met de klok mee). Rechtsboven zit het levelbolletje, onderaan de sterren van je
  /// level: daar komt niets.
  static const _sparkAngles = [-2.0, 3.05, 2.25, 0.62];
  static const _sparkStill = [1.0, 0.7, 0.88, 0.62];
  static const _dotAngles = [-1.25, 1.2, 2.7];

  void _sparkle(Canvas canvas, Offset c) {
    final st = (ring * 0.42).clamp(6.0, 14.0);
    final light = frameTint(color, 0.93);
    final rc = ring - border * 0.25;
    for (var i = 0; i < _sparkAngles.length; i++) {
      final v = _moving ? math.pow(0.5 + 0.5 * math.sin(2 * math.pi * (_t + i / _sparkAngles.length)), 1.5).toDouble() : _sparkStill[i];
      final scale = 0.45 + 0.55 * v;
      final alpha = _moving ? 0.35 + 0.65 * v : 1.0;
      final a = _sparkAngles[i];
      final p = c + Offset(math.cos(a), math.sin(a)) * rc;
      canvas.drawCircle(
        p,
        st * 0.45 * scale,
        Paint()
          ..color = color.withValues(alpha: 0.75 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, st * 0.22),
      );
      canvas.drawPath(_star(p, st * 0.55 * scale), Paint()..color = light.withValues(alpha: alpha));
    }
    // Kleine puntjes, net uit de maat met de sterretjes
    final dot = math.max(0.9, border * 0.32);
    for (var i = 0; i < _dotAngles.length; i++) {
      final v = _moving ? 0.5 + 0.5 * math.sin(2 * math.pi * (_t + 0.5 + i / _dotAngles.length)) : 0.8;
      final a = _dotAngles[i];
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * (ring - border / 2),
        dot * (0.6 + 0.6 * v),
        Paint()..color = frameTint(color, 0.9).withValues(alpha: 0.4 + 0.6 * v),
      );
    }
  }

  /// Een ster met vier punten rond [p] met straal [r].
  static Path _star(Offset p, double r) {
    final path = Path();
    const pts = 8;
    for (var i = 0; i < pts; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final d = i.isEven ? r : r * 0.3;
      final q = p + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    return path..close();
  }

  // --- Lauwerkrans: twee takjes met blaadjes aan de onderkant, links en rechts (staat stil)

  void _laurel(Canvas canvas, Offset c) {
    final leaf = (ring * 0.4).clamp(6.0, 15.0);
    final n = ring >= 26 ? 6 : 5;
    final rb = ring + leaf * 0.02;
    final stem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.1, border * 0.38)
      ..color = frameTint(color, 0.36);
    final outer = Paint()..color = color;
    final inner = Paint()..color = frameTint(color, 0.36);
    final tip = Paint()..color = frameTint(color, 0.64);
    // Van onderaan (bijna 90°) naar boven (rechts); de linkerkant is het spiegelbeeld
    const from = 1.34, to = 0.12;
    for (final side in [1.0, -1.0]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(side, 1);
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: rb), to, from - to, false, stem);
      for (var i = 0; i < n; i++) {
        final f = i / (n - 1);
        final phi = from + (to - from) * f;
        final b = Offset(math.cos(phi), math.sin(phi)) * rb;
        // Richting langs de tak (naar boven) en naar buiten
        final tangent = Offset(math.sin(phi), -math.cos(phi));
        final out = Offset(math.cos(phi), math.sin(phi));
        final len = leaf * (1 - 0.32 * f);
        _leaf(canvas, b, _dir(tangent, out, 0.75), len, outer);
        if (i < n - 1) _leaf(canvas, b + tangent * (len * 0.25), _dir(tangent, out, -0.2), len * 0.8, inner);
      }
      final end = Offset(math.cos(to), math.sin(to)) * rb;
      _leaf(canvas, end, Offset(math.sin(to), -math.cos(to)), leaf * 0.62, tip);
      canvas.restore();
    }
  }

  /// Richting [tangent] gedraaid met hoek [beta] naar [out] (negatief = naar binnen).
  static Offset _dir(Offset tangent, Offset out, double beta) => tangent * math.cos(beta) + out * math.sin(beta);

  /// Een blaadje vanaf [b] in richting [d] (eenheidsvector) met lengte [len].
  static void _leaf(Canvas canvas, Offset b, Offset d, double len, Paint paint) {
    final t = b + d * len;
    final m = (b + t) / 2;
    final nrm = Offset(-d.dy, d.dx) * (len * 0.34);
    canvas.drawPath(
      Path()
        ..moveTo(b.dx, b.dy)
        ..quadraticBezierTo(m.dx + nrm.dx, m.dy + nrm.dy, t.dx, t.dy)
        ..quadraticBezierTo(m.dx - nrm.dx, m.dy - nrm.dy, b.dx, b.dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(AvatarFramePainter old) =>
      old.frame != frame || old.color != color || old.ring != ring || old.border != border || old.front != front || old.anim != anim;
}

/// De ring van een avatar met een supporterrand eromheen. [child] is de ring zelf (met de avatar erin), [size] de
/// buitenmaat van de ring; [inset] de marge rond de ring binnen [child].
class FramedRing extends StatefulWidget {
  const FramedRing({
    super.key,
    required this.frame,
    required this.color,
    required this.size,
    required this.border,
    this.inset = 3,
    this.animate = true,
    required this.child,
  });

  final AvatarFrame frame;
  final Color color;
  final double size, border, inset;

  /// false: altijd stil (bv. op een deelkaart, die als afbeelding bewaard wordt).
  final bool animate;
  final Widget child;

  @override
  State<FramedRing> createState() => _FramedRingState();
}

class _FramedRingState extends State<FramedRing> with TickerProviderStateMixin {
  AnimationController? _c;

  bool get _motion => widget.animate && widget.frame.animated && avatarFrameAnimations && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (!_motion) {
      _c?.dispose();
      _c = null;
      return;
    }
    final d = framePeriod(widget.frame);
    if (_c?.duration != d) {
      _c?.dispose();
      _c = AnimationController(vsync: this, duration: d)..repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FramedRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AvatarFramePainter painter(bool front) =>
        AvatarFramePainter(frame: widget.frame, color: widget.color, ring: widget.size / 2, border: widget.border, front: front, anim: _c);
    return RepaintBoundary(
      child: CustomPaint(
        painter: painter(false),
        foregroundPainter: painter(true),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
