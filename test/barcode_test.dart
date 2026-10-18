import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:macromatrix/ui/screens/scan_screen.dart';
import 'package:zxing_lib/oned.dart';
import 'package:zxing_lib/zxing.dart';

void main() {
  (Uint8List, int, int) render(String code, {bool rotate = false}) {
    final m = EAN13Writer().encode(code, BarcodeFormat.ean13, 400, 160);
    var im = img.Image(width: m.width + 40, height: m.height + 40);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < m.height; y++) {
      for (var x = 0; x < m.width; x++) {
        if (m.get(x, y)) im.setPixelRgb(x + 20, y + 20, 0, 0, 0);
      }
    }
    if (rotate) im = img.copyRotate(im, angle: 90);
    final luma = Uint8List(im.width * im.height);
    var i = 0;
    for (final p in im) {
      luma[i++] = p.r.toInt();
    }
    return (luma, im.width, im.height);
  }

  test('EAN-13 rechtop en gedraaid', () {
    expect(decodeBarcode(render('5449000000996')), '5449000000996');
    expect(decodeBarcode(render('3017620422003', rotate: true)), '3017620422003');
  });
}
