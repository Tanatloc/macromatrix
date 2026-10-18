/// Health Connect (Android): stappen, workouts en gewicht automatisch overnemen.
///
/// - Workouts met verbrande energie worden beweging (en tellen dus mee in je energiedoel als dat aanstaat).
/// - Stappen per dag worden een meting "Stappen" (ze tellen niet mee in je doel: dat zit al in je activiteitsniveau).
/// - Gewicht wordt een meting "Gewicht" (de laatste van de dag), en geldt meteen voor je doelen.
/// Alleen lezen; MacroMatrix schrijft niets naar Health Connect. Andere platformen: niets.
library;

export 'health_sync_native.dart' if (dart.library.js_interop) 'health_sync_web.dart';
