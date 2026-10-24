import 'dart:async';

import 'package:macromatrix/ui/widgets/avatar_frame.dart';

/// Voor alle tests: supporterranden staan stil, zodat pumpAndSettle niet blijft wachten op een animatie die nooit
/// stopt. Een test die de beweging zelf nakijkt, zet [avatarFrameAnimations] tijdelijk weer aan.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  avatarFrameAnimations = false;
  await testMain();
}
