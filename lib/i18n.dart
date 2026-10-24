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

/// Taal van het toestel (of de browser): Nederlands als de eerste voorkeurstaal Nederlands is, anders Engels.
AppLang get deviceLang {
  final locales = PlatformDispatcher.instance.locales;
  final first = locales.isEmpty ? PlatformDispatcher.instance.locale : locales.first;
  return first.languageCode == 'nl' ? AppLang.nl : AppLang.en;
}

void setAppLang(AppLang lang) {
  Intl.defaultLocale = lang == AppLang.nl ? 'nl_BE' : 'en_GB';
  appLang.value = lang;
}

/// Decimaalteken van de taal: komma in het Nederlands, punt in het Engels ("1.5" wordt "1,5").
extension LocalDecimal on String {
  String get dec => isNl ? replaceAll('.', ',') : this;
}

/// Naam midden in een zin: "Vitamine D" wordt "vitamine D", "Jodium" wordt "jodium", "B12" blijft.
String inSentence(String name) =>
    name.length > 1 && name[1] == name[1].toLowerCase() && name[1] != name[1].toUpperCase() ? name[0].toLowerCase() + name.substring(1) : name;

/// Getal met hoogstens [d] decimalen, zonder overbodige nullen ("20.0" wordt "20", "0.90" wordt "0.9"),
/// met het decimaalteken van de taal.
String fmtNum(num v, [int d = 1]) {
  var s = v.toStringAsFixed(d);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return s.dec;
}

/// Zoals [fmtNum], maar met duizendtallen volgens de taal ("1.022,5" of "1,022.5"), voor getallen die je alleen
/// leest. Niet voor invoervelden: daar zou "1.200" als 1,2 gelezen worden.
String fmtGrouped(num v, [int d = 1]) {
  var s = fmtNum(v, d);
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final at = s.indexOf(isNl ? ',' : '.');
  final whole = at < 0 ? s : s.substring(0, at);
  final rest = at < 0 ? '' : s.substring(at);
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(isNl ? '.' : ',');
    b.write(whole[i]);
  }
  return '${neg ? '-' : ''}$b$rest';
}

// Woorden van portienamen in beide talen, langste eerst. Een portie komt als tekst in het dagboek, in de taal van dat
// moment ("1 stuk (≈120 g)"); bij het tonen zetten we ze om naar de huidige taal, zodat "1 stuk" en "1 piece" niet
// door elkaar staan. Bij twee vertalingen wint de eerste ("slice" wordt "sneetje", "punt" wordt "slice").
const _portionWords = <(String, String)>[
  ('on a slice', 'op een boterham'),
  ('small bag', 'klein zakje'),
  ('teaspoon', 'koffielepel'),
  ('tablespoon', 'eetlepel'),
  ('scoop', 'schep'),
  ('shot', 'borrel'),
  ('glass', 'glas'),
  ('mug', 'mok'),
  ('bowl', 'kom'),
  ('bag', 'zakje'),
  ('slice', 'sneetje'),
  ('slice', 'punt'),
  ('slice', 'stuk taart'),
  ('piece', 'stuk'),
  ('pcs', 'stuk'),
  ('serving', 'portie'),
  ('portion', 'portie'),
];

final _portionLead = RegExp(r'^((?:\d+(?:[.,]\d+)?|½|¼|¾)\s+)?(.+)$');

/// Portienaam in de huidige taal: alleen het woord vooraan ("1 pcs", "1 sneetje (≈35 g)", "1 portion (150 g)") wordt
/// vertaald; de rest (grammen, uitleg van de databank) blijft zoals hij is. "pcs" wordt in het Engels "piece".
String portionInLang(String label) {
  final m = _portionLead.firstMatch(label);
  if (m == null) return label;
  var rest = m.group(2)!;
  final lower = rest.toLowerCase();
  final pairs = isNl ? _portionWords : [for (final (en, nl) in _portionWords) (nl, en), ('pcs', 'piece')];
  for (final (from, to) in pairs) {
    if (lower.startsWith(from) && (lower.length == from.length || !RegExp(r'[a-zà-ÿ]').hasMatch(lower[from.length]))) {
      rest = to + rest.substring(from.length);
      break;
    }
  }
  rest = isNl ? rest.replaceFirst(' of the recipe)', ' van het recept)') : rest.replaceFirst(' van het recept)', ' of the recipe)');
  return '${m.group(1) ?? ''}$rest';
}

/// Zelfde portie, ook als de ene in het Engels en de andere in het Nederlands bewaard is.
bool samePortion(String? a, String? b) => a != null && b != null && (a == b || portionInLang(a) == portionInLang(b));
