import 'package:fitness_os/features/home/domain/home_precedence.dart';

/// Result of a sync operation with optional error details.
class SyncResult {
  final bool success;
  final String? errorDetails;

  const SyncResult({required this.success, this.errorDetails});
  
  factory SyncResult.ok() => const SyncResult(success: true);
  factory SyncResult.failed(String details) => SyncResult(success: false, errorDetails: details);
}

/// Loads the calm Home now-state and runs one-shot Sync from Home CTAs.
abstract class HomeRepository {
  Future<HomeSnapshot> loadSnapshot();

  /// Workouts + vitals pass; updates Home sync status prefs.
  Future<SyncResult> syncNow();
}
