import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/swim_stroke_label.dart';

/// 16px outline stroke glyph for Intervals rows.
///
/// 1 breast (frog), 2 free (dolphin + crawl arc), 3 fly (butterfly),
/// 4 back (same dolphin inverted), 5 medley / unknown → neutral waves.
class SwimStrokeIcon extends StatelessWidget {
  const SwimStrokeIcon({
    super.key,
    required this.style,
    this.size = 16,
  });

  final int? style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurfaceVariant;
    final tooltip = style == null ? 'Unknown stroke' : swimStrokeLabel(style);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SwimStrokePainter(style: style, color: color),
        ),
      ),
    );
  }
}

class _SwimStrokePainter extends CustomPainter {
  const _SwimStrokePainter({required this.style, required this.color});

  final int? style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (style) {
      case 1:
        _paintFrog(canvas, size, paint);
      case 2:
        _paintDolphin(canvas, size, paint, inverted: false);
      case 3:
        _paintButterfly(canvas, size, paint);
      case 4:
        _paintDolphin(canvas, size, paint, inverted: true);
      case 5:
        _paintWaves(canvas, size, paint);
      default:
        _paintWaves(canvas, size, paint);
    }
  }

  /// Side-view dolphin facing right + freestyle crawl arc above.
  /// [inverted] flips vertically for backstroke (same family).
  void _paintDolphin(
    Canvas canvas,
    Size size,
    Paint paint, {
    required bool inverted,
  }) {
    canvas.save();
    if (inverted) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(1, -1);
      canvas.translate(-size.width / 2, -size.height / 2);
    }

    final w = size.width;
    final h = size.height;

    // Body + head (teardrop along midline).
    final body = Path()
      ..moveTo(w * 0.12, h * 0.58)
      ..cubicTo(w * 0.18, h * 0.42, w * 0.45, h * 0.38, w * 0.72, h * 0.48)
      ..cubicTo(w * 0.88, h * 0.52, w * 0.92, h * 0.58, w * 0.86, h * 0.64)
      ..cubicTo(w * 0.55, h * 0.72, w * 0.28, h * 0.70, w * 0.14, h * 0.62)
      ..close();
    canvas.drawPath(body, paint);

    // Tail fluke.
    final fluke = Path()
      ..moveTo(w * 0.12, h * 0.58)
      ..quadraticBezierTo(w * 0.02, h * 0.42, w * 0.08, h * 0.36)
      ..moveTo(w * 0.12, h * 0.58)
      ..quadraticBezierTo(w * 0.00, h * 0.72, w * 0.10, h * 0.78);
    canvas.drawPath(fluke, paint);

    // Dorsal fin.
    final fin = Path()
      ..moveTo(w * 0.48, h * 0.42)
      ..quadraticBezierTo(w * 0.52, h * 0.26, w * 0.62, h * 0.40);
    canvas.drawPath(fin, paint);

    // Crawl arc only on freestyle (not flipped with backstroke).
    if (!inverted) {
      final arc = Path()
        ..moveTo(w * 0.42, h * 0.34)
        ..quadraticBezierTo(w * 0.62, h * 0.08, w * 0.88, h * 0.28);
      canvas.drawPath(arc, paint);
    }

    canvas.restore();
  }

  /// Top-down frog with natural splayed forearms.
  void _paintFrog(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;

    // Body oval.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.52),
        width: w * 0.34,
        height: h * 0.42,
      ),
      paint,
    );

    // Head.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.22),
        width: w * 0.28,
        height: h * 0.22,
      ),
      paint,
    );

    // Natural frog-style arms (bent, splayed forward-out).
    final leftArm = Path()
      ..moveTo(w * 0.38, h * 0.40)
      ..quadraticBezierTo(w * 0.12, h * 0.28, w * 0.08, h * 0.18)
      ..quadraticBezierTo(w * 0.18, h * 0.14, w * 0.22, h * 0.22);
    canvas.drawPath(leftArm, paint);

    final rightArm = Path()
      ..moveTo(w * 0.62, h * 0.40)
      ..quadraticBezierTo(w * 0.88, h * 0.28, w * 0.92, h * 0.18)
      ..quadraticBezierTo(w * 0.82, h * 0.14, w * 0.78, h * 0.22);
    canvas.drawPath(rightArm, paint);

    // Hind legs splayed back.
    final leftLeg = Path()
      ..moveTo(w * 0.40, h * 0.68)
      ..quadraticBezierTo(w * 0.18, h * 0.78, w * 0.10, h * 0.90);
    canvas.drawPath(leftLeg, paint);

    final rightLeg = Path()
      ..moveTo(w * 0.60, h * 0.68)
      ..quadraticBezierTo(w * 0.82, h * 0.78, w * 0.90, h * 0.90);
    canvas.drawPath(rightLeg, paint);
  }

  /// Literal butterfly — two wings + body.
  void _paintButterfly(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.50;
    final cy = h * 0.50;

    // Body.
    canvas.drawLine(
      Offset(cx, h * 0.18),
      Offset(cx, h * 0.82),
      paint,
    );

    // Left wings (upper + lower lobe).
    final left = Path()
      ..moveTo(cx, cy - h * 0.08)
      ..cubicTo(
        w * 0.28,
        h * 0.05,
        w * 0.05,
        h * 0.22,
        w * 0.18,
        h * 0.42,
      )
      ..cubicTo(
        w * 0.08,
        h * 0.58,
        w * 0.22,
        h * 0.78,
        cx,
        cy + h * 0.10,
      );
    canvas.drawPath(left, paint);

    // Right wings (mirror).
    final right = Path()
      ..moveTo(cx, cy - h * 0.08)
      ..cubicTo(
        w * 0.72,
        h * 0.05,
        w * 0.95,
        h * 0.22,
        w * 0.82,
        h * 0.42,
      )
      ..cubicTo(
        w * 0.92,
        h * 0.58,
        w * 0.78,
        h * 0.78,
        cx,
        cy + h * 0.10,
      );
    canvas.drawPath(right, paint);
  }

  /// Neutral waves for medley / unknown.
  void _paintWaves(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final upper = Path()
      ..moveTo(w * 0.08, h * 0.40)
      ..cubicTo(w * 0.22, h * 0.22, w * 0.38, h * 0.58, w * 0.52, h * 0.40)
      ..cubicTo(w * 0.66, h * 0.22, w * 0.82, h * 0.58, w * 0.92, h * 0.40);
    canvas.drawPath(upper, paint);

    final lower = Path()
      ..moveTo(w * 0.08, h * 0.68)
      ..cubicTo(w * 0.22, h * 0.50, w * 0.38, h * 0.86, w * 0.52, h * 0.68)
      ..cubicTo(w * 0.66, h * 0.50, w * 0.82, h * 0.86, w * 0.92, h * 0.68);
    canvas.drawPath(lower, paint);
  }

  @override
  bool shouldRepaint(covariant _SwimStrokePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}
