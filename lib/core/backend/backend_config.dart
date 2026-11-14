abstract final class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://asia-south1-fathom-fitness-os.cloudfunctions.net/api',
  );

  static const String writeKey = String.fromEnvironment(
    'BACKEND_WRITE_KEY',
    defaultValue: '',
  );

  static bool get isEnabled => writeKey.isNotEmpty;
}
