import 'package:flutter/material.dart';

// Design tokens in three layers (primitive → semantic → component).
// Components read semantic tokens through `context.t`, never raw colors, so
// light and dark themes stay consistent.
//
// Direction: calm and legible under stress. One neutral base (zinc), one
// accent (emergency red); green only means "safe / I'm okay", amber only
// means "attention". No pure black.

/// Brand name shown in the app, notifications and SMS.
const appName = 'P.A.Z.I.Y.O.N';
const appTagline = 'When you can’t speak for yourself, it speaks for you.';

// ---------------------------------------------------------------- primitives

abstract final class Palette {
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF0E0E11);

  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const red950 = Color(0xFF2A0E0E);

  static const green400 = Color(0xFF4ADE80);
  static const green600 = Color(0xFF16A34A);
  static const green700 = Color(0xFF15803D);

  static const amber400 = Color(0xFFFBBF24);
  static const amber600 = Color(0xFFD97706);
  static const amber800 = Color(0xFF92400E);
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

abstract final class Radii {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
}

/// Minimum touch target; emergency controls use [Sizes.emergency].
abstract final class Sizes {
  static const touch = 56.0;
  static const emergency = 88.0;
  static const helpButton = 216.0;
}


// ---------------------------------------------------------------- semantic

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.ok,
    required this.onOk,
    required this.warn,
    required this.warnSurface,
    required this.onWarnSurface,
    required this.focus,
  });

  final Color bg, surface, surfaceMuted, border, text, textMuted;
  final Color accent, accentPressed, onAccent;
  final Color ok, onOk;
  final Color warn, warnSurface, onWarnSurface;
  final Color focus;

  // The emergency screens are always dark: readable at max brightness in a
  // dark room without blinding a bystander (spec section 8).
  static const emergencyBg = Palette.zinc950;
  static const emergencySurface = Palette.zinc900;
  static const emergencyBorder = Palette.zinc700;
  static const emergencyText = Palette.zinc50;
  static const emergencyMuted = Palette.zinc300;

  static const light = AppTokens(
    bg: Palette.zinc50,
    surface: Colors.white,
    surfaceMuted: Palette.zinc100,
    border: Palette.zinc200,
    text: Palette.zinc900,
    textMuted: Palette.zinc600,
    accent: Palette.red600,
    accentPressed: Palette.red700,
    onAccent: Colors.white,
    ok: Palette.green700,
    onOk: Colors.white,
    warn: Palette.amber800,
    warnSurface: Color(0xFFFFF7E6),
    onWarnSurface: Palette.amber800,
    focus: Palette.amber600,
  );

  static const dark = AppTokens(
    bg: Palette.zinc950,
    surface: Palette.zinc900,
    surfaceMuted: Palette.zinc800,
    border: Palette.zinc800,
    text: Palette.zinc50,
    textMuted: Palette.zinc400,
    accent: Palette.red600,
    accentPressed: Palette.red700,
    onAccent: Colors.white,
    ok: Palette.green700,
    onOk: Colors.white,
    warn: Palette.amber400,
    warnSurface: Color(0xFF2A1F0A),
    onWarnSurface: Palette.amber400,
    focus: Palette.amber400,
  );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensX on BuildContext {
  AppTokens get t => Theme.of(this).extension<AppTokens>()!;
}

// ---------------------------------------------------------------- type scale

const _fontFamily = 'Outfit';
const _fontFallback = ['NotoSansEthiopic'];

/// Every style names the family, because button and field styles replace the
/// theme's text style rather than merging with it.
abstract final class TypeScale {
  static const display = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 34, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.6);
  static const title = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 26, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.4);
  static const heading = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 19, fontWeight: FontWeight.w600, height: 1.25);
  static const body = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 17, fontWeight: FontWeight.w400, height: 1.45);
  static const label = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 17, fontWeight: FontWeight.w600, height: 1.2);
  static const caption = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35);
  static const emergencyStep = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 30, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.3);
  static const countdown = TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 132, fontWeight: FontWeight.w700, height: 1, letterSpacing: -4);
}

// ---------------------------------------------------------------- theme

ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.text,
    onSecondary: t.bg,
    error: t.accent,
    onError: t.onAccent,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerHighest: t.surfaceMuted,
    outline: t.border,
    outlineVariant: t.border,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    extensions: [t],
    scaffoldBackgroundColor: t.bg,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    textTheme: TextTheme(
      headlineMedium: TypeScale.title.copyWith(color: t.text),
      titleLarge: TypeScale.heading.copyWith(color: t.text),
      bodyLarge: TypeScale.body.copyWith(color: t.text),
      bodyMedium: TypeScale.body.copyWith(color: t.text),
      labelLarge: TypeScale.label,
      bodySmall: TypeScale.caption.copyWith(color: t.textMuted),
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(Sizes.touch, Sizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: TypeScale.label,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(Sizes.touch, Sizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        foregroundColor: t.text,
        side: BorderSide(color: t.border, width: 1.5),
        textStyle: TypeScale.label,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(Sizes.touch, Sizes.touch),
        foregroundColor: t.text,
        textStyle: TypeScale.label,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      labelStyle: TypeScale.body.copyWith(color: t.textMuted),
      floatingLabelStyle: TypeScale.caption.copyWith(color: t.text),
      hintStyle: TypeScale.body.copyWith(color: t.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: t.focus, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : t.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ok : t.surfaceMuted),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: t.text, thumbColor: t.text, inactiveTrackColor: t.border),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.surfaceMuted,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TypeScale.caption.copyWith(color: s.contains(WidgetState.selected) ? t.text : t.textMuted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? t.text : t.textMuted, size: 26),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.text,
      contentTextStyle: TypeScale.body.copyWith(color: t.bg),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
