/// Bouwstenen van het ontwerpsysteem: kaart, kop, statusvorm, bereikbalk, segmentknop, chips en labels.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/food.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/targets.dart';
import '../theme.dart';
import '../../i18n.dart';

final _ints = <String, NumberFormat>{};

/// Geheel getal met duizendtallen volgens de taal (2,042 of 2.042).
String fmtInt(num v) => _ints.putIfAbsent(appLocale, () => NumberFormat.decimalPattern(appLocale)).format(v.round());

/// Getal met [d] decimalen, met punt (Engels) of komma (Nederlands).
String fmtDec(num v, [int d = 1]) => fmtNum(v, d);

/// Naam midden in een zin: "Vitamine D" wordt "vitamine D", "Jodium" wordt "jodium", "B12" blijft.
String inSentence(String name) =>
    name.length > 1 && name[1] == name[1].toLowerCase() && name[1] != name[1].toUpperCase() ? name[0].toLowerCase() + name.substring(1) : name;

/// Percentage zonder decimalen. Rondt niet naar 100% als je er nog net niet bent (99,6% blijft 99%), en
/// niet naar 0% als er toch iets is (0,4% wordt 1%): anders lijkt een doel gehaald of een inname nul terwijl dat niet zo is.
String fmtPct(double fraction) {
  final pct = (fraction * 100).round();
  if (fraction < 1 && pct >= 100) return '99%';
  if (fraction > 0 && pct == 0) return '1%';
  return '$pct%';
}

/// Inhoud niet breder dan een gsm-kolom op grote schermen.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Vanaf deze vensterbreedte krijgt de app een pc-indeling: een zijbalk met namen, en schermen in kolommen.
const desktopWidth = 1000.0;

/// Pc-indeling (zie [desktopWidth])?
bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopWidth;

/// Vanaf deze breedte van de inhoud zetten schermen kaarten naast elkaar.
const twoColumnWidth = 940.0;

/// Breedste inhoud op een pc: ruim genoeg voor twee of drie kolommen, maar niet uitgerekt op een ultrabreed scherm.
const wideMaxWidth = 1280.0;

/// Twee kolommen naast elkaar als er plaats is (pc), anders [left] boven [right].
class SplitColumns extends StatelessWidget {
  const SplitColumns({super.key, required this.left, required this.right, this.gap = 10, this.leftFlex = 1, this.rightFlex = 1});
  final List<Widget> left, right;
  final double gap;
  final int leftFlex, rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= twoColumnWidth
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: leftFlex,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: rightFlex,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...left,
              SizedBox(height: gap),
              ...right,
            ],
          ),
  );
}

/// Kaart: wit vlak, dunne lijn, ronde hoeken (20) en een zachte schaduw.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.shadow = true,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 20,
    this.dashed = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  /// Gestippelde rand zonder vulling, voor iets wat nog leeg is.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    Widget body = Padding(padding: padding, child: child);
    // Altijd een eigen (doorzichtige) Material: anders vallen tikeffecten van lijstregels in de kaart weg achter de achtergrond
    body = Material(
      type: MaterialType.transparency,
      child: onTap == null ? body : InkWell(onTap: onTap, customBorder: shape, child: body),
    );
    if (dashed) {
      return CustomPaint(
        painter: _DashedBorder(color: borderColor ?? p.lineStrong, radius: radius),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? p.line),
        boxShadow: shadow ? p.shadow : null,
      ),
      child: body,
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

/// Titel van een kaart, met rechts optioneel een getal of knop.
class PanelTitle extends StatelessWidget {
  const PanelTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: p.ink),
              ),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: p.ink3)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Klein bovenschrift in hoofdletters (mono), bv. "VRIJDAG · WEEK 42".
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: color ?? context.pal.ink3),
  );
}

