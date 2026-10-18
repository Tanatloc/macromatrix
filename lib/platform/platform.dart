/// Verschillen tussen platformen: gsm en pc (bestanden, sqlite als bibliotheek) tegenover de browser
/// (sqlite als WebAssembly, opslag in IndexedDB, downloads via de browser).
library;

export 'platform_native.dart' if (dart.library.js_interop) 'platform_web.dart';
