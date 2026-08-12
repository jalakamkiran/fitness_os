import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/domain/repositories/home_repository.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

/// Huawei pool-swim activity type id (see workout history labels).
const int kPoolSwimType = 5;

/// Open-water swim type id.
const int kOpenWaterSwimType = 6;

/// When FT today reports 0 kcal but workouts burned more than this, treat the
/// FT row as untrusted (e.g. wrong day-anchor zeros) and use workout-sum.
const int _kFitnessTotalsUntrustedWorkoutCalThreshold = 10;

class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({
    required SharedPreferences prefs,
    required HuaweiLink link,
    required WorkoutHistoryRepository workouts,
    required VitalsRepository vitals,
    OneShotAutoSync? autoSync,
    DateTime Function()? now,
  })  : _prefs = prefs,
        _link = link,
        _workouts = workouts,
        _vitals = vitals,
        _autoSync = autoSync,
        _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final HuaweiLink _link;
  final WorkoutHistoryRepository _workouts;
  final VitalsRepository _vitals;
  final OneShotAutoSync? _autoSync;
  final DateTime Function() _now;

  @override
  Future<HomeSnapshot> loadSnapshot() async {
    final rememberedMac = _prefs.getString(GateAPrefs.rememberedMac);
    final rememberedName =
        _prefs.getString(GateAPrefs.rememberedName) ?? 'GT5';
    final gateA = _prefs.getBool(GateAPrefs.gateAPassed) ?? false;
    final isPaired = (rememberedMac != null && rememberedMac.isNotEmpty) ||
        gateA ||
        _link.state == LinkState.connected ||
        _link.state == LinkState.gateAIncomplete;

    final workouts = await _workouts.loadLocal();
    final hrDays = await _vitals.loadDailyHr();
    final fitnessTotals = await _vitals.loadFitnessTotals();
    final everSynced = _prefs.containsKey(GateAPrefs.lastSyncCursor) ||
        _prefs.containsKey(GateAPrefs.lastActivitySyncCursor) ||
        _prefs.containsKey(GateAPrefs.sleepSessionsJson) ||
        workouts.isNotEmpty ||
        hrDays.isNotEmpty ||
        fitnessTotals.isNotEmpty ||
        _prefs.getString(GateAPrefs.homeLastSyncStatus) == 'ok';

    final syncInProgress = _link.syncInFlight ||
        _vitals.isSyncOrMergeInFlight ||
        (_autoSync?.passInFlight ?? false);

    final syncFailed =
        _prefs.getString(GateAPrefs.homeLastSyncStatus) == 'failed';

    final today = _localDayKey(_now());
    final todayWorkouts = workouts.where((w) {
      if (w.startTime <= 0) return false;
      final dt =
          DateTime.fromMillisecondsSinceEpoch(w.startTime * 1000).toLocal();
      return _localDayKey(dt) == today;
    }).toList();

    final todaySwims = todayWorkouts
        .where((w) => w.type == kPoolSwimType || w.type == kOpenWaterSwimType)
        .toList();
    final latestSwim = todaySwims.isNotEmpty
        ? todaySwims.first
        : workouts
            .where(
                (w) => w.type == kPoolSwimType || w.type == kOpenWaterSwimType)
            .fold<WorkoutSummary?>(null, (best, w) {
            if (best == null || w.startTime > best.startTime) return w;
            return best;
          });

    final hasSwimTakeaway = latestSwim != null && todaySwims.isNotEmpty;

    final precedence = resolveHomePrecedence(
      HomePrecedenceInputs(
        isPaired: isPaired,
        everSynced: everSynced,
        syncInProgress: syncInProgress,
        syncFailed: syncFailed,
        hasSwimTakeaway: hasSwimTakeaway,
      ),
    );

    final lastSyncAt = _prefs.getInt(GateAPrefs.homeLastSyncAtMs);
    final lastSyncedLabel = lastSyncAt == null
        ? null
        : _relativeSyncLabel(
            DateTime.fromMillisecondsSinceEpoch(lastSyncAt),
            _now(),
          );

    final workoutCalories = todayWorkouts.fold<int>(
      0,
      (sum, w) => sum + (w.calories ?? 0),
    );
    final workoutSteps = todayWorkouts.fold<int>(
      0,
      (sum, w) => sum + (w.steps ?? 0),
    );
    final workoutSec = todayWorkouts.fold<int>(
      0,
      (sum, w) => sum + w.durationSec,
    );

    // Capture-locked: FT supplies day calories/steps; wire 0x07 is not exercise
    // minutes, so workout time stays on today's workout-sum until a duration
    // tag is owned. Sanity: FT cal=0 while workouts burned meaningfully →
    // untrusted (wrong day-anchor residue) → full workout-sum triple.
    FitnessTotalsDay? ftToday;
    for (final d in fitnessTotals) {
      if (d.dayKey == today) {
        ftToday = d;
        break;
      }
    }
    final int calories;
    final int steps;
    final int displayWorkoutSec;
    final ft = ftToday;
    if (ft != null &&
        !(ft.calories == 0 &&
            workoutCalories > _kFitnessTotalsUntrustedWorkoutCalThreshold)) {
      calories = ft.calories;
      steps = ft.steps;
      displayWorkoutSec = workoutSec;
    } else {
      calories = workoutCalories;
      steps = workoutSteps;
      displayWorkoutSec = workoutSec;
    }

    final hrToday = hrDays.where((d) => d.dayKey == today).toList();
    final hr = hrToday.isNotEmpty
        ? hrToday.first
        : (hrDays.isNotEmpty ? hrDays.first : null);
    final vitalsLabel = hr == null
        ? null
        : '${hr.minBpm} · ${hr.avgBpm} · ${hr.maxBpm}';

    String? takeawayTitle;
    String? takeawayBody;
    int? sessionNumber;
    if (hasSwimTakeaway && latestSwim != null) {
      final swim = latestSwim;
      sessionNumber = swim.number;
      final km = swim.distanceM == null
          ? null
          : (swim.distanceM! / 1000).toStringAsFixed(1);
      takeawayTitle = km != null
          ? 'Pool swim · $km km'
          : 'Pool swim · #${swim.number}';
      takeawayBody =
          '${_formatDuration(swim.durationSec)} · open session for signals';
    } else if (precedence == HomePrecedence.noSwimDataYet) {
      takeawayTitle = 'No swim yet today';
      takeawayBody =
          'When you finish a pool session, the takeaway lands here — one line, not a chart.';
    }

    final sessionReady = _link.sessionReady;

    return HomeSnapshot(
      precedence: precedence,
      deviceLabel: rememberedName,
      brandSubtitle: _brandSubtitle(
        precedence: precedence,
        deviceLabel: rememberedName,
        lastSyncedLabel: lastSyncedLabel,
      ),
      syncPillLabel: _pillLabel(precedence),
      syncTitle: _syncTitle(
        precedence,
        rememberedName,
        sessionReady: sessionReady,
      ),
      syncCaption: _syncCaption(
        precedence,
        lastSyncedLabel,
        sessionReady: sessionReady,
      ),
      lastSyncedLabel: lastSyncedLabel,
      caloriesLabel: everSynced &&
              precedence != HomePrecedence.pairedNeverSynced &&
              precedence != HomePrecedence.notPaired
          ? _formatInt(calories)
          : null,
      stepsLabel: everSynced &&
              precedence != HomePrecedence.pairedNeverSynced &&
              precedence != HomePrecedence.notPaired
          ? _formatInt(steps)
          : null,
      workoutTimeLabel: precedence == HomePrecedence.noSwimDataYet ||
              precedence == HomePrecedence.dataAvailable
          ? '${displayWorkoutSec ~/ 60}m'
          : null,
      vitalsSnapshotLabel: vitalsLabel,
      swimTakeawayTitle: takeawayTitle,
      swimTakeawayBody: takeawayBody,
      swimSessionNumber: sessionNumber,
    );
  }

  @override
  Future<bool> syncNow() async {
    final pass = SentrySyncInstrumentation.startPassTransaction(
      trigger: 'manual',
    );
    try {
      final workoutResult = await _workouts.syncFromWatch();
      final vitalsResult = await _vitals.syncFromWatch();
      final ok = workoutResult.isRight && vitalsResult.isRight;
      await _prefs.setString(
        GateAPrefs.homeLastSyncStatus,
        ok ? 'ok' : 'failed',
      );
      if (ok) {
        await _prefs.setInt(
          GateAPrefs.homeLastSyncAtMs,
          _now().millisecondsSinceEpoch,
        );
      }
      await SentrySyncInstrumentation.finishWithStatus(
        pass,
        status: ok ? 'ok' : 'error',
      );
      return ok;
    } catch (_) {
      await SentrySyncInstrumentation.finishWithStatus(
        pass,
        status: 'error',
      );
      rethrow;
    }
  }
}

