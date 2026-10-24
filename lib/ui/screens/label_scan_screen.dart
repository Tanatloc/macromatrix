import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../i18n.dart';
import '../../platform/ai_request.dart';
import '../../platform/label_scan.dart';
import '../../platform/photo_log.dart' show shrinkPhoto;
import '../../platform/platform.dart' show canScanBarcodes;
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../../sync/pro.dart';
import '../../sync/supporter_tracker.dart' show offSharedCount;
import '../theme.dart';
import '../widgets/ai_quota_note.dart';
import '../widgets/kit.dart';
import '../widgets/pro_widgets.dart';
import 'custom_food_screen.dart';
import 'photo_capture_screen.dart';

/// Een foto nemen of kiezen, verkleind voor de server; null = geannuleerd. Te vervangen in tests (ook gebruikt door
/// het importeren van een recept).
Future<Uint8List?> Function(BuildContext context, {required String title}) pickAiPhoto = _pickAiPhoto;

/// De verbindingen met /api/label en /api/off-contribute. Te vervangen in tests.
@visibleForTesting
LabelScan labelScan = LabelScan();
@visibleForTesting
OffContribute offContribute = OffContribute();

/// Het token van je account, of null als je niet ingelogd bent. Te vervangen in tests.
String? Function(BuildContext context) aiToken = (context) => context.read<Account?>()?.client?.auth.currentSession?.accessToken;

/// Op gsm en in de browser: kiezen tussen de camera en een bestaande foto. Op een pc meteen een bestand kiezen.
Future<Uint8List?> _pickAiPhoto(BuildContext context, {required String title}) async {
  var camera = false;
  if (canScanBarcodes) {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Take a photo', 'Foto nemen')),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose a photo', 'Foto kiezen')),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return null;
    camera = choice;
  }
  final Uint8List? raw;
  if (camera) {
    raw = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const PhotoCaptureScreen()));
  } else {
    final picked = await FilePicker.pickFiles(dialogTitle: title, type: FileType.image);
    raw = picked.isEmpty ? null : await picked.single.readAsBytes();
  }
  if (raw == null) return null;
  return compute(shrinkPhoto, raw);
}

/// Uitleg boven het formulier na een gelezen etiket.
String labelNotice(LabelResult r) => [
  tr(
    'Read from your photo. Check every value against the label before you save.',
    'Gelezen van je foto. Kijk elke waarde na op het etiket voor je bewaart.',
  ),
  if (r.fromPortion)
    tr(
      'The label gave values per serving; they were converted to 100 g.',
      'Het etiket gaf waarden per portie; ze zijn omgerekend naar 100 g.',
    ),
  if (r.perMl) tr('Values per 100 ml are used as per 100 g.', 'Waarden per 100 ml gelden hier als per 100 g.'),
  if (r.warnings.isNotEmpty)
    tr('Some values looked wrong and were left empty.', 'Sommige waarden leken niet te kloppen en zijn leeg gelaten.'),
].join(' ');

/// "Scan het etiket": een product dat nergens gevonden werd, invullen met een foto van de voedingswaardetabel (en
/// eventueel de voorkant voor de naam). Het formulier voor een eigen product opent daarna ingevuld; je kijkt alles
/// na en bewaart het als je eigen product (gesynchroniseerd met je account). Daarna kun je het delen met Open Food
/// Facts. Geeft het bewaarde product terug.
class LabelScanScreen extends StatefulWidget {
  const LabelScanScreen({super.key, required this.barcode});
  final String barcode;

  @override
  State<LabelScanScreen> createState() => _LabelScanScreenState();
}

