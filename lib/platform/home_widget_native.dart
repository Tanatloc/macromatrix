import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../i18n.dart';
import '../state/app_state.dart';

/// Gegevens voor het Android-widget (MacroMatrixWidget.kt leest ze uit de gedeelde voorkeuren).
class HomeWidgetSync {
  static String? _last;

  static Future<void> update(AppState s) async {
    if (!Platform.isAndroid) return;
    final t = s.todaySummary;
    final streak = s.streak.current;
    final left = t.left >= 0 ? t.left : -t.left;
    final data = <String, String>{
      'kcal': NumberFormat.decimalPattern(appLocale).format(left),
      'kcal_label': t.left >= 0 ? tr('kcal left', 'kcal over') : tr('kcal over goal', 'kcal boven doel'),
      'streak': '$streak',
      'streak_label': streak == 1 ? tr('day', 'dag') : tr('days', 'dagen'),
      'log_label': tr('Log', 'Loggen'),
      'hint': t.loggedToday ? '' : tr('Not logged yet today', 'Vandaag nog niets gelogd'),
    };
    final sig = data.values.join('|');
    if (sig == _last) return;
    _last = sig;
    try {
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(androidName: 'MacroMatrixWidget');
    } on Exception {
      // Geen widget geplaatst of plugin niet beschikbaar: niets aan de hand
    }
  }

  /// Werd de app geopend via het widget (bv. macromatrix://quicklog)?
  static Future<Uri?> launchUri() async => Platform.isAndroid ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
  static Stream<Uri?> get clicks => Platform.isAndroid ? HomeWidget.widgetClicked : const Stream.empty();
}
