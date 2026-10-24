/// Ontwerpsysteem: kleuren, letters en de standaardstijl van Material-onderdelen.
/// Het ontwerp zelf staat in design/project (System.dc.html).
library;

import 'package:flutter/material.dart';

import '../i18n.dart';

const kSans = 'Geist';
const kMono = 'GeistMono';

/// Kleuren van het ontwerp, voor licht en donker. Opvragen met `context.pal`.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.sunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.brand,
    required this.brandSoft,
    required this.onBrand,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.low,
    required this.lowFill,
    required this.lowSoft,
    required this.ok,
    required this.okFill,
    required this.okSoft,
    required this.high,
    required this.highFill,
    required this.highSoft,
    required this.track,
    required this.shadow,
  });

  /// Achtergrond, kaarten, licht vlak, verzonken vlak (segmentknoppen), lijnen.
  final Color bg, surface, surface2, sunken, line, lineStrong;

  /// Tekst: hoofdtekst, secundair, bijschrift.
  final Color ink, ink2, ink3;

  /// Merkkleur (petrol) voor snelle positieve acties, links en accenten.
  final Color brand, brandSoft, onBrand;

  /// Macro's.
  final Color protein, carbs, fat, fiber;

  /// Status: tekst, vulling en zachte achtergrond voor tekort, op doel en te veel.
  final Color low, lowFill, lowSoft, ok, okFill, okSoft, high, highFill, highSoft;

  /// Lege balk.
  final Color track;
  final List<BoxShadow> shadow;

  static const light = Palette(
    bg: Color(0xFFF4F3EF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFAF9F6),
    sunken: Color(0xFFEEECE7),
    line: Color(0xFFE4E1DA),
    lineStrong: Color(0xFFD3CFC6),
    ink: Color(0xFF15171A),
    ink2: Color(0xFF4B5058),
    ink3: Color(0xFF676C75),
    brand: Color(0xFF0E6B65),
    brandSoft: Color(0xFFE2EFEC),
    onBrand: Color(0xFFFFFFFF),
    protein: Color(0xFF3D5BD9),
    carbs: Color(0xFFB8741A),
    fat: Color(0xFFA9466B),
    fiber: Color(0xFF2E7D5B),
    low: Color(0xFF9A5B00),
    lowFill: Color(0xFFD98E1F),
    lowSoft: Color(0xFFFBEEDA),
    ok: Color(0xFF1C7357),
    okFill: Color(0xFF2A9D74),
    okSoft: Color(0xFFE1F0E9),
    high: Color(0xFFB3362A),
    highFill: Color(0xFFD2513F),
    highSoft: Color(0xFFF8E2DE),
    track: Color(0xFFECE9E3),
    shadow: [
      BoxShadow(color: Color(0x0A15171A), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x3815171A), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -18),
    ],
  );

  static const dark = Palette(
    bg: Color(0xFF0D0F11),
    surface: Color(0xFF15181B),
    surface2: Color(0xFF1A1E22),
    sunken: Color(0xFF111316),
    line: Color(0xFF25292E),
    lineStrong: Color(0xFF343A41),
    ink: Color(0xFFECEDEF),
    ink2: Color(0xFFB7BCC4),
    ink3: Color(0xFF9CA2AB),
    brand: Color(0xFF5BC3B6),
    brandSoft: Color(0xFF132B28),
    onBrand: Color(0xFF06201D),
    protein: Color(0xFF8FA3FF),
    carbs: Color(0xFFE3A956),
    fat: Color(0xFFE08BAA),
    fiber: Color(0xFF6CC79A),
    low: Color(0xFFE7A651),
    lowFill: Color(0xFFD99434),
    lowSoft: Color(0xFF2E2412),
    ok: Color(0xFF62C99E),
    okFill: Color(0xFF3BAA80),
    okSoft: Color(0xFF12291F),
    high: Color(0xFFF0806F),
    highFill: Color(0xFFD9604E),
    highSoft: Color(0xFF351A16),
    track: Color(0xFF22262B),
    shadow: [BoxShadow(color: Color(0xE6000000), blurRadius: 32, offset: Offset(0, 14), spreadRadius: -20)],
  );

  /// Kleur van een macro (energie is bewust inkt: neutraal, geen oordeel).
  Color macro(String key) => switch (key) {
    'protein' => protein,
    'carbs' => carbs,
    'fat' => fat,
    'fiber' => fiber,
    _ => ink,
  };

  /// Dezelfde kleuren met een andere merkkleur (een accent voor supporters, zie [accents]).
  Palette withBrand(Color brand, Color brandSoft, Color onBrand) => Palette(
    bg: bg,
    surface: surface,
    surface2: surface2,
    sunken: sunken,
    line: line,
    lineStrong: lineStrong,
    ink: ink,
    ink2: ink2,
    ink3: ink3,
    brand: brand,
    brandSoft: brandSoft,
    onBrand: onBrand,
    protein: protein,
    carbs: carbs,
    fat: fat,
    fiber: fiber,
    low: low,
    lowFill: lowFill,
    lowSoft: lowSoft,
    ok: ok,
    okFill: okFill,
    okSoft: okSoft,
    high: high,
    highFill: highFill,
    highSoft: highSoft,
    track: track,
    shadow: shadow,
  );

  /// Dezelfde kleuren op een andere achtergrond (zie [backdrops]); status- en macrokleuren blijven gelijk.
  Palette withSurfaces(Surfaces v) => Palette(
    bg: v.bg,
    surface: v.surface,
    surface2: v.surface2,
    sunken: v.sunken,
    line: v.line,
    lineStrong: v.lineStrong,
    ink: ink,
    ink2: ink2,
    ink3: ink3,
    brand: brand,
    brandSoft: brandSoft,
    onBrand: onBrand,
    protein: protein,
    carbs: carbs,
    fat: fat,
    fiber: fiber,
    low: low,
    lowFill: lowFill,
    lowSoft: lowSoft,
    ok: ok,
    okFill: okFill,
    okSoft: okSoft,
    high: high,
    highFill: highFill,
    highSoft: highSoft,
    track: v.track,
    shadow: shadow,
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => other == null || t < 0.5 ? this : other;
}

