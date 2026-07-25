/// Frozen Home state precedence (plan U3 / design home-states.html).
///
/// Deterministic hierarchy — evaluate in this order only:
/// 1. [notPaired]
/// 2. [syncInProgress]
/// 3. [pairedNeverSynced]
/// 4. [syncFailed]
/// 5. [dataAvailable]
/// 6. [noSwimDataYet]
enum HomePrecedence {
  notPaired,
  pairedNeverSynced,
  syncInProgress,
  syncFailed,
  dataAvailable,
  noSwimDataYet,
}

/// Inputs for [resolveHomePrecedence]. Keep this surface stable for tests.
class HomePrecedenceInputs {
  const HomePrecedenceInputs({
    required this.isPaired,
    required this.everSynced,
    required this.syncInProgress,
    required this.syncFailed,
    required this.hasSwimTakeaway,
  });

  final bool isPaired;
  final bool everSynced;
  final bool syncInProgress;
  final bool syncFailed;

  /// True when a swim takeaway line is available (today or latest).
  final bool hasSwimTakeaway;
}

/// Pure precedence resolver — single source of truth for Home UI branching.
HomePrecedence resolveHomePrecedence(HomePrecedenceInputs inputs) {
  if (!inputs.isPaired) return HomePrecedence.notPaired;
  if (inputs.syncInProgress) return HomePrecedence.syncInProgress;
  if (!inputs.everSynced) return HomePrecedence.pairedNeverSynced;
  if (inputs.syncFailed) return HomePrecedence.syncFailed;
  if (inputs.hasSwimTakeaway) return HomePrecedence.dataAvailable;
  return HomePrecedence.noSwimDataYet;
}

/// Calm “now” snapshot for Home (Today-only; never charts / history / reasoner).
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
    this.vitalsSnapshotLabel,
    this.swimTakeawayTitle,
    this.swimTakeawayBody,
    this.swimSessionNumber,
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
  final String? vitalsSnapshotLabel;
  final String? swimTakeawayTitle;
  final String? swimTakeawayBody;
  final int? swimSessionNumber;

  /// Test / fixture helper that freezes precedence without inventing metrics.
  factory HomeSnapshot.forPrecedence(
    HomePrecedence precedence, {
    String deviceLabel = 'GT5-A07',
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
          syncCaption: 'One-shot pass on open · keep UI calm.',
        ),
      HomePrecedence.syncFailed => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · sync failed',
          syncPillLabel: 'Failed',
          syncTitle: 'Couldn’t sync',
          syncCaption:
              'Last good data kept when available · retry when ready.',
          lastSyncedLabel: 'as of earlier',
        ),
      HomePrecedence.dataAvailable => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · synced 2m ago',
          syncPillLabel: 'Synced',
          syncTitle: '$deviceLabel connected',
          syncCaption: 'Auto-sync on open · last pass 2m ago',
          caloriesLabel: '1,842',
          stepsLabel: '7,420',
          vitalsSnapshotLabel: '58 · 72 · 97%',
          swimTakeawayTitle: 'Efficient early, fatigue later',
          swimTakeawayBody: 'Shorten sets before adding volume.',
          swimSessionNumber: 11,
        ),
      HomePrecedence.noSwimDataYet => HomeSnapshot(
          precedence: precedence,
          deviceLabel: deviceLabel,
          brandSubtitle: 'GT5 · synced just now',
          syncPillLabel: 'Synced',
          syncTitle: '$deviceLabel connected',
          syncCaption: 'Sync healthy · no swim session today',
          caloriesLabel: '920',
          stepsLabel: '3,110',
          workoutTimeLabel: '0m · no sessions',
          vitalsSnapshotLabel: '61 · — · 98%',
          swimTakeawayTitle: 'No swim yet today',
          swimTakeawayBody:
              'When you finish a pool session, the takeaway lands here — one line, not a chart.',
        ),
    };
  }
}
