import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/quick_parse.dart';
import '../../platform/cloud_voice.dart';
import '../../platform/photo_log.dart';
import '../../platform/platform.dart' show canScanBarcodes;
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../screens/add_food_screen.dart';
import '../screens/photo_capture_screen.dart';
import '../theme.dart';
import 'kit.dart';
import 'number_input.dart';
import 'pro_widgets.dart';
import 'quick_line.dart';
import 'undo.dart';

/// Spraak werkt in de Android-app en in Chrome/Edge; op Linux typ je de zin.
bool get speechSupported => kIsWeb || defaultTargetPlatform == TargetPlatform.android;

/// Snel loggen: zeg of typ wat je at ("200 g chicken and a bowl of rice"), controleer en voeg alles toe.
/// Met [photo] vraagt het venster meteen een foto van je bord (loggen met een foto, vanuit het +-menu). Met [text]
/// (al getypt in het veld op een lege Vandaag) staan de producten meteen klaar om toe te voegen.
Future<void> showQuickLog(BuildContext context, {Meal? meal, bool photo = false, String? text}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _QuickLogSheet(meal: meal ?? context.read<AppState>().suggestedMeal, photo: photo, text: text),
);

/// Een foto van je bord nemen of kiezen, al verkleind voor de server; null = geannuleerd. Te vervangen in tests.
@visibleForTesting
Future<Uint8List?> Function(BuildContext context) pickPlatePhoto = _pickPlatePhoto;

/// De verbinding met /api/photo. Te vervangen in tests (met een nagebootste http-client).
@visibleForTesting
PhotoLog photoLog = PhotoLog();

/// Het token van je account, of null als je niet ingelogd bent. Te vervangen in tests.
@visibleForTesting
String? Function(BuildContext context) photoToken = (context) => context.read<Account>().client?.auth.currentSession?.accessToken;

/// Op gsm en in de browser: kiezen tussen de camera en een bestaande foto. Op een pc meteen een bestand kiezen.
Future<Uint8List?> _pickPlatePhoto(BuildContext context) async {
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
            // Eerlijk zeggen dat een AI de foto leest (GP-12)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                photoAiNote,
                key: const ValueKey('photo-ai-note'),
                style: TextStyle(fontSize: 12, height: 1.4, color: ctx.pal.ink3),
              ),
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
    final picked = await FilePicker.pickFiles(dialogTitle: tr('Choose a photo of your meal', 'Kies een foto van je maaltijd'), type: FileType.image);
    raw = picked.isEmpty ? null : await picked.single.readAsBytes();
  }
  if (raw == null) return null;
  // Verkleinen tot 1024 px en JPEG 80 voor het versturen (in een aparte isolate: een foto van 12 MP is zwaar)
  return compute(shrinkPhoto, raw);
}


class _QuickLogSheet extends StatefulWidget {
  const _QuickLogSheet({required this.meal, this.photo = false, this.text});
  final Meal meal;
  final bool photo;
  final String? text;

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _speech = SpeechToText();
  late Meal _meal = widget.meal;
  List<QuickLine> _lines = const [];
  bool _listening = false;
  String? _speechError;

  /// Melding bij een leeg veld of een zin zonder product.
  String? _notice;

  /// Na een korte typpauze vanzelf zoeken (N10); Enter en de knop werken ook.
  Timer? _typing;

  /// Een dubbele tik op het kruisje wist niet ook de regel die eronder opschuift (N04).
  DateTime _lastRemove = DateTime(0);

  // Opnemen via de eigen server (toestellen zonder spraakherkenning, bv. GrapheneOS)
  CloudVoice? _cloud;
  bool _cloudRecording = false, _transcribing = false;
  Timer? _cloudTimer;

  // Loggen met een foto: bezig met kijken, een foutmelding, en of de lijst uit een foto komt (dan geschat)
  bool _looking = false, _fromPhoto = false;
  String? _photoError;