/// Een merkkleur om uit te kiezen bij Instellingen → Weergave. Petrol is de standaard en altijd gratis; de andere
/// zijn een extraatje voor wie Pro heeft. Elke kleur heeft een lichte en een donkere versie met genoeg contrast
/// voor witte (licht) of donkere (donker) tekst erop.
@immutable
class Accent {
  const Accent(
    this.id,
    this.en,
    this.nl, {
    required this.light,
    required this.lightSoft,
    required this.dark,
    required this.darkSoft,
    required this.darkOn,
  });
  final String id, en, nl;
  final Color light, lightSoft, dark, darkSoft, darkOn;

  String get name => tr(en, nl);
  bool get pro => id != defaultAccent;

  /// De merkkleur voor licht of donker, om een staal te tonen.
  Color brandFor(Brightness b) => b == Brightness.dark ? dark : light;

  Palette apply(Palette p, Brightness b) =>
      id == defaultAccent ? p : (b == Brightness.dark ? p.withBrand(dark, darkSoft, darkOn) : p.withBrand(light, lightSoft, const Color(0xFFFFFFFF)));
}

const defaultAccent = 'petrol';

const accents = <Accent>[
  Accent(
    'petrol',
    'Petrol',
    'Petrol',
    light: Color(0xFF0E6B65),
    lightSoft: Color(0xFFE2EFEC),
    dark: Color(0xFF5BC3B6),
    darkSoft: Color(0xFF132B28),
    darkOn: Color(0xFF06201D),
  ),
  Accent(
    'ocean',
    'Ocean',
    'Oceaan',
    light: Color(0xFF1F5FAE),
    lightSoft: Color(0xFFE3ECF8),
    dark: Color(0xFF7FB2F0),
    darkSoft: Color(0xFF13233A),
    darkOn: Color(0xFF061A33),
  ),
  Accent(
    'plum',
    'Plum',
    'Pruim',
    light: Color(0xFF7A3E8F),
    lightSoft: Color(0xFFF1E6F4),
    dark: Color(0xFFCB9BDC),
    darkSoft: Color(0xFF2A1A30),
    darkOn: Color(0xFF22102A),
  ),
  Accent(
    'gold',
    'Gold',
    'Goud',
    light: Color(0xFF835C00),
    lightSoft: Color(0xFFF6EDD6),
    dark: Color(0xFFE5B85C),
    darkSoft: Color(0xFF2E2510),
    darkOn: Color(0xFF261A00),
  ),
  Accent(
    'slate',
    'Slate',
    'Leisteen',
    light: Color(0xFF46566B),
    lightSoft: Color(0xFFE7EBF0),
    dark: Color(0xFFA9B8CC),
    darkSoft: Color(0xFF1C2229),
    darkOn: Color(0xFF0E141B),
  ),
  Accent(
    'rose',
    'Rose',
    'Roos',
    light: Color(0xFFB0325F),
    lightSoft: Color(0xFFF7E3EA),
    dark: Color(0xFFF28BAE),
    darkSoft: Color(0xFF331722),
    darkOn: Color(0xFF2A0614),
  ),
  Accent(
    'forest',
    'Forest',
    'Woud',
    light: Color(0xFF2F6B2F),
    lightSoft: Color(0xFFE4EFE2),
    dark: Color(0xFF8FD18A),
    darkSoft: Color(0xFF16291A),
    darkOn: Color(0xFF0A2209),
  ),
  Accent(
    'sunset',
    'Sunset',
    'Zonsondergang',
    light: Color(0xFFB4471F),
    lightSoft: Color(0xFFF8E6DD),
    dark: Color(0xFFF4A07A),
    darkSoft: Color(0xFF33201A),
    darkOn: Color(0xFF2B0F03),
  ),
  Accent(
    'lavender',
    'Lavender',
    'Lavendel',
    light: Color(0xFF5B4FC4),
    lightSoft: Color(0xFFE9E7F8),
    dark: Color(0xFFADA6F5),
    darkSoft: Color(0xFF1E1C38),
    darkOn: Color(0xFF150F3D),
  ),
];

