import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:voedingsapp/ui/widgets/avatar.dart';

void main() {
  test('foto wordt vierkant 192 px en klein genoeg voor de server', () {
    final photo = img.Image(width: 4000, height: 3000);
    img.fill(photo, color: img.ColorRgb8(200, 80, 40));
    final out = shrinkAvatar(img.encodeJpg(photo));
    final back = img.decodeJpg(out)!;
    expect((back.width, back.height), (192, 192));
    expect(out.length * 4 / 3, lessThan(100000));
  });
}