  @override
  void initState() {
    super.initState();
    if (widget.text case final t? when t.trim().isNotEmpty) _text.text = t.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_text.text.isNotEmpty) _parse();
      // De fototeller verversen (een nieuwe dag, of een foto op een ander toestel)
      final pro = proOf(context, listen: false);
      final refreshed = pro?.refreshQuota();
      if (widget.photo) {
        // Vanuit het +-menu meteen een foto vragen, maar pas als de teller bekend is (anders neem je voor niets een foto)
        if (refreshed == null) {
          _photo();
        } else {
          // Hoogstens 3 s wachten: bij een trage verbinding beslist de server toch zelf
          unawaited(refreshed.timeout(const Duration(seconds: 3), onTimeout: () {}).whenComplete(() => mounted ? _photo() : null));
        }
      }
    });
  }

  /// Foto nemen of kiezen, naar de server sturen en de zin die terugkomt opzoeken zoals een getypte zin. Je ziet
  /// alles eerst in de lijst en past het aan met +, −, Andere en ×, voor er iets toegevoegd wordt.
  Future<void> _photo() async {
    if (_looking || _transcribing || _cloudRecording || !mounted) return;
    final token = photoToken(context);
    if (token == null) {
      setState(() => _photoError = _photoErrorText('login'));
      return;
    }
    setState(() => _photoError = null);
    // Gratis foto's van vandaag op: de uitleg met de Pro-knop staat al onder de knop, geen foto vragen
    final pro = proOf(context, listen: false);
    if (pro?.quota?.allowed == false) return;
    final Uint8List? jpeg;
    try {
      jpeg = await pickPlatePhoto(context);
    } catch (_) {
      if (mounted) setState(() => _photoError = _photoErrorText('bad_image'));
      return;
    }
    if (jpeg == null || !mounted) return;
    setState(() => _looking = true);
    try {
      final text = await photoLog.describe(jpeg, token: token);
      final q = photoLog.lastQuota;
      if (q != null) pro?.noteQuota(q);
      if (!mounted) return;
      setState(() => _looking = false);
      if (text.isEmpty) {
        setState(() => _photoError = _photoErrorText('none'));
        return;
      }
      _text.text = text;
      _fromPhoto = true;
      _parse();
    } on PhotoLogException catch (e) {
      // Op voor vandaag: de stand onthouden, dan toont PhotoQuotaNote de uitleg met de Pro-knop
      final q = e.quota;
      if (q != null) pro?.noteQuota(q);
      if (!mounted) return;
      setState(() {
        _looking = false;
        // Toont PhotoQuotaNote de uitleg al (met de Pro-knop), dan geen tweede melding
        _photoError = e.code == 'quota' && pro?.quota?.allowed == false ? null : _photoErrorText(e.code);
      });
    }
  }

  String _photoErrorText(String code) => switch (code) {
    'login' => tr(
      'Logging with a photo needs an account. Log in under Profile → Account, or type what you ate.',
      'Loggen met een foto kan alleen met een account. Log in via Profiel → Account, of typ wat je at.',
    ),
    'not_configured' => tr(
      'Logging with a photo is not available yet. Type or say what you ate.',
      'Loggen met een foto is nog niet beschikbaar. Typ of zeg wat je at.',
    ),
    'quota' => tr(
      "You've used your free photos for today. They're back tomorrow; you can still type or say what you ate.",
      "Je gratis foto's van vandaag zijn op. Morgen kan het weer; je kunt nog altijd typen of zeggen wat je at.",
    ),
    'too_many' => tr(
      'You have used a lot of photos this hour. Try again later, or type what you ate.',
      "Je hebt dit uur al veel foto's gebruikt. Probeer later opnieuw, of typ wat je at.",
    ),
    'network' => tr('No connection. Check your internet and try again.', 'Geen verbinding. Kijk je internet na en probeer opnieuw.'),
    'none' => tr(
      'No food found in that photo. Try again with the whole plate in view, or type it.',
      'Geen eten gevonden op die foto. Probeer opnieuw met het hele bord in beeld, of typ het.',
    ),
    'bad_image' || 'too_big' => tr('That photo could not be opened. Try a JPG or PNG.', 'Die foto kon niet geopend worden. Probeer een JPG of PNG.'),
    _ => tr("Couldn't read the photo. Try again or type what you ate.", 'De foto lezen lukte niet. Probeer opnieuw of typ wat je at.'),
  };

  @override
  void dispose() {
    _typing?.cancel();
    _text.dispose();
    _focus.dispose();
    if (_listening) _speech.stop();
    _cloudTimer?.cancel();
    _cloud?.cancel();
    _cloud?.dispose();
    super.dispose();
  }

  Future<void> _startCloud() async {
    final token = context.read<Account>().client?.auth.currentSession?.accessToken;
    if (token == null) {
      setState(
        () => _speechError = tr(
          'Log in to use voice on this phone, or type what you ate.',
          'Log in om spraak te gebruiken op deze gsm, of typ wat je at.',
        ),
      );
      return;
    }
    final c = _cloud ??= CloudVoice();
    if (!await c.start()) {
      setState(() => _speechError = _errorText('error_permission'));
      return;
    }
    setState(() {
      _cloudRecording = true;
      _listening = true;
      _speechError = null;
    });
    // Hoogstens 15 seconden
    _cloudTimer = Timer(const Duration(seconds: 15), _finishCloud);
  }

  Future<void> _finishCloud() async {
    _cloudTimer?.cancel();
    if (!_cloudRecording || !mounted) return;
    final token = context.read<Account>().client?.auth.currentSession?.accessToken ?? '';
    setState(() {
      _cloudRecording = false;
      _listening = false;
      _transcribing = true;
    });
    try {
      final text = await _cloud!.stopAndTranscribe(token: token, lang: isNl ? 'nl' : 'en');
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (text.isEmpty) {
        setState(() => _speechError = _errorText('error_no_match'));
        return;
      }
      _text.text = text;
      _parse();
    } on CloudVoiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _speechError = switch (e.code) {
          'login' => tr('Log in again to use voice, or type what you ate.', 'Log opnieuw in om spraak te gebruiken, of typ wat je at.'),
          'network' => _errorText('error_network'),
          'not_configured' => tr('Voice is not available yet. Type what you ate.', 'Spraak is nog niet beschikbaar. Typ wat je at.'),
          _ => tr("Couldn't turn your voice into text. Try again or type it.", 'Je stem omzetten naar tekst lukte niet. Probeer opnieuw of typ het.'),
        };
      });
    }
  }

  /// De zin omzetten naar regels. Regels die al bestonden (zelfde stuk tekst), houden je gekozen treffer en
  /// hoeveelheid. [auto] = na een typpauze: dan geen melding bij een leeg veld.
  void _parse({bool auto = false}) {
    _typing?.cancel();
    final s = context.read<AppState>();
    final text = _text.text.trim();
    final old = {for (final l in _lines) l.item.toString(): l};
    final items = parseQuick(text);
    setState(() {
      _lines = [for (final q in items) old.remove(q.toString()) ?? QuickLine(q, s.resolveQuick(q))];
      _notice = auto
          ? null
          : text.isEmpty
          ? tr(
              'Type or say what you ate first, e.g. "2 eggs and a slice of bread".',
              'Typ of zeg eerst wat je at, bv. "2 eieren en een sneetje brood".',
            )
          : items.isEmpty
          ? tr('No food found in that sentence. Try e.g. "200 g chicken".', 'Geen product gevonden in die zin. Probeer bv. "200 g kip".')
          : null;
    });
  }

  void _onTyped(String _) {
    _typing?.cancel();
    setState(() => _notice = null);
    _typing = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _parse(auto: true);
    });
  }

  void _clear() {
    _typing?.cancel();
    _text.clear();
    setState(() {
      _lines = const [];
      _notice = null;
      _fromPhoto = false;
    });
    _focus.requestFocus();
  }

  void _remove(QuickLine l) {
    final now = DateTime.now();
    if (now.difference(_lastRemove) < const Duration(milliseconds: 450)) return;
    _lastRemove = now;
    setState(() => _lines = [..._lines]..remove(l));
  }

  Future<void> _listen() async {
    if (_transcribing) return;
    if (_cloudRecording) return _finishCloud();
    // Android zonder spraak-app (bv. GrapheneOS): meteen zelf opnemen, zonder eerst te wachten op een fout
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb && !_listening) {
      final hasApp = await _voiceChannel.invokeMethod<bool>('available').catchError((Object _) => false) ?? false;
      if (!hasApp) return _startCloud();
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      // Sommige Android-toestellen (o.a. Pixel) geven anders error_client: de dienst opzoeken en geen Bluetooth
      options: [SpeechToText.androidIntentLookup, SpeechToText.androidNoBluetooth],
      onError: (e) {
        setState(() => _listening = false);
        // De ingebouwde herkenning weigert: dan het gewone spraakvenster van Android
        if (_systemFallbackCodes.contains(e.errorMsg) && defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
          _systemVoice();
          return;
        }
        // In de browser: geen spraakdienst achter de browser? Dan via onze server
        if (kIsWeb && _webFallbackCodes.contains(e.errorMsg)) {
          _startCloud();
          return;
        }
        setState(() => _speechError = _errorText(e.errorMsg));
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') setState(() => _listening = false);
      },
    );
    if (!ok) {
      if (kIsWeb) return _startCloud();
      if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) return _systemVoice();
      setState(
        () => _speechError = tr(
          'Speech recognition is not available. Type what you ate instead.',
          'Spraakherkenning is niet beschikbaar. Typ wat je at.',
        ),
      );
      return;
    }
    setState(() {
      _listening = true;
      _speechError = null;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: await _localeId(), partialResults: true),
      onResult: (r) {
        _text.text = r.recognizedWords;
        if (r.finalResult) {
          setState(() => _listening = false);
          _parse();
        }
      },
    );
  }

  /// Een taal die de spraakherkenning van dit toestel echt kent. Op Android staan vaak niet alle varianten
  /// (bv. alleen en_US en niet en_GB); dan zou het herkennen meteen mislukken. Null = de standaardtaal.
  String? _cachedLocale;
  bool _localeChecked = false;

  Future<String?> _localeId() async {
    // De browser wil een taalcode met streepje (en-GB), niet met underscore
    if (kIsWeb) return isNl ? 'nl-BE' : 'en-GB';
    if (_localeChecked) return _cachedLocale;
    _localeChecked = true;
    final want = isNl ? const ['nl_BE', 'nl_NL'] : const ['en_GB', 'en_US', 'en_IE'];
    final lang = isNl ? 'nl' : 'en';
    try {
      final available = [for (final l in await _speech.locales()) l.localeId.replaceAll('-', '_')];
      final system = (await _speech.systemLocale())?.localeId.replaceAll('-', '_');
      _cachedLocale =
          want.where(available.contains).firstOrNull ??
          (system != null && system.startsWith(lang) ? system : null) ??
          available.where((l) => l.startsWith('${lang}_')).firstOrNull;
    } catch (_) {
      _cachedLocale = null;
    }
    return _cachedLocale;
  }

  static const _systemFallbackCodes = {
    'error_client',
    'error_recognizer_busy',
    'error_server_disconnected',
    'error_language_not_supported',
    'error_language_unavailable',
    'error_unknown',
  };
  static const _webFallbackCodes = {'aborted', 'network', 'service-not-allowed', 'language-not-supported', 'audio-capture', 'bad-grammar'};
  static const _voiceChannel = MethodChannel('macromatrix/voice');

  /// Het spraakvenster van Android (Google) openen en de tekst invullen.
  Future<void> _systemVoice() async {
    try {
      final text = await _voiceChannel.invokeMethod<String>('recognize', {
        'language': isNl ? 'nl-BE' : 'en-GB',
        'prompt': tr('Say what you ate', 'Zeg wat je at'),
      });
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) return;
      _text.text = text;
      setState(() => _speechError = null);
      _parse();
    } on PlatformException {
      // Geen spraak-app op dit toestel: zelf opnemen en via de server omzetten
      if (mounted) await _startCloud();
    }
  }

  String _errorText(String code) => switch (code) {
    'error_permission' || 'error_insufficient_permissions' => tr(
      'MacroMatrix may not use the microphone. Allow it in your phone settings (Apps → MacroMatrix → Permissions).',
      'MacroMatrix mag de microfoon niet gebruiken. Sta het toe in de instellingen van je gsm (Apps → MacroMatrix → Machtigingen).',
    ),
    'error_no_match' ||
    'error_speech_timeout' => tr("I didn't catch that. Tap the microphone and try again.", 'Niet verstaan. Tik op de microfoon en probeer opnieuw.'),
    'error_language_not_supported' || 'error_language_unavailable' => tr(
      'Your phone has no speech recognition for this language. Install it under Settings → System → Languages → Speech, or type it.',
      'Je gsm heeft geen spraakherkenning voor deze taal. Installeer ze via Instellingen → Systeem → Talen → Spraak, of typ het.',
    ),
    'error_network' || 'error_network_timeout' || 'error_server' => tr(
      'Speech recognition needs internet. Try again or type it.',
      'Spraakherkenning heeft internet nodig. Probeer opnieuw of typ het.',
    ),
    _ => tr('Could not hear you ($code). Try again or type it.', 'Niet goed verstaan ($code). Probeer opnieuw of typ het.'),
  };

  bool _adding = false;

  Future<void> _addAll() async {
    if (_adding) return;
    final s = context.read<AppState>();
    // Een vergeten komma of "1000" in plaats van "1": eerst vragen, zoals op het productscherm (N65)
    final odd = _lines.where((l) => l.found && l.grams > 0 && l.unusual).toList();
    if (odd.isNotEmpty) {
      _adding = true;
      final ok = await confirmUnusual(
        context,
        [
          for (final l in odd)
            tr('${_weight(l.grams)} of ${l.food.name} is ${bigNum(l.kcal)} kcal.', '${_weight(l.grams)} ${l.food.name} is ${bigNum(l.kcal)} kcal.'),
          tr('Is that the right amount?', 'Is dat de juiste hoeveelheid?'),
        ].join('\n'),
      );
      _adding = false;
      if (!ok || !mounted) return;
    }
    final added = <AddedEntry>[];
    for (final l in _lines) {
      if (!l.found || l.grams <= 0) continue;
      // Een andere treffer gekozen: die onthouden voor de volgende keer
      if (l.choice != 0) s.rememberQuickPick(l.item.query, l.food.ref);
      added.add(s.addFood(l.food, meal: _meal, grams: l.grams, quantity: l.portion == null ? l.grams : l.n, portionLabel: l.portion?.label));
    }
    final n = added.length;
    if (n == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    showUndo(
      null,
      tr(
        'Added $n ${n == 1 ? 'item' : 'items'} to ${_meal.label.toLowerCase()}',
        '$n ${n == 1 ? 'item' : 'items'} toegevoegd aan ${_meal.label.toLowerCase()}',
      ),
      () => s.undoAdds(added),
      messenger: messenger,
    );
  }

  static String _weight(double g) => g >= 1000 ? '${g >= 10000 ? bigNum(g / 1000) : fmtNum(g / 1000, 2)} kg' : '${fmtInt(g)} g';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ready = _lines.where((l) => l.found && l.grams > 0).toList();
    final found = ready.length;
    final totalKcal = ready.fold(0.0, (a, l) => a + l.kcal);
    final totalProtein = ready.fold(0.0, (a, l) => a + l.protein);
    final pro = proOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(tr('Quick log', 'Snel loggen'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                speechSupported
                    ? tr(
                        'Tap the microphone and say what you ate, type it, or take a photo of your plate.',
                        'Tik op de microfoon en zeg wat je at, typ het, of neem een foto van je bord.',
                      )
                    : tr(
                        'Type what you ate in one sentence, or add a photo of your plate.',
                        'Typ in één zin wat je at, of voeg een foto van je bord toe.',
                      ),
                style: TextStyle(fontSize: 13, color: p.ink2),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      autofocus: !speechSupported,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: tr('e.g. 200 g chicken and a bowl of rice', 'bv. 200 g kip en een kom rijst'),
                        suffixIcon: _text.text.isEmpty
                            ? null
                            : IconButton(tooltip: tr('Clear', 'Wissen'), icon: const Icon(Icons.close_rounded), onPressed: _clear),
                      ),
                      onChanged: _onTyped,
                      onSubmitted: (_) => _parse(),
                    ),
                  ),
                  if (speechSupported) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: _listening ? tr('Stop', 'Stoppen') : tr('Speak', 'Inspreken'),
                      onPressed: _listen,
                      icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                      style: IconButton.styleFrom(backgroundColor: _listening ? p.high : p.brand, minimumSize: const Size(52, 52)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: tr('Photo of your meal', 'Foto van je maaltijd'),
                    onPressed: _looking ? null : _photo,
                    icon: const Icon(Icons.photo_camera_outlined),
                    style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  ),
                ],
              ),
              // Hoeveel gratis foto's je vandaag nog hebt, of de uitleg als ze op zijn
              if (pro != null) PhotoQuotaNote(quota: pro.quota, pro: pro.isPro),
              if (_looking) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('Looking at your photo…', 'Je foto wordt bekeken…'), style: TextStyle(fontSize: 12.5, color: p.ink2)),
                    ),
                  ],
                ),
              ],
              if (_photoError != null) ...[const SizedBox(height: 6), Text(_photoError!, style: TextStyle(fontSize: 12.5, color: p.high))],
              // Een foto geeft schattingen: dat moet duidelijk zijn voor je toevoegt
              if (_fromPhoto && _lines.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: p.ink2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(
                            'Estimated from your photo. Check each food and amount, and fix them with − and +, Other or × before you add them.',
                            'Geschat op basis van je foto. Kijk elk product en elke hoeveelheid na, en pas ze aan met − en +, Andere of × voor je ze toevoegt.',
                          ),
                          style: TextStyle(fontSize: 12.5, color: p.ink2, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_cloudRecording || _transcribing) ...[
                const SizedBox(height: 6),
                Text(
                  _transcribing
                      ? tr('Turning your voice into text…', 'Je stem wordt omgezet naar tekst…')
                      : tr('Listening… tap stop when you are done (max. 15 s).', 'Ik luister… tik op stop als je klaar bent (max. 15 s).'),
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ],
              if (_speechError != null) ...[const SizedBox(height: 6), Text(_speechError!, style: TextStyle(fontSize: 12.5, color: p.high))],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: Text(tr('Find foods', 'Producten zoeken')),
                  onPressed: _parse,
                ),
              ),
              if (_notice != null) ...[const SizedBox(height: 6), Text(_notice!, style: TextStyle(fontSize: 12.5, color: p.ink2))],
              for (final l in _lines) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: !l.found
                      ? InkWell(
                          onTap: () async {
                            final picked = await Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => AddFoodScreen(meal: _meal, initialQuery: l.item.query),
                              ),
                            );
                            if (mounted) setState(() => _lines = [..._lines]..remove(l));
                            return picked;
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr(
                                    '"${l.item.query}": nothing found — tap to search yourself',
                                    '"${l.item.query}": niets gevonden — tik om zelf te zoeken',
                                  ),
                                  style: TextStyle(color: p.ink3),
                                ),
                              ),
                              Icon(Icons.search_rounded, size: 18, color: p.ink3),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.pick.$1.name,
                                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                                  ),
                                  Text('${l.amountLabel} · ${bigNum(l.kcal)} kcal · "${l.item.query}"', style: TextStyle(fontSize: 12, color: p.ink3)),
                                  if (l.unusual)
                                    Text(
                                      tr('Unusually large. Check the amount.', 'Ongewoon veel. Kijk de hoeveelheid na.'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.high),
                                    ),
                                  const SizedBox(height: 2),
                                  // Hoeveelheid aanpassen zonder het venster te verlaten (N10)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _StepButton(
                                        icon: Icons.remove_rounded,
                                        tooltip: tr('Less', 'Minder'),
                                        onPressed: () => setState(() => l.step(up: false)),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          l.byWeight ? '${bigNum(l.n)} g' : countLabel(l.n),
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                                        ),
                                      ),
                                      _StepButton(
                                        icon: Icons.add_rounded,
                                        tooltip: tr('More', 'Meer'),
                                        onPressed: () => setState(() => l.step(up: true)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (l.options.length > 1)
                              // Met een woord erbij, niet alleen een pijltje (P154); per keuze de bron en de kcal (P177)
                              PopupMenuButton<int>(
                                tooltip: tr('Other match', 'Andere treffer'),
                                itemBuilder: (_) => [
                                  for (final (i, o) in l.options.indexed)
                                    PopupMenuItem(
                                      value: i,
                                      child: Row(
                                        children: [
                                          if (i == l.choice) Icon(Icons.check_rounded, size: 16, color: p.brand) else const SizedBox(width: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(o.$1.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                                Text(
                                                  '${o.$1.source.labelWithCountry} · ${fmtInt((o.$1.per100g['energy'] ?? 0) * o.$2 / 100)} kcal (${fmtInt(o.$2)} g)',
                                                  style: TextStyle(fontSize: 11.5, color: p.ink3),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                onSelected: (i) => setState(() => l.select(i)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swap_horiz_rounded, size: 18, color: p.ink2),
                                      const SizedBox(width: 3),
                                      Text(
                                        tr('Other', 'Andere'),
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: tr('Remove', 'Weghalen'),
                              icon: Icon(Icons.close_rounded, color: p.ink3),
                              onPressed: () => _remove(l),
                            ),
                          ],
                        ),
                ),
              ],
              if (found > 0) ...[
                const SizedBox(height: 14),
                Segmented<Meal>(
                  height: 32,
                  items: [for (final m in Meal.values) (m, m.label)],
                  selected: _meal,
                  onChanged: (m) => setState(() => _meal = m),
                ),
                const SizedBox(height: 12),
                // Het totaal vóór je toevoegt, zodat een ontbijt van 1.500 kcal opvalt (N10)
                Row(
                  children: [
                    Text(tr('Total', 'Totaal'), style: TextStyle(fontSize: 14, color: p.ink2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('${bigNum(totalKcal)} kcal · ${bigNum(totalProtein)} g protein', '${bigNum(totalKcal)} kcal · ${bigNum(totalProtein)} g eiwit'),
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _addAll,
                  child: Text(tr('Add $found to ${_meal.label.toLowerCase()}', '$found toevoegen aan ${_meal.label.toLowerCase()}')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kleine + of − naast de hoeveelheid van een regel.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    padding: EdgeInsets.zero,
  );
}