String _localDayKey(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}

String _formatInt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _formatDuration(int sec) {
  if (sec <= 0) return '—';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String _relativeSyncLabel(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return 'as of ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

String _pillLabel(HomePrecedence p) => switch (p) {
      HomePrecedence.notPaired => 'Unpaired',
      HomePrecedence.pairedNeverSynced => 'Waiting',
      HomePrecedence.syncInProgress => 'Syncing',
      HomePrecedence.syncFailed => 'Failed',
      HomePrecedence.dataAvailable ||
      HomePrecedence.noSwimDataYet =>
        'Synced',
    };

String _brandSubtitle({
  required HomePrecedence precedence,
  required String deviceLabel,
  required String? lastSyncedLabel,
}) =>
    switch (precedence) {
      HomePrecedence.notPaired => 'No watch paired',
      HomePrecedence.pairedNeverSynced => 'GT5 · never synced',
      HomePrecedence.syncInProgress => 'GT5 · syncing…',
      HomePrecedence.syncFailed => 'GT5 · sync failed',
      HomePrecedence.dataAvailable ||
      HomePrecedence.noSwimDataYet =>
        'GT5 · synced ${lastSyncedLabel ?? 'just now'}',
    };

String _syncTitle(
  HomePrecedence p,
  String device, {
  required bool sessionReady,
}) =>
    switch (p) {
      HomePrecedence.notPaired => 'Pair a GT5 to begin',
      HomePrecedence.pairedNeverSynced => '$device paired',
      HomePrecedence.syncInProgress => 'Pulling today’s data',
      HomePrecedence.syncFailed => 'Couldn’t sync',
      HomePrecedence.dataAvailable ||
      HomePrecedence.noSwimDataYet =>
        sessionReady ? '$device connected' : '$device paired',
    };

String _syncCaption(
  HomePrecedence p,
  String? lastSynced, {
  required bool sessionReady,
}) =>
    switch (p) {
      HomePrecedence.notPaired => 'Home stays empty until a watch is linked.',
      HomePrecedence.pairedNeverSynced =>
        'No sync yet · run first pass to load today.',
      HomePrecedence.syncInProgress => 'One-shot pass on open · keep UI calm.',
      HomePrecedence.syncFailed =>
        'Last good data kept when available · retry when ready.',
      HomePrecedence.dataAvailable => sessionReady
          ? 'Auto-sync on open · last pass ${lastSynced ?? 'recently'}'
          : 'Session offline · last pass ${lastSynced ?? 'recently'}',
      HomePrecedence.noSwimDataYet => sessionReady
          ? 'Sync healthy · no swim session today'
          : 'Session offline · last sync kept · no swim session today',
    };
