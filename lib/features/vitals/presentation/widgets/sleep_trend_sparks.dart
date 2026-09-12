import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';

/// Dual spark: score + sleep HRV vs 7-day mean ± ½ SD band.
class SleepTrendSparks extends StatelessWidget {
  const SleepTrendSparks({super.key, required this.band});

  final SleepTrendBand band;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final score = band.latestScore;
    final hrv = band.latestHrv;
    if (score == null && hrv == null) return const SizedBox.shrink();

    String? scoreDelta;
    if (score != null && band.scoreMean != null) {
      final d = (score - band.scoreMean!).round();
      scoreDelta = d >= 0 ? '↑ baseline' : '↓ baseline';
    }
    String? hrvDelta;
    if (hrv != null && band.hrvMean != null) {
      final d = (hrv - band.hrvMean!).round();
      final sign = d >= 0 ? '+' : '';
      hrvDelta = d >= 0 ? '↑ $sign$d' : '↓ $d';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Overnight signals · 7-day band',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (score != null)
                  Expanded(
                    child: _Spark(
                      title: 'Score',
                      value: '$score',
                      delta: scoreDelta,
                      deltaUp: scoreDelta?.startsWith('↑') ?? true,
                      values: [
                        for (final p in band.points)
                          if (p.score != null && p.score! > 0)
                            p.score!.toDouble(),
                      ],
                      mean: band.scoreMean,
                      halfSd: band.scoreHalfSd,
                      lineColor: colors.accent,
                    ),
                  ),
                if (score != null && hrv != null) const SizedBox(width: 12),
                if (hrv != null)
                  Expanded(
                    child: _Spark(
                      title: 'Sleep HRV',
                      value: '$hrv',
                      delta: hrvDelta,
                      deltaUp: hrvDelta?.startsWith('↑') ?? true,
                      values: [
                        for (final p in band.points)
                          if (p.hrv != null) p.hrv!.toDouble(),
                      ],
                      mean: band.hrvMean,
                      halfSd: band.hrvHalfSd,
                      lineColor: colors.ink,
                      caption: 'Night average · ms',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Band = 7d mean ± ½ SD',
              style: FathomTextStyles.mono(
                fontSize: 10,
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({
    required this.title,
    required this.value,
    required this.values,
    required this.lineColor,
    this.delta,
    this.deltaUp = true,
    this.mean,
    this.halfSd,
    this.caption,
  });

  final String title;
  final String value;
  final String? delta;
  final bool deltaUp;
  final List<double> values;
  final double? mean;
  final double? halfSd;
  final Color lineColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              value,
              style: FathomTextStyles.mono(
                fontSize: 18,
                color: colors.ink,
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: 6),
              Text(
                delta!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: deltaUp ? colors.up : colors.hot,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparkPainter(
              values: values,
              mean: mean,
              halfSd: halfSd,
              lineColor: lineColor,
              bandColor: colors.accent.withValues(alpha: 0.14),
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.lineColor,
    required this.bandColor,
    this.mean,
    this.halfSd,
  });

  final List<double> values;
  final double? mean;
  final double? halfSd;
  final Color lineColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (mean != null && halfSd != null) {
      minV = minV < (mean! - halfSd!) ? minV : (mean! - halfSd!);
      maxV = maxV > (mean! + halfSd!) ? maxV : (mean! + halfSd!);
    }
    final span = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    double yOf(double v) => size.height * (1 - ((v - minV) / span));

    if (mean != null && halfSd != null) {
      final top = yOf(mean! + halfSd!);
      final bot = yOf(mean! - halfSd!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, size.width, bot),
          const Radius.circular(2),
        ),
        Paint()..color = bandColor,
      );
    }

    if (values.length == 1) {
      final y = yOf(values.first);
      canvas.drawCircle(Offset(size.width, y), 2.5, Paint()..color = lineColor);
      return;
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final y = yOf(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.mean != mean ||
      oldDelegate.halfSd != halfSd;
}
