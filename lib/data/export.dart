/// Export van het dagboek naar CSV. In het Nederlands met puntkomma en decimale komma (zo opent Excel het in
/// België en Nederland meteen goed), in het Engels met komma en decimale punt.
library;

import '../i18n.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/values.dart';
import 'user_db.dart';

String diaryCsv(UserDb db, {String from = '0000-01-01', String to = '9999-12-31'}) {
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
    final a = withDerived(e.amounts);
    lines.add([e.day, e.time, e.meal.label, e.name, e.brand, e.grams, for (final n in nutrients) a[n.key]].map(cell).join(sep));
  }
  return '${lines.join('\n')}\n';
}
