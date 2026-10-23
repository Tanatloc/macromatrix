import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/ui/screens/supplements_screen.dart';

void main() {
  test('IU omrekenen naar µg/mg voor vitamine A, D en E', () {
    expect(fromIu('vit_d', 1000), closeTo(25, 1e-9)); // 1 µg = 40 IU
    expect(fromIu('vit_a', 3330), closeTo(1000, 1e-9)); // retinol: 1 µg = 3,33 IU
    expect(fromIu('vit_e', 149), closeTo(100, 1e-9)); // natuurlijk alfa-tocoferol: 1 mg = 1,49 IU
    expect(fromIu('vit_c', 100), isNull);
  });

  test('bovengrens per dosis', () {
    expect(supplementCap('vit_d'), 100000);
    expect(supplementCap('magnesium'), 10000);
  });
}