Accent accentById(String? id) => accents.firstWhere((a) => a.id == id, orElse: () => accents.first);

/// De kleur die echt gebruikt wordt: de gekozen met Pro, anders petrol.
String effectiveAccent(String chosen, {required bool pro}) => pro ? accentById(chosen).id : defaultAccent;

/// Vlakken van een achtergrond: achtergrond, kaarten, licht vlak, verzonken vlak, lijnen en lege balk.
@immutable
class Surfaces {
  const Surfaces(this.bg, this.surface, this.surface2, this.sunken, this.line, this.lineStrong, this.track);
  final Color bg, surface, surface2, sunken, line, lineStrong, track;
}

/// Een achtergrond om uit te kiezen bij Instellingen → Weergave. Standaard is gratis; de andere zijn voor Pro, net als
/// de extra kleuren. Alleen de vlakken veranderen: tekst, status- en macrokleuren blijven dezelfde, zodat alles even
/// leesbaar blijft. Zonder eigen versie voor licht of donker blijft dat de standaard.
@immutable
class Backdrop {
  const Backdrop(this.id, this.en, this.nl, {this.light, this.dark});
  final String id, en, nl;
  final Surfaces? light, dark;

  String get name => tr(en, nl);
  bool get pro => id != defaultBackdrop;

  Palette apply(Palette p, Brightness b) {
    final v = b == Brightness.dark ? dark : light;
    return v == null ? p : p.withSurfaces(v);
  }

  /// Achtergrond en kaart, om een staal te tonen.
  (Color, Color) swatchFor(Brightness b) {
    final base = b == Brightness.dark ? Palette.dark : Palette.light;
    final v = b == Brightness.dark ? dark : light;
    return (v?.bg ?? base.bg, v?.surface ?? base.surface);
  }
}

const defaultBackdrop = 'standard';

