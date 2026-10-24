import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/feature_gate.dart';
import '../widgets/kit.dart';
import 'nutrients_screen.dart';
import 'trends_screen.dart';
import 'recap_screen.dart';
import 'weekly_report_screen.dart';
import '../../i18n.dart';

enum _Period { day, week, month }

/// Dashboard: alle macro's en micro's van één dag, of het gemiddelde en verloop van een week of maand.
/// Met de pijltjes blader je naar vorige dagen, weken of maanden.
/// Telkens [showDay] afgaat (bv. "Alle voedingsstoffen" in het dagboek), springt het terug naar de dagweergave:
/// die volgt de dag die in het dagboek gekozen is. Telkens [showWeek] afgaat (de kaart "Laatste 7 dagen"), springt
/// het naar de week van die dag. Met [startOnWeek] opent het meteen op Week.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.showDay, this.showWeek, this.startOnWeek = false, this.active = true});
  final Listenable? showDay;
  final Listenable? showWeek;
  final bool startOnWeek;

  /// Is dit tabblad zichtbaar? Kom je terug naar het dashboard, dan begint het weer bovenaan (N83).
  final bool active;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late _Period _period = widget.startOnWeek ? _Period.week : _Period.day;
  late DateTime _anchor = widget.startOnWeek ? context.read<AppState>().date : _today();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.showDay?.addListener(_toDay);
    widget.showWeek?.addListener(_toWeek);
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.showDay != widget.showDay) {
      old.showDay?.removeListener(_toDay);
      widget.showDay?.addListener(_toDay);
    }
    if (old.showWeek != widget.showWeek) {
      old.showWeek?.removeListener(_toWeek);
      widget.showWeek?.addListener(_toWeek);
    }
    // Terug naar dit tabblad: bovenaan beginnen, anders tik je op wat toevallig onder de vinger staat
    if (widget.active && !old.active && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    widget.showDay?.removeListener(_toDay);
    widget.showWeek?.removeListener(_toWeek);
    super.dispose();
  }

  /// Naar de weekweergave van de dag die in het dagboek gekozen is (N16).
  void _toWeek() {
    if (!mounted) return;
    setState(() {
      _period = _Period.week;
      _anchor = context.read<AppState>().date;
    });
  }

  /// Terug naar de dagweergave (de dag zelf staat in AppState.date).
  void _toDay() {
    if (!mounted) return;
    setState(() {
      _period = _Period.day;
      _anchor = context.read<AppState>().date;
    });
  }

  static DateTime _today() {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day);
  }

  /// Eerste en laatste dag van de gekozen week of maand (nooit later dan vandaag).
  (DateTime, DateTime) get _range {
    final today = _today();
    final (from, end) = switch (_period) {
      _Period.week => (
        DateTime(_anchor.year, _anchor.month, _anchor.day - (_anchor.weekday - 1)),
        DateTime(_anchor.year, _anchor.month, _anchor.day - (_anchor.weekday - 1) + 6),
      ),
      _ => (DateTime(_anchor.year, _anchor.month, 1), DateTime(_anchor.year, _anchor.month + 1, 0)),
    };
    return (from, end.isAfter(today) ? today : end);
  }

  bool get _atToday => _range.$2 == _today();

  void _shift(AppState s, int dir) {
    setState(() {
      switch (_period) {
        case _Period.day:
          s.shiftDay(dir);
        case _Period.week:
          _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * dir);
        case _Period.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
      }
    });
  }

  String _label(AppState s) {
    final today = _today();
    switch (_period) {
      case _Period.day:
        final diff = (s.date.difference(today).inHours / 24).round();
        return switch (diff) {
          0 => tr('Today', 'Vandaag'),
          -1 => tr('Yesterday', 'Gisteren'),
          _ => toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', appLocale).format(s.date)),
        };
      case _Period.week:
        final (from, _) = _range;
        final end = DateTime(from.year, from.month, from.day + 6);
        final f = DateFormat('d MMM', appLocale);
        final thisWeek = _atToday && today.difference(from).inDays < 7;
        return thisWeek ? tr('This week', 'Deze week') : '${f.format(from)} – ${f.format(end)}';
      case _Period.month:
        final now = logicalNow();
        return _anchor.year == now.year && _anchor.month == now.month
            ? tr('This month', 'Deze maand')
            : toBeginningOfSentenceCase(DateFormat(_anchor.year == now.year ? 'MMMM' : 'MMMM yyyy', appLocale).format(_anchor));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final canNext = _period == _Period.day ? !s.isToday : !_atToday;
    final (from, to) = _range;

    final segmented = Segmented<_Period>(
      items: [(_Period.day, tr('Day', 'Dag')), (_Period.week, 'Week'), (_Period.month, tr('Month', 'Maand'))],
      selected: _period,
      onChanged: (v) => setState(() {
        _period = v;
        _anchor = _period == _Period.day ? _today() : s.date;
      }),
    );

    // Bovenop een ander scherm geopend (niet als tabblad): een terugpijl, want er is dan geen menubalk (N16)
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, c) {
            // Op een pc: breder, met dag/week/maand naast de titel
            final wide = c.maxWidth >= twoColumnWidth;
            final mw = wide ? wideMaxWidth : 760.0;
            return ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (canPop)
                  Narrow(
                    maxWidth: mw,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(padding: EdgeInsets.only(left: 8, top: 4), child: BackButton()),
                    ),
                  ),
                Narrow(
                  maxWidth: mw,
                  child: PageHeader(
                    eyebrow: _label(s),
                    title: 'Dashboard',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wide) ...[SizedBox(width: 340, child: segmented), const SizedBox(width: 12)],
                        SquareButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous', 'Vorige'), onPressed: () => _shift(s, -1)),
                        const SizedBox(width: 6),
                        SquareButton(
                          icon: Icons.chevron_right_rounded,
                          tooltip: tr('Next', 'Volgende'),
                          onPressed: canNext ? () => _shift(s, 1) : null,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!wide)
                  Narrow(
                    child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: segmented),
                  ),
                if (_period == _Period.day)
                  const DayNutrients()
                else
                  Narrow(
                    maxWidth: mw,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_period == _Period.month)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                // In een lege maand valt er niets samen te vatten: alleen het jaar
                                if (s.dailyTotals(from, to).isNotEmpty) ...[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                                      label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Monthly recap', 'Maandoverzicht'), maxLines: 1)),
                                      onPressed: () =>
                                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecapScreen(from: from, year: false))),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.celebration_rounded, size: 18),
                                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Year ${from.year}', 'Jaar ${from.year}'), maxLines: 1)),
                                    onPressed: () =>
                                        Navigator.of(context)
                                            .push(MaterialPageRoute(builder: (_) => RecapScreen(from: DateTime(from.year), year: true))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_period == _Period.week)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              // Op een gsm over de hele breedte, op een pc gewoon een knop
                              child: SizedBox(
                                width: wide ? null : double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.insights_rounded, size: 18),
                                  // Met de coach erbij zeggen we dat ook, anders zoek je hem niet in het weekrapport
                                  label: Text(
                                    featureOn(context, 'coach')
                                        ? tr('Weekly report and coach', 'Weekrapport en coach')
                                        : tr('Weekly report', 'Weekrapport'),
                                  ),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyReportScreen(monday: from))),
                                ),
                              ),
                            ),
                          ),
                        PeriodTrends(key: ValueKey('$from'), from: from, to: to),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
