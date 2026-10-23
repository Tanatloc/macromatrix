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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _block();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _block();

  /// Rond de app (MaterialApp.builder): laat geen tikken door zolang [blocked] waar is.
  Widget wrap(Widget? child) => ValueListenableBuilder<bool>(
    valueListenable: blocked,
    builder: (_, ignoring, child) => IgnorePointer(ignoring: ignoring, child: child),
    child: child,
  );
}

final tapGuard = TapGuard();
