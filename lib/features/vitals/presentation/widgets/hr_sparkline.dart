import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Minute-level HR sparkline from persisted side-file samples.
class HrSparkline extends StatelessWidget {
  const HrSparkline({
    super.key,
    required this.samples,
    this.height = 120,
  });

  final List<DailyHrSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            samples.isEmpty
                ? 'No minute samples for this day'
                : 'Need more samples to chart (${samples.length})',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final minBpm = samples.map((s) => s.bpm).reduce(math.min);
    final maxBpm = samples.map((s) => s.bpm).reduce(math.max);
    final pad = math.max(4, ((maxBpm - minBpm) * 0.08).round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _HrSparklinePainter(
              samples: samples,
              lineColor: scheme.primary,
              fillColor: scheme.primary.withValues(alpha: 0.12),
              minBpm: minBpm - pad,
              maxBpm: maxBpm + pad,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatTime(samples.first.timestampUnix),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              '${samples.length} samples · $minBpm–$maxBpm bpm',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              _formatTime(samples.last.timestampUnix),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(int unixSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _HrSparklinePainter extends CustomPainter {
  _HrSparklinePainter({
    required this.samples,
    required this.lineColor,
    required this.fillColor,
    required this.minBpm,
    required this.maxBpm,
  });

  final List<DailyHrSample> samples;
  final Color lineColor;
  final Color fillColor;
  final int minBpm;
  final int maxBpm;

  @override
  void paint(Canvas canvas, Size size) {
    final range = (maxBpm - minBpm).clamp(1, 999);
    final points = <Offset>[];
    final n = samples.length;

    for (var i = 0; i < n; i++) {
      final x = n == 1 ? 0.0 : i / (n - 1) * size.width;
      final yNorm = (samples[i].bpm - minBpm) / range;
      final y = size.height - (yNorm * size.height);
      points.add(Offset(x, y));
    }

    final fillPath = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HrSparklinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.minBpm != minBpm ||
        oldDelegate.maxBpm != maxBpm;
  }
}
