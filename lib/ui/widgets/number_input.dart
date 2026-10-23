/// Hulp voor getalvelden: komma of punt aanvaarden, bij aantikken alles selecteren zodat typen het oude getal
/// vervangt, en een "Klopt dit?"-vraag bij waarden die waarschijnlijk een tikfout zijn.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';

/// Getal uit een veld, met komma of punt als decimaalteken. Leeg of ongeldig geeft null.
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Voor `onTap` van een getalveld: selecteert de hele inhoud, zodat wat je typt het oude getal vervangt
/// in plaats van er cijfers tussen te zetten (100 → 102500).
VoidCallback selectAllOnTap(TextEditingController c) =>
    () => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);

/// Vraagt of een ongewone waarde echt klopt. Geeft true als de gebruiker bevestigt.
Future<bool> confirmUnusual(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Is this right?', 'Klopt dit?')),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Change it', 'Aanpassen'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Yes, save', 'Ja, bewaren'))),
      ],
    ),
  );
  return ok == true;
}

/// Foutmelding voor een veld met een verplicht bereik, of null als de waarde past (of leeg is en mag).
String? rangeError(String text, double min, double max, {String unit = '', bool optional = false}) {
  if (text.trim().isEmpty) return optional ? null : tr('Enter a number', 'Vul een getal in');
  final v = parseNum(text);
  if (v == null) return tr('Not a valid number', 'Geen geldig getal');
  if (v < min || v > max) {
    final u = unit.isEmpty ? '' : ' $unit';
    return tr('Between ${fmtNum(min)} and ${fmtNum(max)}$u', 'Tussen ${fmtNum(min)} en ${fmtNum(max)}$u');
  }
  return null;
}
