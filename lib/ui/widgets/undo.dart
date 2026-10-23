/// Eén melding met "Ongedaan maken" voor alles wat je verwijdert, zodat een misklik nooit iets kost.
library;

import 'package:flutter/material.dart';

import '../../i18n.dart';

/// Toont [message] met een knop om [onUndo] uit te voeren. Blijft 10 seconden staan: lang genoeg om te
/// merken dat je mis tikte. Geef de [messenger] mee als het scherm zelf meteen sluit.
void showUndo(BuildContext? context, String message, VoidCallback onUndo, {ScaffoldMessengerState? messenger}) {
  final m = messenger ?? ScaffoldMessenger.of(context!);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Met een knop blijft een SnackBar standaard staan tot je tikt; deze moet vanzelf verdwijnen
        persist: false,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: tr('Undo', 'Ongedaan maken'), onPressed: onUndo),
      ),
    );
}