/// Kop bovenaan een hoofdscherm: bovenschrift, grote titel en rechts knoppen.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, this.eyebrow, required this.title, this.trailing, this.titleBadge});
  final String? eyebrow;
  final String title;
  final Widget? trailing;

  /// Iets naast de titel, bv. je reeks.
  final Widget? titleBadge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 4)],
              Row(
                children: [
                  Flexible(
                    child: Text(title, style: Theme.of(context).textTheme.headlineMedium, overflow: TextOverflow.ellipsis),
                  ),
                  if (titleBadge != null) ...[const SizedBox(width: 10), titleBadge!],
                ],
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Vierkante knop met een icoon en een dunne rand (40 × 40).
class SquareButton extends StatelessWidget {
  const SquareButton({super.key, required this.icon, required this.onPressed, required this.tooltip, this.filled = false, this.size = 40});
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? p.ink : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size >= 46 ? 14 : 12),
          side: filled ? BorderSide.none : BorderSide(color: p.line),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size >= 46 ? 14 : 12)),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size >= 46 ? 22 : 18, color: filled ? p.bg : (onPressed == null ? p.ink3 : p.ink)),
          ),
        ),
      ),
    );
  }
}

/// Status als vorm én kleur, zodat het ook zonder kleurenzicht leesbaar is:
/// tekort = open ring, op doel = volle stip, te veel = driehoek.
class StatusMark extends StatelessWidget {
  const StatusMark(this.level, {super.key, this.size = 9});
  final Level level;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _MarkPainter(level, context.pal)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.level, this.p);
  final Level level;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    switch (level) {
      case Level.low:
        canvas.drawCircle(
          c,
          s / 2 - s * 0.11,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.22
            ..color = p.lowFill,
        );
      case Level.ok:
        canvas.drawCircle(c, s / 2, Paint()..color = p.okFill);
      case Level.high:
        final path = Path()
          ..moveTo(c.dx, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(path, Paint()..color = p.highFill);
      case Level.none:
        canvas.drawCircle(c, s / 2, Paint()..color = p.lineStrong);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.level != level || old.p != p;
}

extension LevelColors on Palette {
  Color fillOf(Level l) => switch (l) {
    Level.low => lowFill,
    Level.ok => okFill,
    Level.high => highFill,
    Level.none => lineStrong,
  };
  Color softOf(Level l) => switch (l) {
    Level.low => lowSoft,
    Level.ok => okSoft,
    Level.high => highSoft,
    Level.none => sunken,
  };
  Color textOf(Level l) => switch (l) {
    Level.low => low,
    Level.ok => ok,
    Level.high => high,
    Level.none => ink3,
  };
}

/// Bereikbalk: loopt tot 150% van het doel; het streepje staat op het doel, de rode zone begint bij de
/// bovengrens (of bij het maximum als de stof alleen een limiet heeft).
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.amount, required this.target, this.height = 8, this.neutral = false});
  final double amount;
  final Target? target;
  final double height;

  /// Eén product in plaats van een dag: "nog niet gehaald" krijgt geen waarschuwingskleur.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = target;
    final ref = t?.goal ?? t?.upper;
    if (t == null || ref == null || ref <= 0) return SizedBox(height: height);
    final scale = ref * 1.5;
    final level = levelOf(amount, t);
    final limit = t.upper;
    final fill = neutral && level != Level.high ? p.brand : p.fillOf(level);
    return SizedBox(
      height: height + 6,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final r = Radius.circular(height / 2);
          return Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.all(r)),
              ),
              if (limit != null && limit < scale)
                Positioned(
                  left: w * limit / scale,
                  right: 0,
                  top: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.highSoft,
                      borderRadius: BorderRadius.horizontal(right: r),
                    ),
                  ),
                ),
              Container(
                width: w * math.min(1, amount / scale),
                height: height,
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.all(r)),
              ),
              Positioned(
                left: w / 1.5 - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(1)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Eenvoudige voortgangsbalk (macro's, deel van het geheel).
class Bar extends StatelessWidget {
  const Bar({super.key, required this.fraction, required this.color, this.height = 6, this.track});
  final double fraction;
  final Color color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track ?? context.pal.track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Verdeling van de energie over eiwit, koolhydraten en vet als dunne gestapelde balk.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar(this.split, {super.key, this.height = 4, this.width});
  final (double, double, double)? split;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = split;
    final bar = s == null
        ? Container(
            height: height,
            decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(height / 2)),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (final (f, c) in [(s.$1, p.protein), (s.$2, p.carbs), (s.$3, p.fat)])
                    if (f > 0.005)
                      Expanded(
                        flex: math.max(1, (f * 1000).round()),
                        child: Container(color: c, margin: const EdgeInsets.only(right: 1.5)),
                      ),
                ],
              ),
            ),
          );
    return width == null ? bar : SizedBox(width: width, child: bar);
  }
}

