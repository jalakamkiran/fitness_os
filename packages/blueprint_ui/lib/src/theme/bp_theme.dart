import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Central theme configuration for Blueprint UI / Fathom.
///
/// Use with [MaterialApp]:
/// ```dart
/// MaterialApp(
///   theme: BpTheme.light(),
///   darkTheme: BpTheme.dark(),
/// )
/// ```
class BpTheme {
  BpTheme._();

  /// Light pool-night theme (`tokens.css` `:root` / light).
  static ThemeData light() => _build(FathomColors.light, Brightness.light);

  /// Dark pool-night theme (`tokens.css` `html[data-theme="dark"]`).
  static ThemeData dark() => _build(FathomColors.dark, Brightness.dark);

  static ThemeData _build(FathomColors colors, Brightness brightness) {
    final textTheme = FathomTextStyles.textTheme(colors);
    final colorScheme = colors.toColorScheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: colors.line,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.bg,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: colors.bgElev,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.tabBg,
        indicatorColor: colors.pool,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? colors.accent : colors.inkDim,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.accent : colors.inkDim,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.accentInk,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.gaugeTrack,
      ),
    );
  }
}
