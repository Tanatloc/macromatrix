/// Na het openen of sluiten van een scherm heel even geen tikken: een snelle tweede tik op "Toevoegen" landt anders
/// op het scherm eronder (een product openen of een dag wisselen zonder het te willen).
///
/// De schermen van een tabblad staan in een eigen navigator (zie shell.dart). Die krijgt [TapGuard.observer], anders
/// merkte de bescherming het sluiten van een productscherm niet en viel een snelle tweede tik op "Toevoegen" op
/// de grote + van de onderbalk (N03). De blokkering geldt voor de hele app, dus ook voor de onderbalk.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class TapGuard extends NavigatorObserver {
  /// True zolang tikken genegeerd worden.
  final blocked = ValueNotifier(false);
  Timer? _timer;

  void _block([Duration d = const Duration(milliseconds: 300)]) {
    _timer?.cancel();
    _timer = Timer(d, () => blocked.value = false);
    // Een navigator die tijdens het bouwen ontstaat of verandert (de tabbladen), mag de app niet midden in die
    // bouwbeurt laten herbouwen: dan na dit beeld
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_timer?.isActive ?? false) blocked.value = true;
      });
    } else {
      blocked.value = true;
    }
  }

  /// Een waarnemer voor een geneste navigator (een navigator kan maar één keer dezelfde waarnemer hebben).
  NavigatorObserver observer() => _NestedGuard(this);

  // Alleen bij een volledige schermwissel kort blokkeren. Een dialoog, menu of blad (PopupRoute) openen we NIET
  // blokkeren: daar wil je meteen in tikken, en de bescherming slikte anders de eerste tik in (bv. 'Alles
  // selecteren', 'Kopieer van gisteren', een activiteit kiezen).
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _block();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Bij het sluiten wel kort blokkeren, zodat de tik die sloot niet op het scherm eronder landt. Iets langer dan
    // bij openen: een dubbele tik op "Toevoegen" heeft zijn tweede tik soms pas na 300 ms.
    _block(const Duration(milliseconds: 400));
  }

  /// Rond de app (MaterialApp.builder): laat geen tikken door zolang [blocked] waar is.
  Widget wrap(Widget? child) => ValueListenableBuilder<bool>(
    valueListenable: blocked,
    builder: (_, ignoring, child) => IgnorePointer(ignoring: ignoring, child: child),
    child: child,
  );
}

class _NestedGuard extends NavigatorObserver {
  _NestedGuard(this.guard);
  final TapGuard guard;

  // Het beginscherm van een tabblad (zonder vorig scherm) is geen schermwissel
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) guard.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => guard.didPop(route, previousRoute);
}

final tapGuard = TapGuard();

/// Een dubbele tik op × wist niet ook de regel die eronder opschuift (N04): kort na een verwijdering doet een
/// volgende × niets.
class RemoveGuard {
  Timer? _lock;

  /// True als deze verwijdering mag; zet dan de korte blokkering.
  bool allow() {
    if (_lock?.isActive ?? false) return false;
    _lock = Timer(const Duration(milliseconds: 600), () {});
    return true;
  }
}
