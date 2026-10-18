import '../state/app_state.dart';
import '../sync/account.dart';

class BattleNotify {
  static Future<void> setup(AppState state, Account account) async {}
  static void markSeen(AppState state, Iterable<String> ids) {}
}
