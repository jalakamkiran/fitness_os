import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

/// Provisional Huawei message-path stage `wireType` → display kind.
///
/// Not locked vs Health — labels are honest/provisional until night capture
/// confirms GT5-A07 mapping. Unknown types fall back to `stage N`.
///
/// Typical community map used here:
/// - 1 → Light
/// - 2 → Deep
/// - 3 → REM
/// - 4 / 7 → Awake
enum SleepStageKind { light, deep, rem, awake, unknown }

/// Map wire type to a display kind (provisional).
SleepStageKind sleepStageKindFromWireType(int? wireType) {
  return switch (wireType) {
    1 => SleepStageKind.light,
    2 => SleepStageKind.deep,
    3 => SleepStageKind.rem,
    4 || 7 => SleepStageKind.awake,
    _ => SleepStageKind.unknown,
  };
}

/// Human label for a wire type (provisional).
String sleepStageLabel(int? wireType) {
  return switch (sleepStageKindFromWireType(wireType)) {
    SleepStageKind.light => 'Light',
    SleepStageKind.deep => 'Deep',
    SleepStageKind.rem => 'REM',
    SleepStageKind.awake => 'Awake',
    SleepStageKind.unknown =>
      wireType == null ? 'stage ?' : 'stage $wireType',
  };
}

/// Design token color for a stage kind (Light=inkDim, Deep=accent, REM=amber, Awake=hot).
Color sleepStageColor(BuildContext context, SleepStageKind kind) {
  final colors = FathomColors.of(context);
  return switch (kind) {
    SleepStageKind.light => colors.inkDim,
    SleepStageKind.deep => colors.accent,
    SleepStageKind.rem => colors.amber,
    SleepStageKind.awake => colors.hot,
    SleepStageKind.unknown => colors.inkFaint,
  };
}

Color sleepStageColorForWireType(BuildContext context, int? wireType) {
  return sleepStageColor(context, sleepStageKindFromWireType(wireType));
}
