import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:fitness_os/core/observability/sentry_config.dart';

/// Workout sync observability breadcrumbs (privacy-safe).
///
/// Never logs health data values (HR, GPS, sample bodies). Only codes, counts,
/// and error context for debugging workout type mapping and parsing.
abstract final class WorkoutSyncBreadcrumbs {
  static bool get _isEnabled => SentryConfig.shouldInitialize;

  /// Record when an unknown workout type code is encountered.
  static void unknownWorkoutType(int typeCode) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Unknown workout type encountered',
        category: 'workout.type',
        level: SentryLevel.warning,
        data: {
          'typeCode': typeCode,
        },
      ),
    );
  }

  /// Record successful workout type mapping.
  static void mappedWorkoutType(int typeCode, String label) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Workout type mapped: $label',
        category: 'workout.type',
        level: SentryLevel.debug,
        data: {
          'typeCode': typeCode,
          'label': label,
        },
      ),
    );
  }

  /// Record workout sync start.
  static void syncStart({
    required int startUnix,
    required int endUnix,
    required int enrichStartUnix,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Workout sync started',
        category: 'workout.sync',
        level: SentryLevel.info,
        data: {
          'startUnix': startUnix,
          'endUnix': endUnix,
          'enrichStartUnix': enrichStartUnix,
          'windowDays': ((endUnix - startUnix) / 86400).round(),
        },
      ),
    );
  }

  /// Record workout sync completion.
  static void syncComplete({
    required String status,
    required int workoutCount,
    int? enrichedCount,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Workout sync complete: $status',
        category: 'workout.sync',
        level: status == 'ok' ? SentryLevel.info : SentryLevel.warning,
        data: {
          'status': status,
          'workoutCount': workoutCount,
          if (enrichedCount != null) 'enrichedCount': enrichedCount,
        },
      ),
    );
  }

  /// Record workout sync error.
  static void syncError(String message, {Object? error, StackTrace? stackTrace}) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Workout sync error: $message',
        category: 'workout.sync',
        level: SentryLevel.error,
        data: {
          'errorMessage': message,
          if (error != null) 'errorType': error.runtimeType.toString(),
        },
      ),
    );
    
    if (error != null) {
      Sentry.captureException(
        error,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'workout_sync', 'message': message}),
      );
    }
  }

  /// Record TLV parse failure (tag ID and length only, never body).
  static void tlvParseFailure({
    required int tag,
    required int length,
    required String context,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'TLV parse failure',
        category: 'workout.parse',
        level: SentryLevel.warning,
        data: {
          'tag': '0x${tag.toRadixString(16)}',
          'length': length,
          'context': context,
        },
      ),
    );
  }

  /// Record workout enrichment (data/pace/segments counts).
  static void enrichment({
    required int workoutNumber,
    required int dataCount,
    required int paceCount,
    required int segmentsCount,
    required String status,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Workout enrichment: #$workoutNumber',
        category: 'workout.enrich',
        level: SentryLevel.debug,
        data: {
          'workoutNumber': workoutNumber,
          'dataCount': dataCount,
          'paceCount': paceCount,
          'segmentsCount': segmentsCount,
          'status': status,
        },
      ),
    );
  }

  /// Record badminton-specific data parsing.
  static void badmintonData({
    required int workoutNumber,
    Map<String, dynamic>? metrics,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Badminton workout data parsed: #$workoutNumber',
        category: 'workout.badminton',
        level: SentryLevel.info,
        data: {
          'workoutNumber': workoutNumber,
          if (metrics != null) ...metrics,
        },
      ),
    );
  }

  /// Record when raw payload size exceeds expected bounds.
  static void unusualPayloadSize({
    required String context,
    required int size,
    required int expected,
  }) {
    if (!_isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Unusual payload size: $context',
        category: 'workout.payload',
        level: SentryLevel.warning,
        data: {
          'context': context,
          'actualSize': size,
          'expectedSize': expected,
          'ratio': (size / expected).toStringAsFixed(2),
        },
      ),
    );
  }
}
