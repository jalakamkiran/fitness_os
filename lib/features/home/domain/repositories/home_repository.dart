import 'package:fitness_os/features/home/domain/home_precedence.dart';

/// Loads the calm Home now-state and runs one-shot Sync from Home CTAs.
abstract class HomeRepository {
  Future<HomeSnapshot> loadSnapshot();

  /// Workouts + vitals pass; updates Home sync status prefs.
  Future<bool> syncNow();
}
