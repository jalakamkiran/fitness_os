import 'package:flutter/material.dart';

/// Compact Strava mark (orange mountain) for TCX share affordances.
///
/// Not the official trademark asset — a simplified three-peak silhouette in
/// Strava orange so the AppBar action reads as "upload to Strava" vs generic share.
class StravaMarkIcon extends StatelessWidget {
  const StravaMarkIcon({super.key, this.size = 22});

  final double size;

  /// Brand orange commonly associated with Strava uploads.
  static const Color brandOrange = Color(0xFFFC4C02);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StravaMarkPainter(color: brandOrange),
      ),
    );
  }
}

class _StravaMarkPainter extends CustomPainter {
  _StravaMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Left peak (lighter via opacity) + right peak — classic Strava "S" mountain.
    final left = Path()
      ..moveTo(size.width * 0.08, size.height * 0.88)
      ..lineTo(size.width * 0.38, size.height * 0.12)
      ..lineTo(size.width * 0.58, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.88)
      ..close();

    final right = Path()
      ..moveTo(size.width * 0.42, size.height * 0.88)
      ..lineTo(size.width * 0.62, size.height * 0.42)
      ..lineTo(size.width * 0.92, size.height * 0.88)
      ..close();

    canvas.drawPath(
      left,
      paint..color = color.withValues(alpha: 0.55),
    );
    canvas.drawPath(right, paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _StravaMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
