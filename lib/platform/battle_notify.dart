/// Melding op de gsm als een vriend je uitdaagt voor een battle (Android). Elders: niets.
library;

export 'battle_notify_native.dart' if (dart.library.js_interop) 'battle_notify_web.dart';
