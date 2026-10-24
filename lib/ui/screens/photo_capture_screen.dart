import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../i18n.dart';

/// Eén foto nemen met de camera (Android en browser), voor loggen met een foto. Geeft de ruwe JPEG terug, of
/// null als je teruggaat. Verkleinen gebeurt daarna (zie shrinkPhoto).
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

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
      // 1080p is ruim genoeg: we verkleinen toch tot 1024 px
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code.contains('Denied') || e.code.contains('ermission')
              ? tr(
                  'No access to the camera. Give the app permission in your phone settings, or choose a photo instead.',
                  'Geen toegang tot de camera. Geef de app toestemming in de instellingen van je gsm, of kies een foto.',
                )
              : tr('The camera could not start. Choose a photo instead.', 'De camera kon niet starten. Kies een foto.'),
        );
      }
    }
  }

  Future<void> _take() async {
    final c = _controller;
    if (_taking || c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    setState(() => _taking = true);
    try {
      final bytes = await (await c.takePicture()).readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } on CameraException {
      if (mounted) {
        setState(() {
          _taking = false;
          _error = tr('Taking the photo failed. Try again.', 'De foto nemen lukte niet. Probeer opnieuw.');
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text(tr('Photo of your meal', 'Foto van je maaltijd'), style: const TextStyle(color: Colors.white)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null && !ready)
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
          else if (!ready)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Center(
              child: AspectRatio(aspectRatio: kIsWeb ? c.value.aspectRatio : 1 / c.value.aspectRatio, child: CameraPreview(c)),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 132,
            child: Text(
              _error != null && ready
                  ? _error!
                  : tr('Take the photo from above, with the whole plate in view', 'Neem de foto van boven, met het hele bord in beeld'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Center(
                child: Tooltip(
                  message: tr('Take photo', 'Foto nemen'),
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _taking ? null : _take,
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: _taking
                            ? const Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 3))
                            : const Icon(Icons.photo_camera_rounded, size: 34, color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
