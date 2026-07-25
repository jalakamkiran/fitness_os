import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fitness_os/app/splash/fathom_splash_timing.dart';
import 'package:fitness_os/app/splash/fathom_wordmark.dart';
import 'package:flutter/material.dart';

/// Cold-start brand moment: Discobolus enters → settles as T → Fa/hom assemble.
///
/// Duration is capped via [FathomSplashTiming.standard] (~1.55s). App icon must
/// remain letter-F only; this figure is splash-only.
class FathomSplashScreen extends StatefulWidget {
  const FathomSplashScreen({
    super.key,
    this.onFinished,
    this.timing = FathomSplashTiming.standard,
    this.autoPlay = true,
  });

  final VoidCallback? onFinished;
  final FathomSplashTiming timing;
  final bool autoPlay;

  @override
  State<FathomSplashScreen> createState() => _FathomSplashScreenState();
}

class _FathomSplashScreenState extends State<FathomSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _finishedNotified = false;

  @override
  void initState() {
    super.initState();
    final total = widget.timing.total;
    _controller = AnimationController(
      vsync: this,
      duration: total <= Duration.zero
          ? const Duration(milliseconds: 1)
          : total,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && total > Duration.zero) {
          _notifyFinished();
        }
      });

    if (widget.autoPlay) {
      if (total <= Duration.zero) {
        _controller.value = 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notifyFinished();
        });
      } else {
        _controller.forward();
      }
    }
  }

  void _notifyFinished() {
    if (_finishedNotified) return;
    _finishedNotified = true;
    // Always defer: AnimationController may complete while ancestors build.
    final callback = widget.onFinished;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final invertAthlete = Theme.of(context).brightness == Brightness.dark;
    final timing = widget.timing;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final athleteOpacity = _athleteOpacity(t, timing);
        final athleteScale = _athleteScale(t, timing);
        final faOpacity = _faOpacity(t, timing);
        final homOpacity = _homOpacity(t, timing);
        final lettersY = _lettersOffsetY(t, timing);

        return ColoredBox(
          color: colors.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 1.05,
                    colors: [
                      colors.accent.withValues(alpha: 0.18),
                      colors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: athleteOpacity,
                  child: FathomWordmark(
                    height: 40,
                    color: colors.ink,
                    athleteScale: athleteScale,
                    faOpacity: faOpacity,
                    homOpacity: homOpacity,
                    lettersOffsetY: lettersY,
                    invertAthlete: invertAthlete,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _athleteOpacity(double t, FathomSplashTiming timing) {
    if (timing.total <= Duration.zero) return 1;
    final end = timing.figureEnd;
    if (end <= 0) return 1;
    return Curves.easeOutCubic.transform((t / end).clamp(0.0, 1.0));
  }

  static double _athleteScale(double t, FathomSplashTiming timing) {
    if (timing.total <= Duration.zero) return 1;
    final figureEnd = timing.figureEnd;
    final settleEnd = timing.settleEnd;
    if (t <= figureEnd) {
      final local = figureEnd == 0 ? 1.0 : (t / figureEnd).clamp(0.0, 1.0);
      return 2.9 - 0.3 * Curves.easeOutCubic.transform(local);
    }
    if (t <= settleEnd) {
      final span = settleEnd - figureEnd;
      final local = span == 0 ? 1.0 : ((t - figureEnd) / span).clamp(0.0, 1.0);
      return 2.6 - 1.6 * Curves.easeOutCubic.transform(local);
    }
    return 1;
  }

  static double _faOpacity(double t, FathomSplashTiming timing) {
    if (timing.total <= Duration.zero) return 1;
    final start = timing.settleEnd;
    final end = timing.lettersEnd;
    if (t <= start) return 0;
    final span = end - start;
    if (span <= 0) return 1;
    // Fa leads slightly (design: 80ms of 700ms ≈ 11%).
    final local = ((t - start) / span).clamp(0.0, 1.0);
    final shifted = ((local - 0.05) / 0.95).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(shifted);
  }

  static double _homOpacity(double t, FathomSplashTiming timing) {
    if (timing.total <= Duration.zero) return 1;
    final start = timing.settleEnd;
    final end = timing.lettersEnd;
    if (t <= start) return 0;
    final span = end - start;
    if (span <= 0) return 1;
    // hom lags slightly (design: 180ms of 700ms ≈ 26%).
    final local = ((t - start) / span).clamp(0.0, 1.0);
    final shifted = ((local - 0.18) / 0.82).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(shifted);
  }

  static double _lettersOffsetY(double t, FathomSplashTiming timing) {
    final opacity = _faOpacity(t, timing);
    return 10 * (1 - opacity);
  }
}

/// Overlays [FathomSplashScreen] above [child] until the brand moment finishes.
///
/// Keeps the real [MaterialApp] route tree mounted underneath so DI bootstrap
/// and first-route build are not blocked beyond the short splash hold.
class FathomSplashGate extends StatefulWidget {
  const FathomSplashGate({
    super.key,
    required this.child,
    this.enabled = true,
    this.timing = FathomSplashTiming.standard,
  });

  final Widget child;
  final bool enabled;
  final FathomSplashTiming timing;

  @override
  State<FathomSplashGate> createState() => _FathomSplashGateState();
}

class _FathomSplashGateState extends State<FathomSplashGate> {
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.enabled;
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: FathomSplashScreen(
            timing: widget.timing,
            onFinished: () {
              if (!mounted) return;
              setState(() => _showSplash = false);
            },
          ),
        ),
      ],
    );
  }
}
