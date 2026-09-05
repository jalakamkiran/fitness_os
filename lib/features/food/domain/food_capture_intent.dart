/// Pending food capture intent from notification tap.
///
/// Singleton coalesce: only one pending intent at a time (slot + localDay).
/// Consumed by RecoveryTabHost when it mounts Food and opens capture.
class FoodCaptureIntent {
  FoodCaptureIntent({
    required this.slot,
    required this.localDay,
  });

  final String slot; // breakfast, lunch, dinner, snack
  final String localDay; // YYYY-MM-DD

  static FoodCaptureIntent? _pending;

  /// Get the pending intent and clear it.
  static FoodCaptureIntent? consumePending() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  /// Set a pending intent (coalesce: overwrites any existing).
  static void setPending(FoodCaptureIntent intent) {
    _pending = intent;
  }

  /// Clear pending intent without consuming.
  static void clearPending() {
    _pending = null;
  }

  /// Check if there's a pending intent.
  static bool hasPending() => _pending != null;

  @override
  String toString() => 'FoodCaptureIntent(slot: $slot, day: $localDay)';
}
