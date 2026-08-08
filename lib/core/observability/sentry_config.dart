import 'package:flutter/foundation.dart';

/// Compile-time Sentry / observability flags from `--dart-define-from-file=.env`.
abstract final class SentryConfig {
  static const dsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  /// Force Sentry on even in debug (owner digs). Prefer release/profile.
  static const forceEnabled = bool.fromEnvironment(
    'SENTRY_FORCE',
    defaultValue: false,
  );

  static bool get hasDsn => dsn.trim().isNotEmpty;

  /// Profile/release by default; debug only with [forceEnabled].
  static bool get shouldInitialize {
    if (!hasDsn) return false;
    if (forceEnabled) return true;
    return kReleaseMode || kProfileMode;
  }
}
