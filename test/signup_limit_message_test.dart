import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:supabase/supabase.dart' show AuthException;

void main() {
  test('te veel nieuwe accounts vanaf hetzelfde netwerk: een duidelijke uitleg, geen "wacht een minuut"', () {
    final m = authMessage(const AuthException('Too many new accounts from this network. Try again later.', statusCode: '429'));
    expect(m, contains('network'));
    expect(m, contains('hour'));
    // Een gewone 429 blijft de korte melding
    expect(authMessage(const AuthException('rate limited', statusCode: '429')), contains('Wait a minute'));
  });
}
