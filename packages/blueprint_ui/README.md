# blueprint_ui

Fathom design-system package for the Fitness OS companion app.

## Theme

```dart
import 'package:blueprint_ui/blueprint_ui.dart';

MaterialApp(
  theme: BpTheme.light(),
  darkTheme: BpTheme.dark(),
  // ...
);
```

Helpers:

- `FathomColors.light` / `FathomColors.dark` / `FathomColors.of(context)`
- `FathomTextStyles.textTheme` / `.sans` / `.mono` — Manrope + IBM Plex Mono

## Token mapping (`docs/design/tokens.css`)

| CSS token | Flutter | Light | Dark |
|---|---|---|---|
| `--bg` | `FathomColors.bg` / scaffold | `#EEF2F6` | `#0B0D10` |
| `--bg-elev` | `FathomColors.bgElev` / surface | `#FFFFFF` | `#14181E` |
| `--ink` | `FathomColors.ink` / onSurface | `#142033` | `#F3F6F8` |
| `--ink-dim` | `FathomColors.inkDim` | `#5B6B7C` | `#A7B2BD` |
| `--ink-faint` | `FathomColors.inkFaint` | `#8A97A6` | `#6F7B88` |
| `--accent` | `FathomColors.accent` → primary | `#19B7B0` | `#5DFFC4` |
| `--accent-ink` | `FathomColors.accentInk` → onPrimary | `#043532` | `#06281D` |
| `--amber` | `FathomColors.amber` → secondary | `#D97706` | `#F0C75E` |
| `--hot` | `FathomColors.hot` → error | `#E85D4C` | `#FF7A68` |
| `--up` | `FathomColors.up` → tertiary | `#0F9F6E` | `#5DFFC4` |
| `--pool` | `FathomColors.pool` | `#D7F3F1` | `#0F2428` |
| `--font-sans` | `FathomTextStyles.fontSans` = Manrope | — | — |
| `--font-mono` | `FathomTextStyles.fontMono` = IBM Plex Mono | — | — |

Manual Flutter port of the locked tokens — no auto-sync from CSS.

### Fonts

`BpTheme` sets `fontFamily` to **Manrope** / **IBM Plex Mono** with system
sans/mono fallbacks. To render the real faces in the host app, either:

1. Add [`google_fonts`](https://pub.dev/packages/google_fonts) and apply
   `GoogleFonts.manropeTextTheme` / `GoogleFonts.ibmPlexMono` over the theme, or
2. Bundle the `.ttf` files under `flutter/fonts` in the app `pubspec.yaml`.
