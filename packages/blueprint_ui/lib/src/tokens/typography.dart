import 'package:flutter/material.dart';

import 'colors.dart';

/// Fathom typography helpers — Manrope (sans) + IBM Plex Mono.
///
/// [TextStyle.fontFamily] is set to the locked family names from
/// `docs/design/tokens.css`. Until the host app registers those faces
/// (via `google_fonts` or bundled assets), Flutter uses [fontFamilyFallback].
class FathomTextStyles {
  FathomTextStyles._();

  /// CSS `--font-sans`.
  static const String fontSans = 'Manrope';

  /// CSS `--font-mono`.
  static const String fontMono = 'IBM Plex Mono';

  static const List<String> sansFallbacks = <String>[
    'system-ui',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static const List<String> monoFallbacks = <String>[
    'ui-monospace',
    'SFMono-Regular',
    'Menlo',
    'Consolas',
    'monospace',
  ];

  /// Display / UI sans style (`--font-sans`).
  static TextStyle sans({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontSans,
      fontFamilyFallback: sansFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Instrument / metric mono style (`--font-mono`).
  static TextStyle mono({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontMono,
      fontFamilyFallback: monoFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Full Material [TextTheme] tinted with [colors] ink steps.
  static TextTheme textTheme(FathomColors colors) {
    return TextTheme(
      displayLarge: sans(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.0,
        color: colors.ink,
      ),
      displayMedium: sans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.05,
        color: colors.ink,
      ),
      displaySmall: sans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.1,
        color: colors.ink,
      ),
      headlineLarge: sans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: colors.ink,
      ),
      headlineMedium: sans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: colors.ink,
      ),
      headlineSmall: sans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colors.ink,
      ),
      titleLarge: sans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: colors.ink,
      ),
      titleMedium: sans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: colors.ink,
      ),
      titleSmall: sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      bodyLarge: sans(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: colors.inkDim,
      ),
      bodyMedium: sans(
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: colors.inkDim,
      ),
      bodySmall: sans(
        fontSize: 12,
        height: 1.4,
        color: colors.inkFaint,
      ),
      labelLarge: sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      labelMedium: mono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6,
        color: colors.inkFaint,
      ),
      labelSmall: mono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: colors.inkFaint,
      ),
    );
  }
}
