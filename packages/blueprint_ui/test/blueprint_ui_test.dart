import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FathomColors', () {
    test('light tokens match locked pool-night values', () {
      const c = FathomColors.light;
      expect(c.accent, const Color(0xFF19B7B0));
      expect(c.amber, const Color(0xFFD97706));
      expect(c.hot, const Color(0xFFE85D4C));
      expect(c.ink, const Color(0xFF142033));
      expect(c.bg, const Color(0xFFEEF2F6));
      expect(c.bgElev, const Color(0xFFFFFFFF));
      expect(c.up, const Color(0xFF0F9F6E));
      expect(c.pool, const Color(0xFFD7F3F1));
    });

    test('dark tokens match locked pool-night values', () {
      const c = FathomColors.dark;
      expect(c.accent, const Color(0xFF5DFFC4));
      expect(c.amber, const Color(0xFFF0C75E));
      expect(c.hot, const Color(0xFFFF7A68));
      expect(c.ink, const Color(0xFFF3F6F8));
      expect(c.bg, const Color(0xFF0B0D10));
      expect(c.bgElev, const Color(0xFF14181E));
      expect(c.up, const Color(0xFF5DFFC4));
      expect(c.pool, const Color(0xFF0F2428));
    });
  });

  group('BpTheme', () {
    test('light() wires Fathom color scheme and scaffold', () {
      final theme = BpTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, FathomColors.light.bg);
      expect(theme.colorScheme.primary, FathomColors.light.accent);
      expect(theme.colorScheme.onPrimary, FathomColors.light.accentInk);
      expect(theme.colorScheme.secondary, FathomColors.light.amber);
      expect(theme.colorScheme.error, FathomColors.light.hot);
      expect(theme.colorScheme.surface, FathomColors.light.bgElev);
      expect(theme.colorScheme.onSurface, FathomColors.light.ink);
      expect(theme.colorScheme.outline, FathomColors.light.inkFaint);
      expect(theme.colorScheme.outlineVariant, FathomColors.light.line);
      expect(theme.extension<FathomColors>(), FathomColors.light);
      expect(theme.useMaterial3, isTrue);
      // Locked `--shadow` base color is `ink` in light mode.
      expect(theme.colorScheme.shadow, FathomColors.light.ink.withValues(alpha: 0.08));
    });

    test('dark() wires Fathom color scheme and scaffold', () {
      final theme = BpTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, FathomColors.dark.bg);
      expect(theme.colorScheme.primary, FathomColors.dark.accent);
      expect(theme.colorScheme.onPrimary, FathomColors.dark.accentInk);
      expect(theme.colorScheme.secondary, FathomColors.dark.amber);
      expect(theme.colorScheme.error, FathomColors.dark.hot);
      expect(theme.colorScheme.surface, FathomColors.dark.bgElev);
      expect(theme.colorScheme.onSurface, FathomColors.dark.ink);
      expect(theme.colorScheme.outline, FathomColors.dark.inkFaint);
      expect(theme.colorScheme.outlineVariant, FathomColors.dark.line);
      expect(theme.extension<FathomColors>(), FathomColors.dark);
      // Locked `--shadow` base color is black in dark mode, not `ink`
      // (which is near-white in dark mode) — regression guard for the
      // dark-mode shadow-tint bug.
      expect(theme.colorScheme.shadow, const Color(0xFF000000).withValues(alpha: 0.45));
    });

    testWidgets('FathomColors.of resolves theme extension', (tester) async {
      late FathomColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Builder(
            builder: (context) {
              resolved = FathomColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.accent, FathomColors.light.accent);
    });
  });

  group('FathomTextStyles', () {
    test('exposes Manrope / IBM Plex Mono family names', () {
      expect(FathomTextStyles.fontSans, 'Manrope');
      expect(FathomTextStyles.fontMono, 'IBM Plex Mono');
      expect(FathomTextStyles.sans().fontFamily, 'Manrope');
      expect(FathomTextStyles.mono().fontFamily, 'IBM Plex Mono');
    });

    test('textTheme tints display and body with ink steps', () {
      final theme = FathomTextStyles.textTheme(FathomColors.light);
      expect(theme.displayLarge?.color, FathomColors.light.ink);
      expect(theme.bodyLarge?.color, FathomColors.light.inkDim);
      expect(theme.bodySmall?.color, FathomColors.light.inkFaint);
      expect(theme.displayLarge?.fontFamily, 'Manrope');
      expect(theme.labelSmall?.fontFamily, 'IBM Plex Mono');
    });
  });
}
