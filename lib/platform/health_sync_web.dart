import '../state/app_state.dart';

/// Geen Health Connect in de browser.
class HealthSync {
  HealthSync(AppState state);
  static bool get supported => false;
  bool get enabled => false;
  Future<bool> enable() async => false;
  void disable() {}
  Future<int> sync() async => 0;
  DateTime? get lastSync => null;
}
