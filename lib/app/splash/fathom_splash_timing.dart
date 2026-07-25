/// Compressed cold-start budget for the Fathom splash brand moment.
///
/// Canonical playable splash in `docs/design/logo.html` is longer (~4.4s).
/// Product constraint: do not block first interactive frame excessively
/// (~1–2s max hold including figure → settle → letters → hold).
class FathomSplashTiming {
  const FathomSplashTiming({
    required this.figure,
    required this.settle,
    required this.letters,
    required this.hold,
  });

  /// Discobolus enters at hero scale.
  final Duration figure;

  /// Settles down to word-height (becomes the T).
  final Duration settle;

  /// Fa + hom assemble around the mark.
  final Duration letters;

  /// Brief hold on completed wordmark before dismissing.
  final Duration hold;

  /// Default product timing (~1.55s total).
  static const FathomSplashTiming standard = FathomSplashTiming(
    figure: Duration(milliseconds: 280),
    settle: Duration(milliseconds: 420),
    letters: Duration(milliseconds: 380),
    hold: Duration(milliseconds: 470),
  );

  /// Instant completion for widget tests that must not hang.
  static const FathomSplashTiming instant = FathomSplashTiming(
    figure: Duration.zero,
    settle: Duration.zero,
    letters: Duration.zero,
    hold: Duration.zero,
  );

  Duration get total => figure + settle + letters + hold;

  double get figureEnd => _ratio(figure);

  double get settleEnd => _ratio(figure + settle);

  double get lettersEnd => _ratio(figure + settle + letters);

  double _ratio(Duration at) {
    final t = total.inMilliseconds;
    if (t <= 0) return 1;
    return at.inMilliseconds / t;
  }
}
