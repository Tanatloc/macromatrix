import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../data/food.dart';
import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/quick_parse.dart';
import '../../platform/cloud_voice.dart';
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../theme.dart';
import 'kit.dart';

/// Spraak werkt in de Android-app en in Chrome/Edge; op Linux typ je de zin.
bool get speechSupported => kIsWeb || defaultTargetPlatform == TargetPlatform.android;

/// Snel loggen: zeg of typ wat je at ("200 g chicken and a bowl of rice"), controleer en voeg alles toe.
Future<void> showQuickLog(BuildContext context, {Meal? meal}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _QuickLogSheet(meal: meal ?? Meal.forHour(DateTime.now().hour)),
);

class _Line {
  _Line(this.item, this.options) : choice = 0;
  final QuickItem item;
  final List<(Food, double, Portion?)> options;
  int choice;
  bool get found => options.isNotEmpty;
  (Food, double, Portion?) get pick => options[choice];
}

String _count(double n) => n == n.roundToDouble() ? '${n.round()}' : fmtDec(n);

class _QuickLogSheet extends StatefulWidget {
  const _QuickLogSheet({required this.meal});
  final Meal meal;

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  final _text = TextEditingController();
  final _speech = SpeechToText();
  late Meal _meal = widget.meal;
  List<_Line> _lines = const [];
  bool _listening = false;
  String? _speechError;

  // Opnemen via de eigen server (toestellen zonder spraakherkenning, bv. GrapheneOS)
  CloudVoice? _cloud;
  bool _cloudRecording = false, _transcribing = false;
  Timer? _cloudTimer;

  @override
  void dispose() {
    _text.dispose();
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

  void _parse() {
    final s = context.read<AppState>();
    setState(() => _lines = [for (final q in parseQuick(_text.text)) _Line(q, s.resolveQuick(q))]);
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

  void _addAll() {
    final s = context.read<AppState>();
    var n = 0;
    for (final l in _lines) {
      if (!l.found) continue;
      final (food, grams, portion) = l.pick;
      s.addFood(food, meal: _meal, grams: grams, quantity: portion == null ? grams : (l.item.count ?? 1), portionLabel: portion?.label);
      n++;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Added $n ${n == 1 ? 'item' : 'items'} to ${_meal.label.toLowerCase()}',
            '$n ${n == 1 ? 'item' : 'items'} toegevoegd aan ${_meal.label.toLowerCase()}',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final found = _lines.where((l) => l.found).length;
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
                    ? tr('Tap the microphone and say what you ate, or type it.', 'Tik op de microfoon en zeg wat je at, of typ het.')
                    : tr('Type what you ate in one sentence.', 'Typ in één zin wat je at.'),
                style: TextStyle(fontSize: 13, color: p.ink2),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: !speechSupported,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(hintText: tr('e.g. 200 g chicken and a bowl of rice', 'bv. 200 g kip en een kom rijst')),
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
                ],
              ),
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
              for (final l in _lines) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: !l.found
                      ? Text(tr('"${l.item.query}": nothing found', '"${l.item.query}": niets gevonden'), style: TextStyle(color: p.ink3))
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
                                  Text(
                                    '${l.pick.$3 == null ? '${fmtInt(l.pick.$2)} g' : '${_count(l.item.count ?? 1)} × ${l.pick.$3!.label} (${fmtInt(l.pick.$2)} g)'} · ${fmtInt((l.pick.$1.per100g['energy'] ?? 0) * l.pick.$2 / 100)} kcal · "${l.item.query}"',
                                    style: TextStyle(fontSize: 12, color: p.ink3),
                                  ),
                                ],
                              ),
                            ),
                            if (l.options.length > 1)
                              PopupMenuButton<int>(
                                tooltip: tr('Other match', 'Andere treffer'),
                                icon: Icon(Icons.swap_horiz_rounded, color: p.ink2),
                                itemBuilder: (_) => [
                                  for (final (i, o) in l.options.indexed) PopupMenuItem(value: i, child: Text(o.$1.name, maxLines: 2)),
                                ],
                                onSelected: (i) => setState(() => l.choice = i),
                              ),
                            IconButton(
                              tooltip: tr('Remove', 'Weghalen'),
                              icon: Icon(Icons.close_rounded, color: p.ink3),
                              onPressed: () => setState(() => _lines = [..._lines]..remove(l)),
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