class _LabelScanScreenState extends State<LabelScanScreen> {
  Uint8List? _label, _front;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) proOf(context, listen: false)?.refreshAiQuota(AiKind.label);
    });
  }

  Future<void> _pick({required bool front}) async {
    try {
      final b = await pickAiPhoto(
        context,
        title: front ? tr('Photo of the front', 'Foto van de voorkant') : tr('Photo of the nutrition table', 'Foto van de voedingswaardetabel'),
      );
      if (b == null || !mounted) return;
      setState(() {
        if (front) {
          _front = b;
        } else {
          _label = b;
        }
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = aiErrorText('bad_image'));
    }
  }

  Future<void> _read() async {
    final label = _label;
    if (label == null || _busy) return;
    final token = aiToken(context);
    if (token == null) {
      setState(() => _error = aiErrorText('login'));
      return;
    }
    final pro = proOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    LabelResult result;
    try {
      result = await labelScan.read(label, front: _front, token: token);
      final q = labelScan.lastQuota;
      if (q != null) pro?.noteAiQuota(AiKind.label, q);
    } on AiException catch (e) {
      if (e.quota != null) pro?.noteAiQuota(AiKind.label, e.quota!);
      if (!mounted) return;
      setState(() {
        _busy = false;
        // De uitleg met de Pro-knop staat al in beeld
        _error = e.code == 'quota' && pro?.aiQuota(AiKind.label)?.allowed == false ? null : aiErrorText(e.code);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final saved = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => CustomFoodScreen(prefill: result.toFood(barcode: widget.barcode), notice: labelNotice(result)),
      ),
    );
    if (saved == null || !mounted) return;
    await _offerShare(saved);
    if (mounted) Navigator.of(context).pop(saved);
  }

  /// Na het bewaren: vragen of het product gedeeld mag worden met Open Food Facts (alleen als dat kan).
  Future<void> _offerShare(Food food) async {
    if (food.barcode == null || food.barcode!.isEmpty) return;
    final token = aiToken(context);
    if (token == null || !await offContribute.configured() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Share this product with Open Food Facts so others can find it?', 'Dit product delen met Open Food Facts, zodat anderen het ook vinden?')),
        content: Text(
          tr(
            'Open Food Facts is a free, public food database. We would send the barcode, the name, the brand, the nutrition values per 100 g '
                'and your photo of the label. It becomes public under the Open Database Licence (ODbL). Nothing about you is sent. '
                'Your own product stays saved either way.',
            'Open Food Facts is een vrije, openbare databank van voedingsmiddelen. We sturen de barcode, de naam, het merk, de voedingswaarden '
                'per 100 g en je foto van het etiket. Dat wordt openbaar onder de Open Database Licence (ODbL). Niets over jou wordt verstuurd. '
                'Je eigen product blijft hoe dan ook bewaard.',
          ),
        ),
        actions: [
          TextButton(key: const ValueKey('off-share-no'), onPressed: () => Navigator.pop(ctx, false), child: Text(tr('No, thanks', 'Nee, bedankt'))),
          FilledButton(key: const ValueKey('off-share-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Share', 'Delen'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final db = context.read<AppState>().user;
    try {
      await offContribute.share(food, label: _label, front: _front, token: token);
      // Teller voor het supporterbadge Wereldverbeteraar (gesynchroniseerd)
      db.setSetting('offShared', {'count': offSharedCount(db) + 1});
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Thank you! The product is shared with Open Food Facts.', 'Bedankt! Het product is gedeeld met Open Food Facts.'))),
      );
    } on AiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'not_configured'
                ? tr('Sharing is not available right now. Your product is saved.', 'Delen kan nu niet. Je product is wel bewaard.')
                : tr("Couldn't share it right now. Your product is saved.", 'Delen lukte nu niet. Je product is wel bewaard.'),
          ),
        ),
      );
    }
  }

  Future<void> _enterYourself() async {
    final saved = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => CustomFoodScreen(barcode: widget.barcode)));
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  Widget _photoTile({required bool front}) {
    final p = context.pal;
    final has = (front ? _front : _label) != null;
    return Panel(
      key: ValueKey(front ? 'label-photo-front' : 'label-photo-table'),
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: _busy ? null : () => _pick(front: front),
      child: Row(
        children: [
          Icon(has ? Icons.check_circle_rounded : (front ? Icons.image_outlined : Icons.document_scanner_outlined), color: has ? p.ok : p.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  front ? tr('Front of the pack (optional)', 'Voorkant van de verpakking (optioneel)') : tr('Nutrition table', 'Voedingswaardetabel'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  has
                      ? tr('Photo added. Tap to take another one.', 'Foto toegevoegd. Tik om een andere te nemen.')
                      : front
                      ? tr('For the name and brand.', 'Voor de naam en het merk.')
                      : tr('Straight on, sharp and well lit.', 'Recht van voren, scherp en goed belicht.'),
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.photo_camera_outlined, color: p.ink3),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pro = proOf(context);
    final quota = pro?.aiQuota(AiKind.label);
    final blocked = quota?.allowed == false;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Scan the label', 'Etiket scannen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    'Barcode ${widget.barcode} is not known yet. Take a photo of the nutrition table and we fill in the values for you. '
                        'You check them and save it as your own product.',
                    'Barcode ${widget.barcode} is nog niet bekend. Neem een foto van de voedingswaardetabel en we vullen de waarden voor je in. '
                        'Jij kijkt ze na en bewaart het als je eigen product.',
                  ),
                  style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
                ),
                const SizedBox(height: 14),
                _photoTile(front: false),
                const SizedBox(height: 10),
                _photoTile(front: true),
                if (pro != null) AiQuotaNote(kind: AiKind.label, quota: quota, pro: pro.isPro),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, key: const ValueKey('label-error'), style: TextStyle(fontSize: 13, color: p.high)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('label-read'),
                  onPressed: _label == null || _busy || blocked ? null : _read,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(_busy ? tr('Reading the label…', 'Het etiket wordt gelezen…') : tr('Read the label', 'Etiket lezen')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('label-enter-yourself'),
                  onPressed: _busy ? null : _enterYourself,
                  child: Text(tr('Enter it yourself instead', 'Liever zelf invullen')),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Your photos are read by an AI model on Cloudflare and are not stored.',
                    "Je foto's worden gelezen door een AI-model bij Cloudflare en niet bewaard.",
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
