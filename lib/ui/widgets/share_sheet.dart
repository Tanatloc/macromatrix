/// Deelkaart tonen en delen: eerst een voorbeeld met vinkjes (wat mag erop, licht of donker), dan "Delen".
/// De kaart wordt buiten beeld getekend op 1080 × 1350 (geen schermafdruk) en als PNG gedeeld; in de browser
/// gedownload.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../i18n.dart';
import '../../platform/platform.dart';
import '../theme.dart';
import 'share_cards.dart';

/// Bouwt de kaart met de aangevinkte onderdelen.
typedef ShareCardBuilder = Widget Function(Set<String> show);

/// Kaart in het thema (licht of donker), los van het thema van de app.
Widget shareCardThemed(Widget card, {required bool dark}) {
  final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
  return Theme(
    data: theme,
    child: Builder(
      builder: (context) => DefaultTextStyle(
        style: TextStyle(fontFamily: kSans, color: context.pal.ink, fontSize: 30),
        child: card,
      ),
    ),
  );
}

/// Tekent [card] buiten beeld op [shareCardSize] en geeft een PNG terug. [view] is het venster van de app (nodig
/// om te tekenen, er komt niets op het scherm).
Future<Uint8List> renderShareCard(Widget card, {required ui.FlutterView view, required bool dark, double pixelRatio = 1}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(logicalConstraints: BoxConstraints.tight(shareCardSize), devicePixelRatio: 1),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: shareCardSize, textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.fromSize(
          size: shareCardSize,
          child: shareCardThemed(card, dark: dark),
        ),
      ),
    ),
  ).attachToRenderTree(build);

  void frame() {
    build.buildScope(root);
    build.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
  }

  try {
    frame();
    // Afbeeldingen (logo, profielfoto) laden soms een tel later: nog eens tekenen
    await Future<void>.delayed(const Duration(milliseconds: 120));
    frame();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Boom weer opruimen, zodat er niets blijft hangen
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(build, root);
    build.finalizeTree();
    focus.dispose();
  }
}

/// Voorbeeld van een deelkaart met vinkjes, en daarna delen. [fileName] zonder extensie. [copyText] is de
/// volledige samenvatting om te kopiëren: die gaat bewust niet mee als bijschrift, want ze kan je gewicht of
/// notities bevatten. Als bijschrift gaat alleen een korte regel met het webadres mee.
Future<void> showShareSheet(
  BuildContext context, {
  required ShareCardBuilder card,
  required String fileName,
  List<ShareToggle> toggles = const [],
  String? copyText,
}) async {
  // Logo alvast laden, zodat het op de kaart staat
  unawaited(precacheImage(const AssetImage('assets/logo.png'), context).catchError((_) {}));
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => ShareSheet(card: card, fileName: fileName, toggles: toggles, copyText: copyText),
  );
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.card, required this.fileName, this.toggles = const [], this.copyText});
  final ShareCardBuilder card;
  final String fileName;
  final List<ShareToggle> toggles;
  final String? copyText;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late final Set<String> _show = {
    for (final t in widget.toggles)
      if (t.initial) t.id,
  };
  bool? _dark;
  bool _busy = false;

  /// Bijschrift bij het delen: kort, met het webadres.
  String get _caption => tr('Made with MacroMatrix · app.divinenet.online', 'Gemaakt met MacroMatrix · app.divinenet.online');

  Future<void> _share(bool dark) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    try {
      final png = await renderShareCard(widget.card({..._show}), view: View.of(context), dark: dark);
      final msg = await saveImageFile('${widget.fileName}.png', png, text: _caption);
      if (!mounted) return;
      nav.pop();
      if (msg != null) messenger?.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Could not create the image', 'De afbeelding kon niet gemaakt worden'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dark = _dark ?? Theme.of(context).brightness == Brightness.dark;
    final maxPreview = MediaQuery.sizeOf(context).height * 0.5;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Share card', 'Kaart delen'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('Only what you see on the card is shared.', 'Alleen wat je op de kaart ziet, wordt gedeeld.'),
              style: TextStyle(fontSize: 13, color: p.ink2),
            ),
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxPreview.clamp(240.0, 520.0)),
                child: AspectRatio(
                  aspectRatio: shareCardSize.width / shareCardSize.height,
                  child: Container(
                    key: const Key('share-preview'),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.line),
                    ),
                    child: FittedBox(
                      child: SizedBox.fromSize(
                        size: shareCardSize,
                        child: shareCardThemed(widget.card({..._show}), dark: dark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.light_mode_rounded), label: Text(tr('Light', 'Licht'))),
                ButtonSegment(value: true, icon: const Icon(Icons.dark_mode_rounded), label: Text(tr('Dark', 'Donker'))),
              ],
              selected: {dark},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _dark = v.first),
            ),
            if (widget.toggles.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final t in widget.toggles)
                CheckboxListTile(
                  key: Key('share-toggle-${t.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _show.contains(t.id),
                  title: Text(t.label),
                  onChanged: (v) => setState(() => v == true ? _show.add(t.id) : _show.remove(t.id)),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.copyText != null)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.copyText!));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Summary copied', 'Samenvatting gekopieerd'))));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(tr('Copy text', 'Tekst kopiëren')),
                  ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('share-go'),
                  onPressed: _busy ? null : () => _share(dark),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, size: 18),
                  label: Text(kIsWeb ? tr('Download', 'Downloaden') : tr('Share', 'Delen')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
