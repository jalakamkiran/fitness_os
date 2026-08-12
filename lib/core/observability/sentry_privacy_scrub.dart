import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs PII / health payloads from Sentry envelopes (defense in depth).
///
/// Instrumentation must still never attach MethodChannel maps — this is the
/// last gate before upload.
abstract final class SentryPrivacyScrub {
  static final _macColon = RegExp(
    r'\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b',
  );
  static final _macPlain = RegExp(r'\b[0-9A-Fa-f]{12}\b');
  static final _hexDump = RegExp(r'\b(?:[0-9A-Fa-f]{2}[\s:]){8,}[0-9A-Fa-f]{2}\b');

  static const forbiddenKeys = {
    'workouts',
    'segments',
    'dataPages',
    'paceBlocks',
    'dailyHrSamples',
    'sleepSessions',
    'fitnessTotals',
    'hrSeries',
    'samples',
    'mac',
    'userId',
    'phoneMac',
    'gemini_api_key',
    'geminiApiKey',
    'authKey',
    'secret',
    'secrets',
    'details',
    'arguments',
    'result',
    // Hooper-4 morning wellness (local prefs; never upload scores).
    'sleepQuality',
    'fatigue',
    'soreness',
    'stress',
    'morningWellness',
    'sleep_feel_on_wake_json',
    'sleepFeelOnWakeJson',
  };

  static String redactText(String input) {
    var out = input;
    out = out.replaceAll(_macColon, '••:••:••:••:••:••');
    out = out.replaceAllMapped(_macPlain, (m) {
      final v = m[0]!;
      // Avoid redacting short hex that isn't a MAC-like blob.
      if (v.length != 12) return v;
      return '••••••••••••';
    });
    out = out.replaceAll(_hexDump, '[hex-redacted]');
    return out;
  }

  static Map<String, dynamic>? scrubMap(Map<String, dynamic>? input) {
    if (input == null) return null;
    final out = <String, dynamic>{};
    for (final e in input.entries) {
      final key = e.key;
      if (forbiddenKeys.contains(key) ||
          forbiddenKeys.contains(key.toLowerCase())) {
        continue;
      }
      final value = e.value;
      if (value is String) {
        out[key] = redactText(value);
      } else if (value is Map) {
        final nested = scrubMap(Map<String, dynamic>.from(value));
        if (nested != null && nested.isNotEmpty) out[key] = nested;
      } else if (value is List) {
        // Drop list payloads that look like health rows.
        if (key.toLowerCase().contains('workout') ||
            key.toLowerCase().contains('sleep') ||
            key.toLowerCase().contains('hr') ||
            key.toLowerCase().contains('sample') ||
            key.toLowerCase().contains('segment')) {
          continue;
        }
        out[key] = value;
      } else {
        out[key] = value;
      }
    }
    return out;
  }

  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    final message = event.message;
    final formatted = message?.formatted;
    final scrubbedMessage = formatted != null
        ? SentryMessage(redactText(formatted))
        : message;
    final extras = event.extra;
    final scrubbedExtra =
        extras == null ? null : scrubMap(Map<String, dynamic>.from(extras));
    final tags = event.tags;
    final scrubbedTags = tags == null
        ? null
        : {
            for (final e in tags.entries) e.key: redactText(e.value),
          };
    return event.copyWith(
      message: scrubbedMessage,
      extra: scrubbedExtra,
      tags: scrubbedTags,
    );
  }

  static SentryTransaction? beforeSendTransaction(
    SentryTransaction transaction,
  ) {
    final extras = transaction.extra;
    final scrubbedExtra =
        extras == null ? null : scrubMap(Map<String, dynamic>.from(extras));
    final tags = transaction.tags;
    final scrubbedTags = tags == null
        ? null
        : {
            for (final e in tags.entries) e.key: redactText(e.value),
          };
    return transaction.copyWith(
      extra: scrubbedExtra,
      tags: scrubbedTags,
    );
  }

  static Breadcrumb? beforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
    if (breadcrumb == null) return null;
    final msg = breadcrumb.message;
    final data = breadcrumb.data;
    return breadcrumb.copyWith(
      message: msg == null ? null : redactText(msg),
      data: data == null ? null : scrubMap(Map<String, dynamic>.from(data)),
    );
  }
}
