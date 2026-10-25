import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/oned.dart';
import 'package:zxing_lib/zxing.dart';

import '../../data/off_client.dart' show looksLikeBarcode;
import '../../i18n.dart';

/// Barcode scannen met de camera (Android en browser). Geeft de gelezen code terug. Start de camera niet (geen camera,
/// geen toestemming), dan typ je het nummer onder de streepjes of probeer je opnieuw (NW-14); dat typen kan ook
/// altijd via het toetsenbord bovenaan.
///
/// Volledig met vrije software: de camera-plugin van Flutter en ZXing (Apache 2.0, in Dart). Op Android worden de
/// beelden rechtstreeks gelezen (helderheid van elk pixel), in de browser elke halve seconde een foto.
/// De camera's van het toestel. Te vervangen in tests (daar is geen camera).
@visibleForTesting
Future<List<CameraDescription>> Function() scanCameras = availableCameras;

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
  final _typed = TextEditingController();

  /// Het nummer zelf typen in plaats van de camera (ook als die wel werkt, bv. bij een gekreukte barcode).
  bool _typing = false;
  String? _typedError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_error != null) setState(() => _error = null);
    // Opnieuw proberen: de vorige camera eerst vrijgeven, anders is ze "in gebruik"
    _webTimer?.cancel();
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose().catchError((_) {});
    try {
      final cams = await scanCameras();
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
    } catch (e) {
      // Ook een fout die geen CameraException is (geen camera-ondersteuning in deze browser): dan dezelfde uitweg
      if (mounted) {
        setState(
          () => _error = e is CameraException && (e.code.contains('Denied') || e.code.contains('ermission'))
              ? (kIsWeb
                    ? tr(
                        'No access to the camera. Allow the camera for this site in your browser (the icon next to the address).',
                        'Geen toegang tot de camera. Sta de camera toe voor deze site in je browser (het icoontje naast het adres).',
                      )
                    : tr(
                        'No access to the camera. Give the app permission in your phone settings.',
                        'Geen toegang tot de camera. Geef de app toestemming in de instellingen van je gsm.',
                      ))
              : tr('The camera could not start.', 'De camera kon niet starten.'),
        );
      }
    }
  }

  void _onFrame(CameraImage frame) {
    // Tijdens het typen niet scannen: een code die de camera toevallig ziet, zou het scherm sluiten
    if (_busy || _done || _typing) return;
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
    if (_busy || _done || _typing || c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
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

  /// Het getypte nummer teruggeven, zoals een gescande code.
  void _submitTyped() {
    final code = _typed.text.replaceAll(RegExp(r'\s'), '');
    if (!looksLikeBarcode(code)) {
      setState(
        () => _typedError = tr(
          'That is not a barcode. Type the 8 or 13 digits under the stripes.',
          'Dat is geen barcode. Typ de 8 of 13 cijfers onder de streepjes.',
        ),
      );
      return;
    }
    _found(code);
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
    _typed.dispose();
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
          if (_error == null)
            IconButton(
              key: const ValueKey('scan-type-number'),
              onPressed: () => setState(() => _typing = !_typing),
              icon: Icon(_typing ? Icons.qr_code_scanner_rounded : Icons.keyboard_outlined),
              tooltip: _typing ? tr('Use the camera', 'Camera gebruiken') : tr('Type the number', 'Nummer typen'),
            ),
          if (!kIsWeb && !_typing && _error == null)
            IconButton(
              onPressed: _toggleTorch,
              icon: Icon(_torch ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
              tooltip: tr('Flashlight', 'Zaklamp'),
            ),
        ],
      ),
      body: _error != null || _typing ? _typePanel() : _cameraView(c),
    );
  }

  /// Camera kapot of zelf gekozen: het nummer onder de streepjes typen, en bij een fout opnieuw proberen.
  Widget _typePanel() => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('scan-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                tr('Type the number under the barcode', 'Typ het nummer onder de barcode'),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('scan-typed'),
                controller: _typed,
                autofocus: _typing,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 1.5),
                cursorColor: Colors.white,
                onChanged: (_) {
                  if (_typedError != null) setState(() => _typedError = null);
                },
                onSubmitted: (_) => _submitTyped(),
                decoration: InputDecoration(
                  hintText: '5400000000000',
                  hintStyle: const TextStyle(color: Colors.white38),
                  errorText: _typedError,
                  errorMaxLines: 3,
                  filled: true,
                  fillColor: Colors.white10,
                  prefixIcon: const Icon(Icons.qr_code_rounded, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('scan-typed-go'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _submitTyped,
                child: Text(tr('Look up', 'Opzoeken')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('scan-retry'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _start,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Try the camera again', 'Camera opnieuw proberen')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cameraView(CameraController? c) => Stack(
    fit: StackFit.expand,
    children: [
      if (c == null || !c.value.isInitialized)
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
  );
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
