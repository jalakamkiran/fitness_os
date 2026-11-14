abstract final class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );

  static const String writeKey = String.fromEnvironment(
    'BACKEND_WRITE_KEY',
    defaultValue: '',
  );

  static bool get isEnabled => baseUrl.isNotEmpty && writeKey.isNotEmpty;
}
