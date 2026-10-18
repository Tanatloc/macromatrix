import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/oned.dart';
import 'package:zxing_lib/zxing.dart';

import '../../i18n.dart';

/// Barcode scannen met de camera (Android en browser). Geeft de gelezen code terug.
///
/// Volledig met vrije software: de camera-plugin van Flutter en ZXing (Apache 2.0, in Dart). Op Android worden de
/// beelden rechtstreeks gelezen (helderheid van elk pixel), in de browser elke halve seconde een foto.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false, _done = false, _torch = false;
  Timer? _webTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(
        back,
        kIsWeb ? ResolutionPreset.high : ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      if (kIsWeb) {
        _webTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _snapWeb());
      } else {
        await c.startImageStream(_onFrame);
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code.contains('Denied') || e.code.contains('ermission')
              ? tr(
                  'No access to the camera. Give the app permission in your phone settings.',
                  'Geen toegang tot de camera. Geef de app toestemming in de instellingen van je gsm.',
                )
              : tr('The camera could not start.', 'De camera kon niet starten.'),
        );
      }
    }
  }

  void _onFrame(CameraImage frame) {
    if (_busy || _done) return;
    _busy = true;
    final y = frame.planes.first;
    final w = frame.width, h = frame.height;
    // Helderheidsvlak zonder opvulling per rij
    final luma = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      luma.setRange(row * w, row * w + w, y.bytes, row * y.bytesPerRow);
    }
    compute(decodeBarcode, (luma, w, h)).then(_found).whenComplete(() => _busy = false);
  }

  Future<void> _snapWeb() async {
    final c = _controller;
    if (_busy || _done || c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    _busy = true;
    try {
      final bytes = await (await c.takePicture()).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final small = decoded.width > 960 ? img.copyResize(decoded, width: 960) : decoded;
      final gray = img.grayscale(small);
      final luma = Uint8List(gray.width * gray.height);
      var i = 0;
      for (final p in gray) {
        luma[i++] = p.r.toInt();
      }
      _found(decodeBarcode((luma, gray.width, gray.height)));
    } catch (_) {
      // Volgende foto proberen
    } finally {
      _busy = false;
    }
  }

  void _found(String? code) {
    if (code == null || _done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } on CameraException {
      // Geen zaklamp op dit toestel
    }
  }

  @override
  void dispose() {
    _webTimer?.cancel();
    final c = _controller;
    if (c != null) {
      if (!kIsWeb && c.value.isStreamingImages) c.stopImageStream();
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text(tr('Scan barcode', 'Barcode scannen'), style: const TextStyle(color: Colors.white)),
        actions: [
          if (!kIsWeb)
            IconButton(
              onPressed: _toggleTorch,
              icon: Icon(_torch ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
              tooltip: tr('Flashlight', 'Zaklamp'),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          else if (c == null || !c.value.isInitialized)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Center(
              child: AspectRatio(aspectRatio: kIsWeb ? c.value.aspectRatio : 1 / c.value.aspectRatio, child: CameraPreview(c)),
            ),
          // Kader als hulp om te richten
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              tr('Point at the barcode on the packaging', 'Richt op de barcode van de verpakking'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zoekt een EAN/UPC-barcode in een grijswaardenbeeld. Probeert het beeld rechtop en 90° gedraaid (de camera van
/// een gsm levert liggende beelden, terwijl je een barcode meestal horizontaal voor een rechtopstaande gsm houdt).
String? decodeBarcode((Uint8List, int, int) frame) {
  final (luma, w, h) = frame;
  const hint = DecodeHint(tryHarder: true, possibleFormats: [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE]);
  String? attempt(Uint8List data, int width, int height) {
    try {
      final bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource.orig(width, height, data)));
      return MultiFormatUPCEANReader(hint).decode(bitmap, hint).text;
    } on ReaderException {
      return null;
    }
  }

  final direct = attempt(luma, w, h);
  if (direct != null) return direct;
  // 90° draaien
  final rotated = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      rotated[x * h + (h - 1 - y)] = luma[row + x];
    }
  }
  return attempt(rotated, h, w);
}
