import 'package:flutter/foundation.dart';

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

  static void logStartupStatus() {
    if (!isEnabled) {
      debugPrint('⚠️  Backend sync DISABLED: BACKEND_WRITE_KEY not provided at build time');
      debugPrint('   Data will only be stored locally on this device.');
      debugPrint('   To enable backend sync, rebuild with:');
      debugPrint('   flutter build apk --dart-define=BACKEND_WRITE_KEY=<key>');
    } else {
      debugPrint('✅ Backend sync ENABLED: Data will sync to $baseUrl');
    }
  }
}
