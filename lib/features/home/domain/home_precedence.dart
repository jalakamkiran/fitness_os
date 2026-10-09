import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Home pairing/sync chrome states (design home-states.html).
///
/// Deterministic hierarchy — evaluate in this order only:
/// 1. [notPaired]
/// 2. [syncInProgress]
/// 3. [pairedNeverSynced]
/// 4. [syncFailed]
/// 5. [dataAvailable] — trusted day context (rest or multi-sport)
///
/// Day stack blocks are independent of swim presence. Empty sessions are data
/// on [HomeSnapshot.todaySessions], not a separate precedence.
enum HomePrecedence {
  notPaired,
  pairedNeverSynced,
  syncInProgress,
  syncFailed,
  dataAvailable,
}

/// Inputs for [resolveHomePrecedence]. Keep this surface stable for tests.
class HomePrecedenceInputs {
  const HomePrecedenceInputs({
    required this.isPaired,
    required this.everSynced,
    required this.syncInProgress,
    required this.syncFailed,
  });

  final bool isPaired;
  final bool everSynced;
  final bool syncInProgress;
  final bool syncFailed;
}

/// Pure precedence resolver — single source of truth for Home chrome branching.
HomePrecedence resolveHomePrecedence(HomePrecedenceInputs inputs) {
  if (!inputs.isPaired) return HomePrecedence.notPaired;
  if (inputs.syncInProgress) return HomePrecedence.syncInProgress;
  if (!inputs.everSynced) return HomePrecedence.pairedNeverSynced;
  if (inputs.syncFailed) return HomePrecedence.syncFailed;
  return HomePrecedence.dataAvailable;
}

/// One attributable today-session row for Home (opens [workout] detail).
class HomeTodaySessionCard {
  const HomeTodaySessionCard({
    required this.workout,
    required this.title,
    required this.whenLabel,
    this.meta = const [],
  });

  final WorkoutSummary workout;
  final String title;
  final String whenLabel;

  /// Plain load / TE / recovery (etc.) fields — omit absent signals.
  final List<({String label, String value})> meta;
}

/// Calm Today instrument snapshot for Home.
class HomeSnapshot {
  const HomeSnapshot({
    required this.precedence,
    this.deviceLabel = 'GT5',
    this.brandSubtitle = '',
    this.syncPillLabel = '',
    this.syncTitle = '',
    this.syncCaption = '',
    this.lastSyncedLabel,
    this.caloriesLabel,
    this.stepsLabel,
    this.workoutTimeLabel,
    this.sleepDurationLabel,
    this.sleepWindowLabel,
    this.sleepFeelCue,
    this.recoveryTimeLabel,
    this.bodyHrLabel,
    this.bodyHrSparkSamples = const [],
    this.todaySessions = const [],
  });

  final HomePrecedence precedence;
  final String deviceLabel;
  final String brandSubtitle;
  final String syncPillLabel;
  final String syncTitle;
  final String syncCaption;
  final String? lastSyncedLabel;
  final String? caloriesLabel;
  final String? stepsLabel;
  final String? workoutTimeLabel;
  final String? sleepDurationLabel;
  final String? sleepWindowLabel;

  /// Short feel-on-wake cue when already answered for the displayed sleep.
  final String? sleepFeelCue;

  /// Overall recovery hours for the Home **Recovery time** card (`14h` / `0h` / `—`).
  /// Null when chrome-only (card hidden). Never a readiness %.
  final String? recoveryTimeLabel;

  /// Today HR rollup `min · avg · max` — omit when no today dayKey.
  final String? bodyHrLabel;

  /// Today HR series for one tiny spark; empty / &lt;2 → no spark.
  final List<DailyHrSample> bodyHrSparkSamples;

  /// Today's workouts ordered by start ascending.
  final List<HomeTodaySessionCard> todaySessions;

  bool get hasDayStackContent =>
      sleepDurationLabel != null ||
      recoveryTimeLabel != null ||
      caloriesLabel != null ||
      stepsLabel != null ||
      workoutTimeLabel != null ||
      bodyHrLabel != null ||
      todaySessions.isNotEmpty;

