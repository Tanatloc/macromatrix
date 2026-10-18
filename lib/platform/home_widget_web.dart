import '../state/app_state.dart';

/// Geen widget in de browser.
class HomeWidgetSync {
  static Future<void> update(AppState s) async {}
  static Future<Uri?> launchUri() async => null;
  static Stream<Uri?> get clicks => const Stream.empty();
}