/// Segmentknop in ontwerpstijl: verzonken spoor, het gekozen segment ligt er wit bovenop.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.selected, required this.onChanged, this.height = 34, this.fontSize = 13});
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final (value, label) in items)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // De gekozen optie staat duidelijk af tegen de donkere achtergrond (ook in donkere modus)
                      color: value == selected ? p.surface2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: value == selected ? Border.all(color: p.lineStrong) : null,
                      boxShadow: value == selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: value == selected ? p.ink : p.ink3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ronde keuzechip: gekozen = inkt, anders wit met een dunne rand.
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap, this.check = false, this.height = 32});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Vinkje tonen als hij gekozen is (voor meerkeuze).
  final bool check;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.ink : p.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? p.ink : p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (check && selected) ...[Icon(Icons.check_rounded, size: 14, color: p.bg), const SizedBox(width: 5)],
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? p.bg : p.ink2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Herkomst als klein label: land van de databank, OFF voor merkproducten, een icoon voor eigen producten.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});
  final FoodSource source;

  static String? codeOf(FoodSource s) => switch (s) {
    FoodSource.ciqual => 'FR',
    FoodSource.slv => 'SE',
    FoodSource.mvt => 'NO',
    FoodSource.frida => 'DK',
    FoodSource.cofid => 'UK',
    FoodSource.usda => 'US',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final code = codeOf(source);
    return Tooltip(
      message: source.labelWithCountry,
      child: Container(
        height: 22,
        constraints: const BoxConstraints(minWidth: 30),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(6)),
        child: code != null
            ? Text(code, style: numStyle(10, color: p.ink2))
            : Icon(
                switch (source) {
                  FoodSource.recipe => Icons.soup_kitchen_outlined,
                  FoodSource.off => Icons.sell_outlined,
                  _ => Icons.edit_note_rounded,
                },
                size: 15,
                color: p.ink2,
              ),
      ),
    );
  }
}

enum TagKind { gap, warn, neutral }

/// Klein label bij een zoekresultaat: wat het toevoegt aan je tekorten, een waarschuwing of een feit.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.kind = TagKind.neutral});
  final String text;
  final TagKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (bg, fg) = switch (kind) {
      TagKind.gap => (p.lowSoft, p.low),
      TagKind.warn => (p.highSoft, p.high),
      TagKind.neutral => (p.sunken, p.ink2),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          style: numStyle(11, weight: FontWeight.w500, color: fg),
        ),
      ),
    );
  }
}

/// Uitleg bij een grafiek: klein kleurstaal en tekst.
class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.swatch, required this.label});
  final Widget swatch;
  final String label;

  static Widget box(Color c, {double w = 8, double h = 8, Color? border, double radius = 2}) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(radius),
      border: border == null ? null : Border.all(color: border),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: 6),
      // Een lang label mag op een smal scherm naar de volgende regel
      Flexible(child: Text(label, style: TextStyle(fontSize: 11.5, color: context.pal.ink2))),
    ],
  );
}

/// Klein vak met een label en een getal (bv. "7-daags gem. 340 mg").
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.boxed = true});
  final String label;
  final String value;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: p.ink3),
        ),
        const SizedBox(height: 1),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: numStyle(boxed ? 15 : 17)),
      ],
    );
    if (!boxed) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface2,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}

/// Plus-min-knoppen rond een getal.
class StepButton extends StatelessWidget {
  const StepButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.size = 32});
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size >= 40 ? 12 : 9),
          side: BorderSide(color: p.lineStrong),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size >= 40 ? 12 : 9)),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size >= 40 ? 18 : 15, color: p.ink),
          ),
        ),
      ),
    );
  }
}

/// Sectiekop buiten een kaart (bv. "Maaltijden  1.842 kcal").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: numStyle(12.5, weight: FontWeight.w400, color: p.ink3),
            ),
        ],
      ),
    );
  }
}
