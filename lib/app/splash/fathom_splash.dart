import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Cold-start brand moment: Discobolus enters → settles as T → Fa/hom assemble.
///
/// Canonical motion: `docs/design/logo.html` playable splash.
/// Budget: ~1.6s total so the first interactive frame is not held excessively.
/// App launcher icon stays letter **F** only — this figure is splash-only.
class FathomSplash extends StatefulWidget {
  const FathomSplash({
    super.key,
    required this.onComplete,
    this.figureMs = 320,
    this.settleMs = 380,
    this.lettersMs = 360,
    this.holdMs = 420,
    this.skipAnimation = false,
  });

  /// Called once the hold beat finishes (or immediately when [skipAnimation]).
  final VoidCallback onComplete;

  /// Phase durations (compressed vs HTML prototype for cold-start budget).
  final int figureMs;
  final int settleMs;
  final int lettersMs;
  final int holdMs;

  /// When true, completes on the next frame without driving the timeline.
  final bool skipAnimation;

  /// Asset path for the Discobolus mark (splash / wordmark T only).
  static const assetPath = 'assets/brand/discobolus.png';

  int get totalMs => figureMs + settleMs + lettersMs + holdMs;

  @override
  State<FathomSplash> createState() => _FathomSplashState();
}

enum FathomSplashPhase { idle, figure, settle, letters, hold }

