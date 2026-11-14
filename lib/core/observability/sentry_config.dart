import 'package:flutter/foundation.dart';

/// Compile-time Sentry / observability flags from `--dart-define-from-file=.env`.
abstract final class SentryConfig {
  static const dsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  /// Force Sentry on even in debug (owner digs). Prefer release/profile.
  static const forceEnabled = bool.fromEnvironment(
    'SENTRY_FORCE',
    defaultValue: false,
  );

  /// Enable raw workout payload dumps for reverse-engineering (owner explicit consent).
  /// Captures full TLV hex for racket sports (badminton, tennis, etc.) to identify
  /// unknown fields like swing count, rally data, cadence.
  /// Default: on for debug, off for release (can be overridden).
  static const rawWorkoutDump = bool.fromEnvironment(
    'SENTRY_RAW_WORKOUT_DUMP',
    defaultValue: kDebugMode,
  );

  static bool get hasDsn => dsn.trim().isNotEmpty;

  /// Profile/release by default; debug only with [forceEnabled].
  static bool get shouldInitialize {
    if (!hasDsn) return false;
    if (forceEnabled) return true;
    return kReleaseMode || kProfileMode;
  }

  /// Whether to capture raw workout payloads (requires Sentry initialized + flag).
  static bool get shouldDumpRawWorkouts =>
      shouldInitialize && rawWorkoutDump;
}
