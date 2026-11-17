/// Compile-time feature flags (`--dart-define`).
abstract final class FeatureFlags {
  static const bool liftWatch =
      bool.fromEnvironment('FATHOM_LIFT_WATCH', defaultValue: false);
}