class _FathomSplashState extends State<FathomSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  FathomSplashPhase _phase = FathomSplashPhase.idle;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.totalMs.clamp(1, 2000)),
    )..addListener(_onTick);

    if (widget.skipAnimation) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }

    _controller.forward();
  }

  void _onTick() {
    final t = _controller.value * widget.totalMs;
    final next = _phaseFor(t);
    if (next != _phase) {
      setState(() => _phase = next);
    }
    if (_controller.isCompleted) {
      _finish();
    }
  }

  FathomSplashPhase _phaseFor(double tMs) {
    final f = widget.figureMs.toDouble();
    final s = f + widget.settleMs;
    final l = s + widget.lettersMs;
    if (tMs < f) return FathomSplashPhase.figure;
    if (tMs < s) return FathomSplashPhase.settle;
    if (tMs < l) return FathomSplashPhase.letters;
    return FathomSplashPhase.hold;
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    // Defer so parents can setState safely outside the ticker callback.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Semantics(
      label: 'Fathom',
      child: ColoredBox(
        color: colors.bg,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.55),
              radius: 1.05,
              colors: [
                colors.accent.withValues(alpha: isDark ? 0.16 : 0.18),
                colors.bg.withValues(alpha: 0),
              ],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return _SplashWordmark(
                  phase: widget.skipAnimation
                      ? FathomSplashPhase.hold
                      : _phase,
                  progressMs: widget.skipAnimation
                      ? widget.totalMs.toDouble()
                      : _controller.value * widget.totalMs,
                  figureMs: widget.figureMs,
                  settleMs: widget.settleMs,
                  lettersMs: widget.lettersMs,
                  ink: colors.ink,
                  invertAthlete: isDark,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark({
    required this.phase,
    required this.progressMs,
    required this.figureMs,
    required this.settleMs,
    required this.lettersMs,
    required this.ink,
    required this.invertAthlete,
  });

  final FathomSplashPhase phase;
  final double progressMs;
  final int figureMs;
  final int settleMs;
  final int lettersMs;
  final Color ink;
  final bool invertAthlete;

  static const _wordHeight = 36.0;
  static const _athleteSlotWidth = 28.0;
  static const _curve = Curves.easeOutCubic;

  double get _athleteScale {
    if (phase == FathomSplashPhase.idle) return 2.6;
    if (phase == FathomSplashPhase.figure) {
      final local = (progressMs / figureMs).clamp(0.0, 1.0);
      return Tween<double>(begin: 2.9, end: 2.6)
          .transform(_curve.transform(local));
    }
    if (phase == FathomSplashPhase.settle) {
      final local =
          ((progressMs - figureMs) / settleMs).clamp(0.0, 1.0);
      return Tween<double>(begin: 2.6, end: 1.0)
          .transform(_curve.transform(local));
    }
    return 1.0;
  }

  double get _athleteOpacity {
    if (phase == FathomSplashPhase.idle) return 0;
    if (phase == FathomSplashPhase.figure) {
      final local = (progressMs / figureMs).clamp(0.0, 1.0);
      return _curve.transform(local);
    }
    return 1.0;
  }

  double _letterOpacity({required double delayMs}) {
    if (phase == FathomSplashPhase.hold) return 1;
    if (phase != FathomSplashPhase.letters &&
        phase != FathomSplashPhase.hold) {
      return 0;
    }
    final start = figureMs + settleMs + delayMs;
    final local =
        ((progressMs - start) / (lettersMs - delayMs).clamp(1, lettersMs))
            .clamp(0.0, 1.0);
    return _curve.transform(local);
  }

  double _letterDy({required double delayMs}) {
    final opacity = _letterOpacity(delayMs: delayMs);
    return Tween<double>(begin: 10, end: 0).transform(opacity);
  }

  @override
  Widget build(BuildContext context) {
    final faOpacity = _letterOpacity(delayMs: 80);
    final homOpacity = _letterOpacity(delayMs: 180);

    Widget athlete = Image.asset(
      FathomSplash.assetPath,
      height: _wordHeight,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.accessibility_new,
        size: _wordHeight,
        color: ink,
      ),
    );
    if (invertAthlete) {
      athlete = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: athlete,
      );
    }

    return ExcludeSemantics(
      child: SizedBox(
        height: _wordHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Opacity(
              opacity: faOpacity,
              child: Transform.translate(
                offset: Offset(0, _letterDy(delayMs: 80)),
                child: _GeometricLetters(
                  kind: _LetterGroup.fa,
                  color: ink,
                  height: _wordHeight,
                ),
              ),
            ),
            Padding(
              // Locked a · mark · h breathing room (~0.12em at 36px ≈ 4px).
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: _athleteSlotWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2.9, bottom: 5),
                  child: Opacity(
                    opacity: _athleteOpacity,
                    child: Transform.scale(
                      scale: _athleteScale,
                      alignment: Alignment.bottomCenter,
                      child: athlete,
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: homOpacity,
              child: Transform.translate(
                offset: Offset(0, _letterDy(delayMs: 180)),
                child: _GeometricLetters(
                  kind: _LetterGroup.hom,
                  color: ink,
                  height: _wordHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LetterGroup { fa, hom }

/// Geometric Fa / hom letterforms matching `docs/design/logo.html` symbols.
class _GeometricLetters extends StatelessWidget {
  const _GeometricLetters({
    required this.kind,
    required this.color,
    required this.height,
  });

  final _LetterGroup kind;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final aspect = kind == _LetterGroup.fa ? 52 / 36 : 92 / 36;
    return CustomPaint(
      size: Size(height * aspect, height),
      painter: _LetterPainter(kind: kind, color: color),
    );
  }
}

class _LetterPainter extends CustomPainter {
  _LetterPainter({required this.kind, required this.color});

  final _LetterGroup kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final sx = size.width / (kind == _LetterGroup.fa ? 52 : 92);
    final sy = size.height / 36;
    canvas.scale(sx, sy);

    if (kind == _LetterGroup.fa) {
      // F
      final f = Path()
        ..moveTo(4, 4)
        ..lineTo(24, 4)
        ..lineTo(24, 8.4)
        ..lineTo(9.2, 8.4)
        ..lineTo(9.2, 16)
        ..lineTo(20.4, 16)
        ..lineTo(20.4, 20.4)
        ..lineTo(9.2, 20.4)
        ..lineTo(9.2, 32)
        ..lineTo(4, 32)
        ..close();
      canvas.drawPath(f, paint);

      // a — outer bowl + stem
      final aOuter = Path()
        ..addOval(Rect.fromCircle(center: const Offset(40.7, 22.9), radius: 7.3));
      final aInner = Path()
        ..addOval(Rect.fromCircle(center: const Offset(40.7, 22.9), radius: 4.0));
      canvas.drawPath(
        Path.combine(PathOperation.difference, aOuter, aInner),
        paint,
      );
      canvas.drawRect(const Rect.fromLTWH(44.2, 13.8, 4.2, 18.2), paint);
    } else {
      // h
      canvas.drawRect(const Rect.fromLTWH(4, 4, 4.4, 28), paint);
      final hBowl = Path()
        ..moveTo(8.4, 15)
        ..cubicTo(9.9, 13.5, 12, 12.5, 14.9, 12.5)
        ..cubicTo(20.2, 12.5, 23.8, 16.1, 23.8, 21.8)
        ..lineTo(23.8, 32)
        ..lineTo(19.4, 32)
        ..lineTo(19.4, 22.7)
        ..cubicTo(19.4, 19.3, 17.5, 17.2, 14.4, 17.2)
        ..cubicTo(11.1, 17.2, 8.8, 19.5, 8.8, 22.9)
        ..lineTo(8.8, 32)
        ..lineTo(4.4, 32)
        ..lineTo(4.4, 15)
        ..close();
      canvas.drawPath(hBowl, paint);

      // o
      final oOuter = Path()
        ..addOval(Rect.fromCircle(center: const Offset(38.4, 22.8), radius: 9.2));
      final oInner = Path()
        ..addOval(Rect.fromCircle(center: const Offset(38.4, 22.8), radius: 5.2));
      canvas.drawPath(
        Path.combine(PathOperation.difference, oOuter, oInner),
        paint,
      );

      // m — three stems + arches (simplified geometric)
      canvas.drawRect(const Rect.fromLTWH(54.2, 14.2, 4.3, 17.8), paint);
      canvas.drawRect(const Rect.fromLTWH(65.8, 17.2, 4.3, 14.8), paint);
      canvas.drawRect(const Rect.fromLTWH(77.5, 17.2, 4.3, 14.8), paint);
      canvas.drawRect(const Rect.fromLTWH(88.1, 14.2, 4.3, 17.8), paint);
      // arch connectors
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(56, 14.2, 14, 5.5),
          const Radius.circular(4),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(68, 14.2, 14, 5.5),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LetterPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
