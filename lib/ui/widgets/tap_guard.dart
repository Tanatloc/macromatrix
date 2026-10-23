/// Na het openen of sluiten van een scherm heel even geen tikken: een snelle tweede tik op "Toevoegen" landt anders
/// op het scherm eronder (een product openen of een dag wisselen zonder het te willen).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

class TapGuard extends NavigatorObserver {
  /// True zolang tikken genegeerd worden.
  final blocked = ValueNotifier(false);
  Timer? _timer;

  void _block() {
    _timer?.cancel();
    blocked.value = true;
    _timer = Timer(const Duration(milliseconds: 300), () => blocked.value = false);
  }

  // Alleen bij een volledige schermwissel kort blokkeren. Een dialoog, menu of blad (PopupRoute) openen we NIET
  // blokkeren: daar wil je meteen in tikken, en de bescherming slikte anders de eerste tik in (bv. 'Alles
  // selecteren', 'Kopieer van gisteren', een activiteit kiezen).
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _block();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Bij het sluiten wel kort blokkeren, zodat de tik die sloot niet op het scherm eronder landt.
    _block();
  }

  /// Rond de app (MaterialApp.builder): laat geen tikken door zolang [blocked] waar is.
  Widget wrap(Widget? child) => ValueListenableBuilder<bool>(
    valueListenable: blocked,
    builder: (_, ignoring, child) => IgnorePointer(ignoring: ignoring, child: child),
    child: child,
  );
}

final tapGuard = TapGuard();
