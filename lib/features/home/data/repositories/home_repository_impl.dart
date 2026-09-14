import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/domain/repositories/home_repository.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

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
    final sleepSessions = await _vitals.loadSleepSessions();
    final everSynced = _prefs.containsKey(GateAPrefs.lastSyncCursor) ||
        _prefs.containsKey(GateAPrefs.lastActivitySyncCursor) ||
        _prefs.containsKey(GateAPrefs.sleepSessionsJson) ||
        workouts.isNotEmpty ||
        hrDays.isNotEmpty ||
        fitnessTotals.isNotEmpty ||
        sleepSessions.isNotEmpty ||
        _prefs.getString(GateAPrefs.homeLastSyncStatus) == 'ok';

    final syncInProgress = _link.syncInFlight ||
        _vitals.isSyncOrMergeInFlight ||
        (_autoSync?.passInFlight ?? false);

    final syncFailed =
        _prefs.getString(GateAPrefs.homeLastSyncStatus) == 'failed';

    final now = _now();
    final today = _localDayKey(now);
    final todayWorkouts = workouts.where((w) {
      if (w.startTime <= 0) return false;
      final dt =
          DateTime.fromMillisecondsSinceEpoch(w.startTime * 1000).toLocal();
      return _localDayKey(dt) == today;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final precedence = resolveHomePrecedence(
      HomePrecedenceInputs(
        isPaired: isPaired,
        everSynced: everSynced,
        syncInProgress: syncInProgress,
        syncFailed: syncFailed,
      ),
    );

    final lastSyncAt = _prefs.getInt(GateAPrefs.homeLastSyncAtMs);
    final lastSyncedLabel = lastSyncAt == null
        ? null
        : _relativeSyncLabel(
            DateTime.fromMillisecondsSinceEpoch(lastSyncAt),
            now,
          );

    final chromeOnly = precedence == HomePrecedence.notPaired ||
        precedence == HomePrecedence.pairedNeverSynced;

    // Sleep strip
    String? sleepDurationLabel;
    String? sleepWindowLabel;
    String? sleepFeelCue;
    if (!chromeOnly) {
      final sleep = todaysSleepSession(sleepSessions, now: now);
      if (sleep != null && sleep.endUnix > sleep.beginUnix) {
        final durSec = sleep.endUnix - sleep.beginUnix;
        sleepDurationLabel = sleepFormatDuration(durSec);
        sleepWindowLabel = sleepFormatWindow(sleep.beginUnix, sleep.endUnix);
        final feel = await _vitals.loadFeelOnWake(sleep);
        if (feel != null && feel.trim().isNotEmpty) {
          sleepFeelCue = feel.trim();
        }
      }
    }

    // Totals
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

    String? caloriesLabel;
    String? stepsLabel;
    String? workoutTimeLabel;
    if (everSynced && !chromeOnly) {
      caloriesLabel = _formatInt(calories);
      stepsLabel = _formatInt(steps);
      final mins = displayWorkoutSec ~/ 60;
      final sessionCount = todayWorkouts.length;
      if (sessionCount == 0) {
        workoutTimeLabel = '${mins}m · no sessions';
      } else if (mins >= 60) {
        final h = mins ~/ 60;
        final m = mins % 60;
        final time = m > 0 ? '${h}h ${m}m' : '${h}h';
        workoutTimeLabel =
            '$time · $sessionCount session${sessionCount == 1 ? '' : 's'}';
      } else {
        workoutTimeLabel =
            '${mins}m · $sessionCount session${sessionCount == 1 ? '' : 's'}';
      }
    }

    // Body HR — today dayKey only (no non-today fallback).
    String? bodyHrLabel;
    List<DailyHrSample> sparkSamples = const [];
    if (!chromeOnly) {
      final hrToday = hrDays.where((d) => d.dayKey == today).toList();
      if (hrToday.isNotEmpty) {
        final hr = hrToday.first;
        bodyHrLabel = '${hr.minBpm} · ${hr.avgBpm} · ${hr.maxBpm}';
        final series = await _vitals.loadDailyHrSeries(today);
        if (series.length >= 2) {
          sparkSamples = series;
        }
      }
    }

    final todaySessions = chromeOnly
        ? const <HomeTodaySessionCard>[]
        : todayWorkouts.map(buildHomeTodaySessionCard).toList();

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
        sessionCount: todaySessions.length,
      ),
      syncCaption: _syncCaption(
        precedence,
        lastSyncedLabel,
        sessionReady: sessionReady,
        sessionCount: todaySessions.length,
      ),
      lastSyncedLabel: lastSyncedLabel,
      caloriesLabel: caloriesLabel,
      stepsLabel: stepsLabel,
      workoutTimeLabel: workoutTimeLabel,
      sleepDurationLabel: sleepDurationLabel,
      sleepWindowLabel: sleepWindowLabel,
      sleepFeelCue: sleepFeelCue,
      bodyHrLabel: bodyHrLabel,
      bodyHrSparkSamples: sparkSamples,
      todaySessions: todaySessions,
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

/// Maps a [WorkoutSummary] to Home session-card fields (omit absent load/TE/rec).
HomeTodaySessionCard buildHomeTodaySessionCard(WorkoutSummary w) {
  final title = workoutSessionTitle(w);
  final whenParts = <String>[];
  if (w.startTime > 0) {
    final dt = DateTime.fromMillisecondsSinceEpoch(w.startTime * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    whenParts.add('${two(dt.hour)}:${two(dt.minute)}');
  }
  final clock = formatDurationClock(w.durationSec);
  if (clock != '—') whenParts.add(clock);
  if (isSwimWorkout(w.type) && w.distanceM != null && w.distanceM! > 0) {
    whenParts.add(formatDistanceM(w.distanceM));
  } else if (isRunWorkout(w.type)) {
    final km = formatDistanceKm(w.distanceM);
    if (km != null) whenParts.add(km);
  }

  final meta = <({String label, String value})>[];
  if (w.load != null) {
    meta.add((label: 'Load', value: '${w.load}'));
  }

  if (isStrengthWorkout(w.type)) {
    if (w.aerobicEffect != null) {
      meta.add((label: 'Intensity', value: '${w.aerobicEffect}'));
    }
    final recovery = formatRecoveryMinutes(w.recoveryTime);
    if (recovery != null) {
      meta.add((label: 'Recovery', value: recovery));
    }
  } else if (isRunWorkout(w.type)) {
    if (w.aerobicEffect != null) {
      meta.add((
        label: 'TE',
        value: (w.aerobicEffect! / 10.0).toStringAsFixed(1),
      ));
    }
    final recovery = formatRecoveryMinutes(w.recoveryTime);
    if (recovery != null) {
      meta.add((label: 'Recovery', value: recovery));
    }
  } else {
    // Swim and other sports — TE ÷10 when present (GT5 scaled int).
    if (w.aerobicEffect != null) {
      meta.add((
        label: 'TE',
        value: (w.aerobicEffect! / 10.0).toStringAsFixed(1),
      ));
    }
    final recovery = formatRecoveryMinutes(w.recoveryTime);
    if (recovery != null) {
      meta.add((label: 'Recovery', value: recovery));
    }
  }

  return HomeTodaySessionCard(
    workout: w,
    title: title,
    whenLabel: whenParts.join(' · '),
    meta: meta,
  );
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
      HomePrecedence.dataAvailable => 'Synced',
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
      HomePrecedence.dataAvailable =>
        'GT5 · synced ${lastSyncedLabel ?? 'just now'}',
    };

String _syncTitle(
  HomePrecedence p,
  String device, {
  required bool sessionReady,
  required int sessionCount,
}) =>
    switch (p) {
      HomePrecedence.notPaired => 'Pair a GT5 to begin',
      HomePrecedence.pairedNeverSynced => '$device paired',
      HomePrecedence.syncInProgress => 'Pulling today’s data',
      HomePrecedence.syncFailed => 'Couldn’t sync',
      HomePrecedence.dataAvailable =>
        sessionReady ? '$device connected' : '$device paired',
    };

String _syncCaption(
  HomePrecedence p,
  String? lastSynced, {
  required bool sessionReady,
  required int sessionCount,
}) =>
    switch (p) {
      HomePrecedence.notPaired => 'Home stays empty until a watch is linked.',
      HomePrecedence.pairedNeverSynced =>
        'No sync yet · run first pass to load today.',
      HomePrecedence.syncInProgress =>
        'Prior day kept · muted until pass finishes',
      HomePrecedence.syncFailed =>
        'Last good day kept · retry when ready',
      HomePrecedence.dataAvailable => sessionReady
          ? (sessionCount == 0
              ? 'Sync healthy · rest day so far'
              : 'Auto-sync on open · last pass ${lastSynced ?? 'recently'}')
          : 'Session offline · last pass ${lastSynced ?? 'recently'}',
    };
