/// Taal van de app. Engels is de standaard; Nederlands is al volledig beschikbaar als keuze.
///
/// Elke tekst staat in de code als `tr('English', 'Nederlands')`, zodat beide versies naast elkaar staan en
/// variabelen (`$naam`) in beide werken. Voor een derde taal wordt dit later een sleutel per tekst.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum AppLang {
  en('English'),
  nl('Nederlands');

  const AppLang(this.label);
  final String label;
}

/// Huidige taal. De app bouwt opnieuw op als ze verandert.
final appLang = ValueNotifier<AppLang>(AppLang.en);

bool get isNl => appLang.value == AppLang.nl;

/// Tekst in de huidige taal.
String tr(String en, String nl) => isNl ? nl : en;

/// Locale voor datums en getallen.
String get appLocale => isNl ? 'nl_BE' : 'en_GB';

void setAppLang(AppLang lang) {
  Intl.defaultLocale = lang == AppLang.nl ? 'nl_BE' : 'en_GB';
  appLang.value = lang;
}

/// Decimaalteken van de taal: komma in het Nederlands, punt in het Engels ("1.5" wordt "1,5").
extension LocalDecimal on String {
  String get dec => isNl ? replaceAll('.', ',') : this;
}

/// Getal met hoogstens [d] decimalen, zonder overbodige nullen ("20.0" wordt "20", "0.90" wordt "0.9"),
/// met het decimaalteken van de taal.
String fmtNum(num v, [int d = 1]) {
  var s = v.toStringAsFixed(d);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return s.dec;
}