  /// Test / fixture helper that freezes precedence without inventing metrics
  /// for chrome-only states.
  factory HomeSnapshot.forPrecedence(
    HomePrecedence precedence, {
    String deviceLabel = 'GT5-A07',
    bool restDay = false,
  }) {
    return switch (precedence) {
      HomePrecedence.notPaired => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'No watch paired',
          syncPillLabel: 'Unpaired',
          syncTitle: 'Pair a GT5 to begin',
          syncCaption: 'Home stays empty until a watch is linked.',
        ),
      HomePrecedence.pairedNeverSynced => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · never synced',
          syncPillLabel: 'Waiting',
          syncTitle: '$deviceLabel paired',
          syncCaption: 'No sync yet · run first pass to load today.',
        ),
      HomePrecedence.syncInProgress => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · syncing…',
          syncPillLabel: 'Syncing',
          syncTitle: 'Pulling today’s data',
          syncCaption: 'Prior day kept · muted until pass finishes',
          sleepDurationLabel: '7h 12m',
          sleepWindowLabel: '23:18 → 06:30',
          recoveryTimeLabel: '14h',
          caloriesLabel: '1,842',
          stepsLabel: '7,420',
        ),
      HomePrecedence.syncFailed => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · sync failed',
          syncPillLabel: 'Failed',
          syncTitle: 'Couldn’t sync',
          syncCaption: 'Last good day kept · retry when ready',
          lastSyncedLabel: 'as of 09:14',
          recoveryTimeLabel: '9h',
          bodyHrLabel: '52 · 68 · 118',
        ),
      HomePrecedence.dataAvailable => restDay
          ? HomeSnapshot(
              precedence: precedence,
              deviceLabel: deviceLabel,
              brandSubtitle: 'GT5 · synced just now',
              syncPillLabel: 'Synced',
              syncTitle: '$deviceLabel connected',
              syncCaption: 'Sync healthy · rest day so far',
              sleepDurationLabel: '8h 04m',
              sleepWindowLabel: '22:50 → 06:54',
              recoveryTimeLabel: '0h',
              caloriesLabel: '920',
              stepsLabel: '3,110',
              workoutTimeLabel: '0m · no sessions',
              bodyHrLabel: '54 · 62 · 96',
              bodyHrSparkSamples: const [
                DailyHrSample(timestampUnix: 1, bpm: 54),
                DailyHrSample(timestampUnix: 2, bpm: 62),
                DailyHrSample(timestampUnix: 3, bpm: 96),
              ],
            )
          : HomeSnapshot(
              precedence: precedence,
              deviceLabel: deviceLabel,
              brandSubtitle: 'GT5 · synced 2m ago',
              syncPillLabel: 'Synced',
              syncTitle: '$deviceLabel connected',
              syncCaption: 'Auto-sync on open · last pass 2m ago',
              sleepDurationLabel: '7h 12m',
              sleepWindowLabel: '23:18 → 06:30',
              sleepFeelCue: 'OK — already answered',
              recoveryTimeLabel: '14h',
              caloriesLabel: '1,842',
              stepsLabel: '7,420',
              workoutTimeLabel: '1h 18m · 2 sessions',
              bodyHrLabel: '52 · 68 · 118',
              bodyHrSparkSamples: const [
                DailyHrSample(timestampUnix: 100, bpm: 60),
                DailyHrSample(timestampUnix: 200, bpm: 72),
                DailyHrSample(timestampUnix: 300, bpm: 90),
              ],
              todaySessions: [
                HomeTodaySessionCard(
                  workout: const WorkoutSummary(
                    number: 11,
                    startTime: 1,
                    endTime: 2,
                    durationSec: 2538,
                    type: 6,
                    distanceM: 1250,
                    load: 148,
                    aerobicEffect: 28,
                    recoveryTime: 960,
                  ),
                  title: 'Pool swim · #11',
                  whenLabel: '07:12 · 42:18 · 1,250 m',
                  meta: const [
                    (label: 'Load', value: '148'),
                    (label: 'TE', value: '2.8'),
                    (label: 'Recovery', value: '16h'),
                  ],
                ),
                HomeTodaySessionCard(
                  workout: const WorkoutSummary(
                    number: 24,
                    startTime: 3,
                    endTime: 4,
                    durationSec: 2165,
                    type: 140,
                    load: 92,
                    aerobicEffect: 3,
                    recoveryTime: 1320,
                  ),
                  title: 'Strength · #24',
                  whenLabel: '18:40 · 36:05',
                  meta: const [
                    (label: 'Load', value: '92'),
                    (label: 'Intensity', value: '3'),
                    (label: 'Recovery', value: '22h'),
                  ],
                ),
              ],
            ),
    };
  }
}
