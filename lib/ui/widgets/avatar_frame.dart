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
  AvatarFrame.ripple => const Duration(milliseconds: 2800),
  AvatarFrame.spin => const Duration(milliseconds: 9000),
  AvatarFrame.sunburst => const Duration(milliseconds: 3600),
  AvatarFrame.laurel || AvatarFrame.crown || AvatarFrame.wings || AvatarFrame.blades || AvatarFrame.royal => Duration.zero,
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
      case AvatarFrame.ripple:
        if (!front) _ripple(canvas, c);
      case AvatarFrame.spin:
        if (!front) _spin(canvas, c);
      case AvatarFrame.sunburst:
        if (!front) _sunburst(canvas, c);
      case AvatarFrame.crown:
        if (front) _crown(canvas, c);
      case AvatarFrame.wings:
        if (!front) _wings(canvas, c);
      case AvatarFrame.blades:
        if (!front) _blades(canvas, c);
      case AvatarFrame.royal:
        _royal(canvas, c);
    }
  }

  /// Een vorm als glanzend metaal in de levelkleur: licht bovenaan, donker onderaan, met een donkere omlijning.
  void _metal(Canvas canvas, Path path, {double outline = 0.8}) {
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [frameTint(color, 0.8), color, frameTint(color, 0.34)],
          stops: const [0, 0.45, 1],
        ).createShader(b),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = outline
        ..color = frameTint(color, 0.24),
    );
  }

  // --- Vleugels: drie veren per kant, schuin omhoog, achter de ring

  void _wings(Canvas canvas, Offset c) {
    final r = ring;
    final outline = math.max(0.6, r * 0.035);
    for (final side in [1.0, -1.0]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(side, 1);
      // Van de onderste (kortste) naar de bovenste (langste) veer, zodat de bovenste vooraan ligt
      for (var i = 2; i >= 0; i--) {
        final a = -0.8 + i * 0.32;
        final len = r * (1.12 - i * 0.2);
        final w = r * (0.3 - i * 0.04);
        final base = Offset(r * 0.62, -r * 0.22 + i * r * 0.22);
        final d = Offset(math.cos(a), math.sin(a));
        final nrm = Offset(-d.dy, d.dx);
        final tip = base + d * len;
        final path = Path()
          ..moveTo(base.dx - nrm.dx * w * 0.5, base.dy - nrm.dy * w * 0.5)
          ..quadraticBezierTo(base.dx + d.dx * len * 0.55 - nrm.dx * w, base.dy + d.dy * len * 0.55 - nrm.dy * w, tip.dx, tip.dy)
          ..quadraticBezierTo(
            base.dx + d.dx * len * 0.6 + nrm.dx * w * 0.9,
            base.dy + d.dy * len * 0.6 + nrm.dy * w * 0.9,
            base.dx + nrm.dx * w * 0.5,
            base.dy + nrm.dy * w * 0.5,
          )
          ..close();
        _metal(canvas, path, outline: outline);
      }
      canvas.restore();
    }
  }

  // --- Klingen: twee gebogen klingen die onderaan uit de ring komen en naar buiten en omhoog lopen

  void _blades(Canvas canvas, Offset c) {
    final r = ring;
    final outline = math.max(0.6, r * 0.035);
    Offset polar(double a, double d) => Offset(math.cos(a), math.sin(a)) * d;
    for (final side in [1.0, -1.0]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(side, 1);
      // Grote kling: van onderaan de ring, met een bolle buitenkant, tot een punt rechts boven het midden
      final b1 = polar(1.05, r * 0.98);
      final b2 = polar(0.2, r * 0.98);
      final tip = Offset(r * 1.42, -r * 0.42);
      _metal(
        canvas,
        Path()
          ..moveTo(b1.dx, b1.dy)
          ..quadraticBezierTo(r * 1.5, r * 0.62, tip.dx, tip.dy)
          ..quadraticBezierTo(r * 1.1, r * 0.08, b2.dx, b2.dy)
          ..close(),
        outline: outline,
      );
      // Klein puntje eronder, schuin naar beneden
      final s1 = polar(1.45, r * 0.98);
      final s2 = polar(1.15, r * 0.98);
      _metal(
        canvas,
        Path()
          ..moveTo(s1.dx, s1.dy)
          ..quadraticBezierTo(r * 0.55, r * 1.3, r * 0.82, r * 1.32)
          ..quadraticBezierTo(r * 0.62, r * 1.08, s2.dx, s2.dy)
          ..close(),
        outline: outline,
      );
      canvas.restore();
    }
  }

  // --- Koninklijk: een tweede, dunne ring eromheen (achter), met blaadjes opzij en een edelsteentje bovenaan (voor)

  void _royal(Canvas canvas, Offset c) {
    final r = ring;
    final gap = math.max(2.2, border * 0.75);
    final w = math.max(1.6, border * 0.6);
    final ro = r + gap + w / 2;
    if (!front) {
      canvas.drawCircle(
        c,
        ro,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..shader = SweepGradient(
            colors: [frameTint(color, 0.8), frameTint(color, 0.36), frameTint(color, 0.8), frameTint(color, 0.36), frameTint(color, 0.8)],
          ).createShader(Rect.fromCircle(center: c, radius: ro)),
      );
      return;
    }
    // Blaadjes links en rechts op de buitenste ring, schuin omhoog
    final leaf = (r * 0.36).clamp(5.0, 13.0);
    final leafPaint = Paint()..color = color;
    final leafLight = Paint()..color = frameTint(color, 0.7);
    for (final side in [1.0, -1.0]) {
      for (var i = 0; i < 3; i++) {
        final a = side > 0 ? 0.35 - i * 0.32 : math.pi - 0.35 + i * 0.32;
        final p = c + Offset(math.cos(a), math.sin(a)) * ro;
        final out = Offset(math.cos(a), math.sin(a));
        final tangent = Offset(math.sin(a), -math.cos(a)) * side;
        _leaf(canvas, p, _dir(tangent, out, 0.7), leaf * (1 - i * 0.12), i.isEven ? leafPaint : leafLight);
      }
    }
    // Edelsteentje bovenaan
    final g = (r * 0.2).clamp(3.5, 8.0);
    final top = c + Offset(0, -ro);
    final gem = Path()
      ..moveTo(top.dx, top.dy - g)
      ..lineTo(top.dx + g * 0.75, top.dy)
      ..lineTo(top.dx, top.dy + g)
      ..lineTo(top.dx - g * 0.75, top.dy)
      ..close();
    _metal(canvas, gem, outline: math.max(0.6, g * 0.15));
    canvas.drawCircle(top + Offset(-g * 0.2, -g * 0.3), math.max(0.6, g * 0.18), Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  // --- Rimpeling: twee golfjes die van de ring naar buiten lopen en daarbij vervagen

  void _ripple(Canvas canvas, Offset c) {
    final g = (ring * 0.32).clamp(4.0, 11.0);
    for (final k in _moving ? [_t, (_t + 0.5) % 1] : [0.3, 0.75]) {
      canvas.drawCircle(
        c,
        ring + 0.5 + g * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, border * (0.75 - 0.45 * k))
          ..color = frameTint(color, 0.5 + 0.25 * k).withValues(alpha: 0.85 * (1 - k)),
      );
    }
  }

  // --- Draaikrans: een krans van streepjes net buiten de ring die traag ronddraait

  void _spin(Canvas canvas, Offset c) {
    final r = ring + math.max(2.2, border * 0.8);
    final n = ring >= 26 ? 16 : 12;
    final rect = Rect.fromCircle(center: c, radius: r);
    final step = 2 * math.pi / n;
    final turn = 2 * math.pi * _t;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(
        rect,
        turn + i * step,
        step * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.2, border * 0.55)
          ..color = (i.isEven ? color : frameTint(color, 0.78)),
      );
    }
  }

  // --- Zonnestralen: korte stralen rondom die om beurten langer worden

  void _sunburst(Canvas canvas, Offset c) {
    final n = ring >= 26 ? 20 : 14;
    final g = (ring * 0.3).clamp(3.5, 10.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.1, border * 0.45);
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      final wave = _moving ? 0.5 + 0.5 * math.sin(2 * math.pi * (_t * 2 - i / n * 2)) : (i.isEven ? 1.0 : 0.4);
      final len = g * (i.isEven ? 0.55 + 0.45 * wave : 0.35 + 0.3 * wave);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + d * (ring + 1),
        c + d * (ring + 1 + len),
        paint..color = (i.isEven ? color : frameTint(color, 0.72)).withValues(alpha: 0.6 + 0.4 * wave),
      );
    }
  }

  // --- Kroon: een kroontje linksboven op de ring (rechtsboven zit het levelbolletje), staat stil

  void _crown(Canvas canvas, Offset c) {
    const a = -2.1;
    final w = (ring * 0.9).clamp(13.0, 34.0);
    final h = w * 0.66;
    final base = c + Offset(math.cos(a), math.sin(a)) * (ring - border * 0.9);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(a + math.pi / 2);
    // Onderkant op de ring, punten naar buiten (naar boven in dit assenstelsel)
    final path = Path()
      ..moveTo(-w / 2, 0)
      ..lineTo(-w / 2, -h * 0.55)
      ..lineTo(-w / 4, -h * 0.25)
      ..lineTo(0, -h)
      ..lineTo(w / 4, -h * 0.25)
      ..lineTo(w / 2, -h * 0.55)
      ..lineTo(w / 2, 0)
      ..close();
    canvas.drawPath(path.shift(const Offset(0, 0.8)), Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawPath(path, Paint()..color = frameTint(color, 0.62));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(0.8, w * 0.06)
        ..color = frameTint(color, 0.3),
    );
    final dot = Paint()..color = frameTint(color, 0.9);
    final r = math.max(0.9, w * 0.07);
    for (final q in [Offset(-w / 2, -h * 0.55), Offset(0, -h), Offset(w / 2, -h * 0.55)]) {
      canvas.drawCircle(q, r, dot);
    }
    canvas.restore();
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
