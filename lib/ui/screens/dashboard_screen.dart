import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/kit.dart';
import 'nutrients_screen.dart';
import 'trends_screen.dart';
import 'recap_screen.dart';
import 'weekly_report_screen.dart';
import '../../i18n.dart';

enum _Period { day, week, month }

/// Dashboard: alle macro's en micro's van één dag, of het gemiddelde en verloop van een week of maand.
/// Met de pijltjes blader je naar vorige dagen, weken of maanden.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _Period _period = _Period.day;
  DateTime _anchor = _today();

  static DateTime _today() {
    final n = DateTime.now();
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
        final now = DateTime.now();
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Narrow(
              child: PageHeader(
                eyebrow: _label(s),
                title: 'Dashboard',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SquareButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous', 'Vorige'), onPressed: () => _shift(s, -1)),
                    const SizedBox(width: 6),
                    SquareButton(icon: Icons.chevron_right_rounded, tooltip: tr('Next', 'Volgende'), onPressed: canNext ? () => _shift(s, 1) : null),
                  ],
                ),
              ),
            ),
            Narrow(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Segmented<_Period>(
                      items: [(_Period.day, tr('Day', 'Dag')), (_Period.week, 'Week'), (_Period.month, tr('Month', 'Maand'))],
                      selected: _period,
                      onChanged: (v) => setState(() {
                        _period = v;
                        _anchor = _period == _Period.day ? _today() : s.date;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Narrow(
              child: _period == _Period.day
                  ? const DayNutrients()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_period == _Period.month)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                                    label: Text(tr('Monthly recap', 'Maandoverzicht')),
                                    onPressed: () =>
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecapScreen(from: from, year: false))),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.celebration_rounded, size: 18),
                                    label: Text(tr('Year ${from.year}', 'Jaar ${from.year}')),
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
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.insights_rounded, size: 18),
                              label: Text(tr('Weekly report', 'Weekrapport')),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyReportScreen(monday: from))),
                            ),
                          ),
                        PeriodTrends(key: ValueKey('$from'), from: from, to: to),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
