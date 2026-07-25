import 'package:flutter/material.dart';

/// Fathom pool-night palette.
///
/// Canonical source: `docs/design/tokens.css` (light + `html[data-theme="dark"]`).
@immutable
class FathomColors extends ThemeExtension<FathomColors> {
  const FathomColors({
    required this.bg,
    required this.bgElev,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.amber,
    required this.hot,
    required this.up,
    required this.pool,
    required this.poolLine,
    required this.node,
    required this.gaugeTrack,
    required this.tabBg,
    required this.spark,
  });

  /// App / scaffold background (`--bg`).
  final Color bg;

  /// Elevated surfaces / cards (`--bg-elev`).
  final Color bgElev;

  /// Primary ink (`--ink`).
  final Color ink;

  /// Secondary ink (`--ink-dim`).
  final Color inkDim;

  /// Tertiary / meta ink (`--ink-faint`).
  final Color inkFaint;

  /// Hairline / divider (`--line`).
  final Color line;

  /// Brand mint (`--accent`).
  final Color accent;

  /// Ink on accent fills (`--accent-ink`).
  final Color accentInk;

  /// Warning / amber accent (`--amber`).
  final Color amber;

  /// Hot / error (`--hot`).
  final Color hot;

  /// Positive / up (`--up`).
  final Color up;

  /// Soft pool wash (`--pool`).
  final Color pool;

  /// Pool stroke (`--pool-line`).
  final Color poolLine;

  /// Graph / node accent (`--node`).
  final Color node;

  /// Gauge track (`--gauge-track`).
  final Color gaugeTrack;

  /// Tab bar translucent fill (`--tab-bg`).
  final Color tabBg;

  /// Sparkline stroke (`--spark`).
  final Color spark;

  /// Light theme — mint accent `#19B7B0`, amber `#D97706`, hot `#E85D4C`.
  static const light = FathomColors(
    bg: Color(0xFFEEF2F6),
    bgElev: Color(0xFFFFFFFF),
    ink: Color(0xFF142033),
    inkDim: Color(0xFF5B6B7C),
    inkFaint: Color(0xFF8A97A6),
    line: Color(0x14142033),
    accent: Color(0xFF19B7B0),
    accentInk: Color(0xFF043532),
    amber: Color(0xFFD97706),
    hot: Color(0xFFE85D4C),
    up: Color(0xFF0F9F6E),
    pool: Color(0xFFD7F3F1),
    poolLine: Color(0x7319B7B0),
    node: Color(0xFF19B7B0),
    gaugeTrack: Color(0xFFD5DEE8),
    tabBg: Color(0xEBFFFFFF),
    spark: Color(0xFF19B7B0),
  );

  /// Dark theme — mint accent `#5DFFC4`.
  static const dark = FathomColors(
    bg: Color(0xFF0B0D10),
    bgElev: Color(0xFF14181E),
    ink: Color(0xFFF3F6F8),
    inkDim: Color(0xFFA7B2BD),
    inkFaint: Color(0xFF6F7B88),
    line: Color(0x1AF3F6F8),
    accent: Color(0xFF5DFFC4),
    accentInk: Color(0xFF06281D),
    amber: Color(0xFFF0C75E),
    hot: Color(0xFFFF7A68),
    up: Color(0xFF5DFFC4),
    pool: Color(0xFF0F2428),
    poolLine: Color(0x475DFFC4),
    node: Color(0xFF5DFFC4),
    gaugeTrack: Color(0xFF2A323C),
    tabBg: Color(0xE60C0E12),
    spark: Color(0xFF5DFFC4),
  );

  /// Resolves palette from [ThemeData.extensions], else by brightness.
  static FathomColors of(BuildContext context) {
    final extension = Theme.of(context).extension<FathomColors>();
    if (extension != null) return extension;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// Material [ColorScheme] mapped from Fathom tokens.
  ColorScheme toColorScheme(Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: accentInk,
      secondary: amber,
      onSecondary: accentInk,
      tertiary: up,
      onTertiary: accentInk,
      error: hot,
      onError: const Color(0xFFFFFFFF),
      surface: bgElev,
      onSurface: ink,
      onSurfaceVariant: inkDim,
      outline: line,
      outlineVariant: line,
      surfaceContainerHighest: pool,
      // `--shadow` is locked to a black base in dark mode and an ink base in
      // light mode (`docs/design/tokens.css`) — it does not simply track
      // `ink`, which flips to a near-white value in dark mode.
      shadow: brightness == Brightness.dark
          ? const Color(0xFF000000).withValues(alpha: 0.45)
          : ink.withValues(alpha: 0.08),
    );
  }

  @override
  FathomColors copyWith({
    Color? bg,
    Color? bgElev,
    Color? ink,
    Color? inkDim,
    Color? inkFaint,
    Color? line,
    Color? accent,
    Color? accentInk,
    Color? amber,
    Color? hot,
    Color? up,
    Color? pool,
    Color? poolLine,
    Color? node,
    Color? gaugeTrack,
    Color? tabBg,
    Color? spark,
  }) {
    return FathomColors(
      bg: bg ?? this.bg,
      bgElev: bgElev ?? this.bgElev,
      ink: ink ?? this.ink,
      inkDim: inkDim ?? this.inkDim,
      inkFaint: inkFaint ?? this.inkFaint,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      amber: amber ?? this.amber,
      hot: hot ?? this.hot,
      up: up ?? this.up,
      pool: pool ?? this.pool,
      poolLine: poolLine ?? this.poolLine,
      node: node ?? this.node,
      gaugeTrack: gaugeTrack ?? this.gaugeTrack,
      tabBg: tabBg ?? this.tabBg,
      spark: spark ?? this.spark,
    );
  }

  @override
  FathomColors lerp(ThemeExtension<FathomColors>? other, double t) {
    if (other is! FathomColors) return this;
    return FathomColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bgElev: Color.lerp(bgElev, other.bgElev, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkDim: Color.lerp(inkDim, other.inkDim, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      hot: Color.lerp(hot, other.hot, t)!,
      up: Color.lerp(up, other.up, t)!,
      pool: Color.lerp(pool, other.pool, t)!,
      poolLine: Color.lerp(poolLine, other.poolLine, t)!,
      node: Color.lerp(node, other.node, t)!,
      gaugeTrack: Color.lerp(gaugeTrack, other.gaugeTrack, t)!,
      tabBg: Color.lerp(tabBg, other.tabBg, t)!,
      spark: Color.lerp(spark, other.spark, t)!,
    );
  }
}
