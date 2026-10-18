/// Ontwerpsysteem: kleuren, letters en de standaardstijl van Material-onderdelen.
/// Het ontwerp zelf staat in design/project (System.dc.html).
library;

import 'package:flutter/material.dart';

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
    ink2: Color(0xFFA8ADB5),
    ink3: Color(0xFF8B919A),
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

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => other == null || t < 0.5 ? this : other;
}

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

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
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
      side: BorderSide(color: p.line),
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