const backdrops = <Backdrop>[
  Backdrop('standard', 'Standard', 'Standaard'),
  Backdrop(
    'paper',
    'Paper',
    'Papier',
    light: Surfaces(
      Color(0xFFF3EDE1),
      Color(0xFFFFFCF6),
      Color(0xFFFAF5EA),
      Color(0xFFEFE8DA),
      Color(0xFFE2D8C5),
      Color(0xFFD2C6AF),
      Color(0xFFE9E1D1),
    ),
    dark: Surfaces(
      Color(0xFF14110D),
      Color(0xFF1C1813),
      Color(0xFF221D17),
      Color(0xFF17130F),
      Color(0xFF2E2820),
      Color(0xFF3D362B),
      Color(0xFF28231C),
    ),
  ),
  Backdrop(
    'mist',
    'Mist',
    'Mist',
    light: Surfaces(
      Color(0xFFEEF1F5),
      Color(0xFFFFFFFF),
      Color(0xFFF7F9FB),
      Color(0xFFE9EDF2),
      Color(0xFFDAE0E8),
      Color(0xFFC8D0DB),
      Color(0xFFE3E8EE),
    ),
    dark: Surfaces(
      Color(0xFF0B0E13),
      Color(0xFF131821),
      Color(0xFF181E28),
      Color(0xFF0F131A),
      Color(0xFF222A36),
      Color(0xFF313B49),
      Color(0xFF1E2530),
    ),
  ),
  // Echt zwart in het donker (spaart batterij op OLED-schermen); licht blijft standaard
  Backdrop(
    'midnight',
    'Midnight',
    'Middernacht',
    dark: Surfaces(
      Color(0xFF000000),
      Color(0xFF0B0C0E),
      Color(0xFF111316),
      Color(0xFF060708),
      Color(0xFF1C1F23),
      Color(0xFF2B2F35),
      Color(0xFF181B1F),
    ),
  ),
];

Backdrop backdropById(String? id) => backdrops.firstWhere((a) => a.id == id, orElse: () => backdrops.first);

/// De achtergrond die echt gebruikt wordt: de gekozen met Pro, anders de standaard.
String effectiveBackdrop(String chosen, {required bool pro}) => pro ? backdropById(chosen).id : defaultBackdrop;

extension PaletteContext on BuildContext {
  Palette get pal => Theme.of(this).extension<Palette>()!;
}

