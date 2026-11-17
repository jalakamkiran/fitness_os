import 'dart:convert';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:fitness_os/core/observability/sentry_config.dart';
import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';

/// Raw workout payload dumping for reverse-engineering (owner explicit consent).
///
/// Captures full TLV hex for racket sports to identify unknown fields like
/// swing count, rally data, cadence. Only enabled with SENTRY_RAW_WORKOUT_DUMP=true.
///
/// **Privacy**: MAC addresses and user IDs still redacted. Health data (HR values,
/// GPS) included by owner request for debugging only. This is a debugging tool.
abstract final class RawWorkoutDump {
  static const _maxAttachmentBytes = 500 * 1024; // 500 KB per attachment

  /// Whether raw dumps are enabled (requires both Sentry and flag).
  static bool get isEnabled => SentryConfig.shouldDumpRawWorkouts;

  /// Dump raw workout totals for racket sports (badminton, tennis, etc.).
  ///
  /// Captures:
  /// - Workout metadata (id, type, start/end)
  /// - Raw totals TLV hex (full payload)
  /// - Unknown/leftover TLVs with full hex values
  /// - Command/service IDs
  static Future<void> dumpRacketWorkoutTotals({
    required int workoutNumber,
    required int typeCode,
    required int startTime,
    required int endTime,
    required int durationSec,
    required String rawTotalsHex,
    List<Map<String, dynamic>>? unknownTlvs,
    List<Map<String, dynamic>>? leftoverTlvs,
    Map<String, dynamic>? additionalContext,
  }) async {
    if (!isEnabled) return;

    try {
      final metadata = {
        'workoutNumber': workoutNumber,
        'typeCode': typeCode,
        'typeName': _typeCodeName(typeCode),
        'startTime': startTime,
        'endTime': endTime,
        'durationSec': durationSec,
        'service': '0x17',
        'command': '0x08',
        'commandName': 'WorkoutTotals',
        if (additionalContext != null) ...additionalContext,
      };

      final dump = {
        'version': '1.0',
        'dumpType': 'racket_workout_totals',
        'metadata': metadata,
        'rawTotalsHex': rawTotalsHex,
        'rawTotalsLength': rawTotalsHex.length ~/ 2,
        if (unknownTlvs != null && unknownTlvs.isNotEmpty)
          'unknownTlvs': unknownTlvs,
        if (leftoverTlvs != null && leftoverTlvs.isNotEmpty)
          'leftoverTlvs': leftoverTlvs,
      };

      await _sendDump(
        message: 'badminton.raw_dump.totals',
        dump: dump,
        level: SentryLevel.info,
      );
    } catch (e) {
      // Never crash on observability
      print('Failed to dump raw workout totals: $e');
    }
  }

  /// Dump raw workout enrichment data (WorkoutData pages, samples).
  ///
  /// Captures:
  /// - Per-page metadata
  /// - Raw sample stream hex
  /// - Unknown TLVs in data pages
  static Future<void> dumpRacketWorkoutData({
    required int workoutNumber,
    required int typeCode,
    required List<Map<String, dynamic>> dataPages,
    String? rawSampleStreamHex,
    Map<String, dynamic>? additionalContext,
  }) async {
    if (!isEnabled) return;

    try {
      final metadata = {
        'workoutNumber': workoutNumber,
        'typeCode': typeCode,
        'typeName': _typeCodeName(typeCode),
        'service': '0x17',
        'command': '0x0a',
        'commandName': 'WorkoutData',
        'pageCount': dataPages.length,
        if (additionalContext != null) ...additionalContext,
      };

      final dump = {
        'version': '1.0',
        'dumpType': 'racket_workout_data',
        'metadata': metadata,
        'dataPages': dataPages,
        if (rawSampleStreamHex != null) 'rawSampleStreamHex': rawSampleStreamHex,
        if (rawSampleStreamHex != null)
          'rawSampleStreamLength': rawSampleStreamHex.length ~/ 2,
      };

      await _sendDump(
        message: 'badminton.raw_dump.data',
        dump: dump,
        level: SentryLevel.info,
      );
    } catch (e) {
      print('Failed to dump raw workout data: $e');
    }
  }

  /// Dump raw pace blocks (if present for racket sports).
  static Future<void> dumpRacketWorkoutPace({
    required int workoutNumber,
    required int typeCode,
    required List<Map<String, dynamic>> paceBlocks,
    Map<String, dynamic>? additionalContext,
  }) async {
    if (!isEnabled) return;

    try {
      final metadata = {
        'workoutNumber': workoutNumber,
        'typeCode': typeCode,
        'typeName': _typeCodeName(typeCode),
        'service': '0x17',
        'command': '0x0c',
        'commandName': 'Pace',
        'blockCount': paceBlocks.length,
        if (additionalContext != null) ...additionalContext,
      };

      final dump = {
        'version': '1.0',
        'dumpType': 'racket_workout_pace',
        'metadata': metadata,
        'paceBlocks': paceBlocks,
      };

      await _sendDump(
        message: 'badminton.raw_dump.pace',
        dump: dump,
        level: SentryLevel.info,
      );
    } catch (e) {
      print('Failed to dump raw workout pace: $e');
    }
  }

  static Future<void> _sendDump({
    required String message,
    required Map<String, dynamic> dump,
    required SentryLevel level,
  }) async {
    final sentryMessage = SentryMessage(message);
    
    // Redact MAC addresses in the dump (everything else is explicitly consented)
    final redactedDump = _redactMacs(dump);
    
    // Convert to JSON
    final jsonDump = jsonEncode(redactedDump);
    final jsonBytes = utf8.encode(jsonDump);

    // If small enough, include in extras; otherwise use attachment
    if (jsonBytes.length <= _maxAttachmentBytes) {
      final event = SentryEvent(
        message: sentryMessage,
        level: level,
        extra: {'dump': redactedDump},
      );
      await Sentry.captureEvent(event);
    } else {
      // Split into chunks if necessary
      final chunks = _chunkBytes(jsonBytes, _maxAttachmentBytes);
      
      for (var i = 0; i < chunks.length; i++) {
        final chunkMessage = SentryMessage('$message.chunk_${i + 1}_of_${chunks.length}');
        final attachment = SentryAttachment.fromUint8List(
          chunks[i],
          'workout_dump_chunk_${i + 1}.json',
          contentType: 'application/json',
        );
        
        final event = SentryEvent(
          message: chunkMessage,
          level: level,
          extra: {
            'chunkIndex': i + 1,
            'totalChunks': chunks.length,
            'chunkSize': chunks[i].length,
          },
        );
        
        await Sentry.captureEvent(event, hint: Hint.withAttachments([attachment]));
      }
    }
  }

  static Map<String, dynamic> _redactMacs(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is String) {
        result[key] = SentryPrivacyScrub.redactText(value);
      } else if (value is Map) {
        result[key] = _redactMacs(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map) return _redactMacs(Map<String, dynamic>.from(item));
          if (item is String) return SentryPrivacyScrub.redactText(item);
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  static List<Uint8List> _chunkBytes(List<int> bytes, int chunkSize) {
    final chunks = <Uint8List>[];
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      chunks.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    return chunks;
  }

  static String _typeCodeName(int code) {
    const names = {
      129: 'Badminton',
      130: 'Table tennis',
      131: 'Tennis',
      133: 'Squash',
    };
    return names[code] ?? 'Racket sport $code';
  }
}
