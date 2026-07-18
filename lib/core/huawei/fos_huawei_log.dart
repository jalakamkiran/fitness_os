import 'package:flutter/foundation.dart';

/// Filter logcat / Debug Console with: `FOS_HUAWEI`
///
/// Examples:
/// - Cursor Debug Console: search `FOS_HUAWEI`
/// - adb: `adb logcat -s flutter FOS_HUAWEI | grep FOS_HUAWEI`
abstract final class FosHuaweiLog {
  static const tag = 'FOS_HUAWEI';

  static void d(String message, {String? op}) {
    _write('D', message, op: op);
  }

  static void i(String message, {String? op}) {
    _write('I', message, op: op);
  }

  static void w(String message, {String? op}) {
    _write('W', message, op: op);
  }

  static void e(String message, {Object? error, String? op}) {
    final suffix = error == null ? '' : ' | $error';
    _write('E', '$message$suffix', op: op);
  }

  static void _write(String level, String message, {String? op}) {
    if (!kDebugMode) return;
    final scope = op == null ? '' : '($op) ';
    // Prefix stays in the message so Flutter's `I/flutter` lines are greppable.
    debugPrint('[$tag] $level $scope$message');
  }
}