/// Getallen: altijd Geist Mono met cijfers van gelijke breedte, zodat kolommen uitlijnen.
/// Getallen: groot in Geist Mono (het "instrument"-gevoel), klein in gewone Geist met cijfers van gelijke breedte,
/// zodat labels, eenheden en kleine waarden rustig ogen en toch netjes onder elkaar staan.
TextStyle numStyle(double size, {FontWeight weight = FontWeight.w600, Color? color, FontStyle? style, double? height}) => TextStyle(
  fontFamily: size >= 18 ? kMono : null,
  fontSize: size,
  fontWeight: weight,
  fontStyle: style,
  color: color,
  height: height,
  letterSpacing: size >= 20 ? -size * 0.04 : -size * 0.01,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Rand van een chip in het donker (zie [buildTheme]).
const chipEdgeDark = Color(0xFF6B727B);

/// Met [accent] een andere merkkleur en met [backdrop] een andere achtergrond (alleen voor Pro; de app geeft hier de
/// standaard door als Pro niet loopt).
ThemeData buildTheme(Brightness b, {String accent = defaultAccent, String backdrop = defaultBackdrop}) {
  final p = backdropById(backdrop).apply(accentById(accent).apply(b == Brightness.dark ? Palette.dark : Palette.light, b), b);
  final scheme = ColorScheme(
    brightness: b,
    primary: p.brand,
    onPrimary: p.onBrand,
    primaryContainer: p.brandSoft,
    onPrimaryContainer: p.brand,
    secondary: p.ink,
    onSecondary: p.bg,
    secondaryContainer: p.sunken,
    onSecondaryContainer: p.ink,
    tertiary: p.protein,
    onTertiary: p.onBrand,
    error: p.high,
    onError: p.onBrand,
    errorContainer: p.highSoft,
    onErrorContainer: p.high,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.ink3,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface2,
    surfaceContainer: p.surface2,
    surfaceContainerHigh: p.sunken,
    surfaceContainerHighest: p.track,
    outline: p.lineStrong,
    outlineVariant: p.line,
    inverseSurface: p.ink,
    onInverseSurface: p.bg,
    inversePrimary: p.brandSoft,
    shadow: Colors.black,
    scrim: Colors.black54,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: kSans, visualDensity: VisualDensity.standard);
  final t = base.textTheme;
  final text = t.copyWith(
    headlineMedium: t.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.7, height: 1.1, color: p.ink),
    headlineSmall: t.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.15, color: p.ink),
    titleLarge: t.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: p.ink),
    titleMedium: t.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: p.ink),
    titleSmall: t.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.4, color: p.ink),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.4, color: p.ink),
    bodySmall: t.bodySmall?.copyWith(fontSize: 12, height: 1.4, color: p.ink3),
    labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: t.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: t.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
  );
  final r12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final r14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return base.copyWith(
    extensions: [p],
    textTheme: text,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.line,
    splashFactory: InkSparkle.splashFactory,
    // Geen grijze vlakken die blijven staan na een tik of scroll (N55): ingedrukt toont alleen de rimpel, en de
    // hover is zo licht dat een rij onder de muis niet als geselecteerd (p.sunken) oogt.
    highlightColor: Colors.transparent,
    hoverColor: p.ink.withValues(alpha: 0.025),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.25, color: p.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.sunken,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      height: 68,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kSans,
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.ink3,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 21, color: s.contains(WidgetState.selected) ? p.ink : p.ink3)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.sunken,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selectedIconTheme: IconThemeData(color: p.ink),
      unselectedIconTheme: IconThemeData(color: p.ink3),
      selectedLabelTextStyle: TextStyle(fontFamily: kSans, fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink),
      unselectedLabelTextStyle: TextStyle(fontFamily: kSans, fontSize: 11.5, fontWeight: FontWeight.w500, color: p.ink3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.bg,
        disabledBackgroundColor: p.sunken,
        disabledForegroundColor: p.ink3,
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: r14,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.lineStrong),
        minimumSize: const Size(64, 40),
        shape: r12,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brand,
        shape: r12,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.ink)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.bg,
      elevation: 6,
      highlightElevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: const TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.ink,
      disabledColor: p.sunken,
      // In het donker stak de gewone lijnkleur amper af (±1,3:1): niet-gekozen chips waren losse woorden. Deze rand
      // haalt minstens 3:1 tegen de achtergrond en de kaarten (N93).
      side: BorderSide(color: b == Brightness.dark ? chipEdgeDark : p.line),
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w500, color: p.ink2),
      secondaryLabelStyle: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w500, color: p.bg),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      iconTheme: IconThemeData(color: p.ink2, size: 16),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.bg : p.ink2),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        shape: WidgetStatePropertyAll(r12),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: p.ink3),
      hintStyle: TextStyle(color: p.ink3),
      helperStyle: TextStyle(color: p.ink3, fontSize: 11.5),
      suffixStyle: TextStyle(color: p.ink3),
      prefixIconColor: p.ink2,
      suffixIconColor: p.ink2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.ink, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(fontFamily: kSans, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: p.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.lineStrong,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.line),
      ),
      textStyle: TextStyle(fontFamily: kSans, fontSize: 14, color: p.ink),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.line),
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: kSans, fontSize: 14, color: p.bg),
      actionTextColor: p.brandSoft,
      behavior: SnackBarBehavior.floating,
      // Zwevende meldingen hoog genoeg houden, zodat ze de knoppen onderaan (maaltijd toevoegen, FAB) niet
      // bedekken en geen tikken opslokken. Breedte blijft vrij; alleen de onderkant schuift op.
      insetPadding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
      shape: r12,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontFamily: kSans, fontSize: 12, color: p.bg, height: 1.4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: p.ink2,
      titleTextStyle: TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w500, color: p.ink),
      subtitleTextStyle: TextStyle(fontFamily: kSans, fontSize: 12, color: p.ink3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand, linearTrackColor: p.track, circularTrackColor: p.track),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.brand,
      inactiveTrackColor: p.track,
      thumbColor: p.brand,
      overlayColor: p.brand.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onBrand : p.ink3),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.brand : p.sunken),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.brand : p.lineStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : Colors.transparent),
      checkColor: WidgetStatePropertyAll(p.bg),
      side: BorderSide(color: p.lineStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: p.surface,
      headerForegroundColor: p.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
