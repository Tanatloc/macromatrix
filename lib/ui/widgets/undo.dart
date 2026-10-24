/// Eén melding met "Ongedaan maken" voor alles wat je verwijdert, zodat een misklik nooit iets kost.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';

/// Toont [message] met een knop om [onUndo] uit te voeren. Blijft 10 seconden staan: lang genoeg om te
/// merken dat je mis tikte. Geef de [messenger] mee als het scherm zelf meteen sluit.
///
/// [top]: de melding bovenaan tonen, waar ze geen knoppen in een lijst bedekt (bv. de + bij Recent gebruikt).
/// Een tik op "Ongedaan maken" in de eerste halve seconde telt niet: dat is bijna altijd een snelle tweede tik op
/// de knop eronder, geen bewuste keuze (N03).
void showUndo(BuildContext? context, String message, VoidCallback onUndo, {ScaffoldMessengerState? messenger, bool top = false}) {
  final m = messenger ?? ScaffoldMessenger.of(context!);
  final shown = DateTime.now();
  final height = context == null ? null : MediaQuery.maybeSizeOf(context)?.height;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Met een knop blijft een SnackBar standaard staan tot je tikt; deze moet vanzelf verdwijnen
        persist: false,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: top && height != null ? EdgeInsets.fromLTRB(16, 0, 16, height - 150) : null,
        action: SnackBarAction(
          label: tr('Undo', 'Ongedaan maken'),
          onPressed: () {
            if (DateTime.now().difference(shown) < const Duration(milliseconds: 500)) return;
            onUndo();
          },
        ),
      ),
    );
}
