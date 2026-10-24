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

String _day(String day) => day.split('-').reversed.join('/');

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
    // Geen tweede score naast de Voedingsscore: alleen het oordeel in woorden, en in woorden hoe het tegenover
    // vorige week staat
    final vsLastWeek = switch (change) {
      null => null,
      final d when d >= 5 => tr('Better than last week', 'Beter dan vorige week'),
      final d when d <= -5 => tr('Less good than last week', 'Minder goed dan vorige week'),
      _ => tr('About the same as last week', 'Ongeveer zoals vorige week'),
    };
    final work = c.toWorkOn;
    final shown = work.take(maxWorkPoints).toList();
    final more = [
      ...work.skip(maxWorkPoints),
      for (final f in c.factors)
        if (f.rating == HealthRating.unknown) f,
    ];
    final labDay = c.labDay == null ? null : _day(c.labDay!);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink2),
      ),
    );
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
                    if (vsLastWeek != null)
                      Text(
                        vsLastWeek,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: change! >= 5 ? p.ok : (change! <= -5 ? p.low : p.ink2)),
                      ),
                    Text(
                      tr(
                        'Averages of ${c.days} fully logged ${c.days == 1 ? 'day' : 'days'}',
                        'Gemiddelden van ${c.days} volledig gelogde ${c.days == 1 ? 'dag' : 'dagen'}',
                      ),
                      style: TextStyle(fontSize: 12, color: p.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(c.summary, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink)),
          // Eerst wat goed gaat, dan hooguit drie werkpunten met meteen wat je kunt doen
          if (c.goingWell.isNotEmpty) ...[heading(tr('Going well', 'Goed bezig')), for (final f in c.goingWell) _FactorRow(f, labDay: labDay)],
          if (shown.isNotEmpty) ...[heading(tr('To work on', 'Werkpunten')), for (final f in shown) _FactorRow(f, labDay: labDay, showAdvice: true)],
          if (more.isNotEmpty)
            _MoreInfo(
              title: tr('More points (${more.length})', 'Meer punten (${more.length})'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final f in more) _FactorRow(f, labDay: labDay)],
              ),
            ),
          const SizedBox(height: 8),
          if (c.labDay != null && c.factors.any((f) => f.bloodTips.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.bloodtype_rounded, size: 16, color: p.high),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('Includes your blood test of ${_day(c.labDay!)}', 'Met je bloedafname van ${_day(c.labDay!)}'),
                    style: TextStyle(fontSize: 12.5, color: p.ink2),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          _MoreInfo(
            title: tr('About these figures', 'Over deze cijfers'),
            child: Text(
              tr(
                'Averages of ${c.days} fully logged days, judged against the guidelines of EFSA, the WHO and the Belgian Superior Health Council. The figures under "Why it matters" come from large studies: averages and associations that show roughly what is at stake, not a prediction for you. Not medical advice.',
                'Gemiddelden van ${c.days} volledig gelogde dagen, beoordeeld met de richtlijnen van EFSA, de WHO en de Hoge Gezondheidsraad. De cijfers onder "Waarom het telt" komen uit grote studies: gemiddelden en verbanden die tonen wat ongeveer op het spel staat, geen voorspelling voor jou. Geen medisch advies.',
              ),
              style: TextStyle(fontSize: 11.5, color: p.ink3),
            ),
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

/// Eén factor: naam, waarde, doel en oordeel; aantikken toont de uitleg. Bij een werkpunt ([showAdvice]) staat wat
/// je kunt doen er meteen onder.
class _FactorRow extends StatefulWidget {
  const _FactorRow(this.f, {this.labDay, this.showAdvice = false});
  final HealthFactor f;
  final bool showAdvice;

  /// Datum van de bloedafname, al opgemaakt (bv. 20/10/2025).
  final String? labDay;

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
    return InkWell(
      // Dicht: één regel per punt; open: uitleg, impact, advies en wat voor jou geldt
      onTap: () => setState(() => _open = !_open),
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
                        // Het doel waartegen het oordeel geldt
                        if (f.aim != null && f.rating != HealthRating.unknown)
                          TextSpan(
                            text: ' · ${f.aim}',
                            style: TextStyle(fontSize: 12, color: p.ink3),
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
                // Advies uit je bloedwaarden: zichtbaar zonder het punt te openen
                if (f.bloodTips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: tr('Advice based on your blood test', 'Advies op basis van je bloedafname'),
                      child: Icon(Icons.bloodtype_rounded, size: 16, color: p.high),
                    ),
                  ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                child: Text(f.effect, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2)),
              ),
            if (f.advice != null && f.advice!.isNotEmpty && (_open || widget.showAdvice))
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6),
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
            if (_open) ...[
              // Cijfers uit grote studies (ook over levensverwachting): niet standaard in beeld, wel voor wie wil
              if (f.impact != null)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 4),
                  child: _MoreInfo(
                    title: tr('Why it matters', 'Waarom het telt'),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 21, bottom: 4),
                      child: Text(f.impact!, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink)),
                    ),
                  ),
                ),
              if (f.bloodTips.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 10),
                  child: Row(
                    children: [
                      Icon(Icons.bloodtype_rounded, size: 16, color: p.high),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.labDay == null
                              ? tr('Based on your blood test', 'Op basis van je bloedafname')
                              : tr('Based on your blood test of ${widget.labDay}', 'Op basis van je bloedafname van ${widget.labDay}'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final t in f.bloodTips)
                  Padding(
                    padding: const EdgeInsets.only(left: 42, top: 4),
                    child: Text(t, style: TextStyle(fontSize: 13, height: 1.4, color: p.ink)),
                  ),
              ],
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

/// Een kopje dat je openklapt voor extra uitleg.
class _MoreInfo extends StatefulWidget {
  const _MoreInfo({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  State<_MoreInfo> createState() => _MoreInfoState();
}

class _MoreInfoState extends State<_MoreInfo> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: p.ink3),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink3),
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: p.ink3),
              ],
            ),
          ),
        ),
        if (_open) widget.child,
      ],
    );
  }
}
