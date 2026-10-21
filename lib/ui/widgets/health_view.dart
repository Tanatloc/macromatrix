import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../nutrition/health.dart';
import '../../nutrition/insights.dart';
import '../screens/labs_screen.dart';
import '../theme.dart';
import 'kit.dart';

/// Dezelfde vormen en kleuren als bij voedingsstoffen: goed = volle stip, oké = ring, slecht = driehoek.
Level levelOfRating(HealthRating r) => switch (r) {
  HealthRating.good => Level.ok,
  HealthRating.ok => Level.low,
  HealthRating.poor => Level.high,
  HealthRating.unknown => Level.none,
};

/// Gezondheidsdeel van het weekrapport: eindoordeel, score en per factor wat het met je gezondheid doet.
class HealthPanel extends StatelessWidget {
  const HealthPanel({super.key, required this.check, this.change, this.hasLabs});
  final HealthCheck? check;

  /// Of je bloedwaarden hebt ingevuld; null = geen knop naar de bloedwaarden.
  final bool? hasLabs;

  /// Verschil in score met vorige week.
  final int? change;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = check;
    final title = PanelTitle(
      tr('Health', 'Gezondheid'),
      subtitle: c != null && c.hasActivity
          ? tr('How your eating and exercise affect your health', 'Hoe je eten en bewegen je gezondheid beïnvloeden')
          : tr('How your eating affects your health', 'Hoe je eten je gezondheid beïnvloedt'),
    );
    if (c == null) {
      return Panel(
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 10),
            Text(
              tr(
                'Log at least $healthMinDays full days in a week to get a health verdict.',
                'Log minstens $healthMinDays volledige dagen in een week om een gezondheidsoordeel te krijgen.',
              ),
              style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
            ),
          ],
        ),
      );
    }
    final level = levelOfRating(c.rating);
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: p.softOf(level), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusMark(level, size: 12),
                    const SizedBox(width: 8),
                    Text(
                      c.rating.label,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.textOf(level)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${c.score}', style: numStyle(24, color: p.ink)),
                        Text(' / 100', style: numStyle(13, color: p.ink3)),
                      ],
                    ),
                    if (change != null)
                      Text(
                        '${change! > 0 ? '▲' : (change! < 0 ? '▼' : '=')} ${change!.abs()} ${tr('vs last week', 't.o.v. vorige week')}',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: change! >= 0 ? p.ok : p.low),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(c.summary, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink)),
          if (c.biggestGain case final g?) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.trending_up_rounded, size: 20, color: p.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${tr('Biggest gain', 'Grootste winst')}: ${g.title.toLowerCase()}. ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: g.impact),
                        ],
                      ),
                      style: TextStyle(fontSize: 13, height: 1.4, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final f in c.factors) _FactorRow(f),
          const SizedBox(height: 10),
          Text(
            tr(
              'Based on ${c.days} fully logged days and the guidelines of EFSA, the WHO and the Belgian Superior Health Council. The impact figures come from large studies: averages and associations that show roughly what is at stake, not a prediction for you. Not medical advice.',
              'Op basis van ${c.days} volledig gelogde dagen en de richtlijnen van EFSA, de WHO en de Hoge Gezondheidsraad. De cijfers over impact komen uit grote studies: gemiddelden en verbanden die tonen wat ongeveer op het spel staat, geen voorspelling voor jou. Geen medisch advies.',
            ),
            style: TextStyle(fontSize: 11.5, color: p.ink3),
          ),
          if (hasLabs != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.bloodtype_outlined, size: 18),
                label: Text(
                  !hasLabs!
                      ? tr('Add your blood values for advice that fits your blood', 'Voeg je bloedwaarden toe voor advies dat bij je bloed past')
                      : tr('Your blood values', 'Je bloedwaarden'),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LabsScreen())),
              ),
            ),
        ],
      ),
    );
  }
}

/// Eén factor: naam, waarde en oordeel; aantikken toont wat je kunt doen.
class _FactorRow extends StatefulWidget {
  const _FactorRow(this.f);
  final HealthFactor f;

  @override
  State<_FactorRow> createState() => _FactorRowState();
}

class _FactorRowState extends State<_FactorRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = widget.f;
    final level = levelOfRating(f.rating);
    final more = f.advice != null || f.note != null || f.tips.isNotEmpty;
    return InkWell(
      onTap: more ? () => setState(() => _open = !_open) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusMark(level, size: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: f.title,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                        ),
                        TextSpan(
                          text: '  ${f.value}',
                          style: numStyle(12.5, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  f.rating.label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.textOf(level)),
                ),
                if (more) Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: Text(f.effect, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2)),
            ),
            if (f.impact != null)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.insights_rounded, size: 15, color: p.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f.impact!, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink)),
                    ),
                  ],
                ),
              ),
            if (_open) ...[
              if (f.advice != null)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 16, color: p.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(f.advice!, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink)),
                      ),
                    ],
                  ),
                ),
              for (final t in f.tips)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person_outline_rounded, size: 16, color: p.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(t, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink)),
                      ),
                    ],
                  ),
                ),
              if (f.note != null)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 6),
                  child: Text(f.note!, style: TextStyle(fontSize: 11.5, color: p.ink3)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
