/// Export van het dagboek naar CSV. In het Nederlands met puntkomma en decimale komma (zo opent Excel het in
/// België en Nederland meteen goed), in het Engels met komma en decimale punt.
library;

import '../i18n.dart';
import '../nutrition/free_sugars.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/values.dart';
import 'user_db.dart';

/// [values] geeft de waarden van één regel zoals ze in de totalen tellen (in de app `AppState.entryValues`, met de
/// vrije suikers uit het label of de ingrediënten). Zonder [values] schatten we de vrije suikers alleen uit de naam.
String diaryCsv(UserDb db, {String from = '0000-01-01', String to = '9999-12-31', NutrientMap Function(DiaryEntry e)? values}) {
  final sep = isNl ? ';' : ',';
  String cell(Object? v) {
    if (v == null) return '';
    if (v is double) {
      final s = v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return isNl ? s.replaceAll('.', ',') : s;
    }
    final s = '$v';
    return s.contains(RegExp('[$sep"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final header = [
    ...(isNl ? ['datum', 'tijd', 'maaltijd', 'product', 'merk', 'gram'] : ['date', 'time', 'meal', 'product', 'brand', 'grams']),
    for (final n in nutrients) '${n.name} (${n.unit})',
  ];
  final lines = [header.map(cell).join(sep)];
  for (final e in db.entriesBetween(from, to)) {
    final a = values?.call(e) ?? withDerived(scale(withFreeSugars(e.per100g, name: e.name), e.grams));
    lines.add([e.day, e.time, e.meal.label, e.name, e.brand, e.grams, for (final n in nutrients) a[n.key]].map(cell).join(sep));
  }
  return '${lines.join('\n')}\n';
}
