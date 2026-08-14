import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fitness_os/features/workout_history/domain/swim_stroke_label.dart';

/// Intervals-row stroke glyph.
///
/// 1 breast (frog), 2 free (otter swimming), 3 fly (butterfly),
/// 4 back (otter on its back), 5 / unknown → waves.
///
/// Tinted with [FathomColors.inkDim] so light/dark pool-night both stay
/// readable on [FathomColors.bgElev] table cells.
class SwimStrokeIcon extends StatelessWidget {
  const SwimStrokeIcon({
    super.key,
    required this.style,
    this.size = 18,
  });

  final int? style;
  final double size;

  static String assetFor(int? style) {
    return switch (style) {
      1 => 'assets/icons/swim/stroke_breaststroke.svg',
      2 => 'assets/icons/swim/stroke_freestyle.svg',
      3 => 'assets/icons/swim/stroke_butterfly.svg',
      4 => 'assets/icons/swim/stroke_backstroke.svg',
      _ => 'assets/icons/swim/stroke_unknown.svg',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final tooltip = style == null ? 'Unknown stroke' : swimStrokeLabel(style);

    return Tooltip(
      message: tooltip,
      child: SvgPicture.asset(
        assetFor(style),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(colors.inkDim, BlendMode.srcIn),
      ),
    );
  }
}
