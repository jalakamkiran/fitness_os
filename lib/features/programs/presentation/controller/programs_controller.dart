import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart' show WorkoutSummary;
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/baseline_resolver.dart';
import 'package:fitness_os/features/programs/domain/chore_matcher.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:fitness_os/features/programs/domain/scorecards.dart';
import 'package:fitness_os/features/programs/domain/soft_load_warn.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

/// Athlete-facing Programs state: active program, ledger, soft-warn, scorecards.
///
/// No Coach imports — works with Coach DI absent (AE6).
class ProgramsController extends ChangeNotifier {
  ProgramsController({
    required ProgramStore store,
    ProgramPlanner? planner,
    BaselineResolver? resolver,
    ChoreMatcher? matcher,
    SharedPreferences? prefs,
    WorkoutHistoryRepository? workoutHistory,
    DateTime Function()? now,
  })  : _store = store,
        _planner = planner ?? ProgramPlanner(),
        _resolver = resolver ?? BaselineResolver(),
        _matcher = matcher ?? ChoreMatcher(),
        _prefs = prefs,
        _workoutHistory = workoutHistory,
        _now = now ?? DateTime.now;

  final ProgramStore _store;
  final ProgramPlanner _planner;
  final BaselineResolver _resolver;
  final ChoreMatcher _matcher;
  final SharedPreferences? _prefs;
  final WorkoutHistoryRepository? _workoutHistory;
  final DateTime Function() _now;

  Program? _active;
  ProgressLedger _ledger = const ProgressLedger();
  SoftLoadWarnResult _softWarn = const SoftLoadWarnResult(
    warn: false,
    level: SoftLoadWarnLevel.none,
    copy: '',
  );
  ScorecardBundle? _scorecards;
  bool _loading = true;
  String? _error;
  String? _createHint;

  Program? get active => _active;
  ProgressLedger get ledger => _ledger;
  SoftLoadWarnResult get softWarn => _softWarn;
  ScorecardBundle? get scorecards => _scorecards;
  bool get loading => _loading;
  String? get error => _error;
  String? get createHint => _createHint;
  bool get hasActive =>
      _active != null && _active!.status == ProgramStatus.active;

  bool get hideGameLayer {
    if (_ledger.hideGameLayer) return true;
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.getBool(GateAPrefs.programsHideGameLayer) ?? false;
  }

  Milestone? get nextMilestone {
    final p = _active;
    if (p == null) return null;
    for (final m in p.milestones) {
      if (m.status == MilestoneStatus.upcoming ||
          m.status == MilestoneStatus.due ||
          m.status == MilestoneStatus.nearPass ||
          m.status == MilestoneStatus.failed ||
          m.status == MilestoneStatus.delayed) {
        return m;
      }
    }
    return p.milestones.isEmpty ? null : p.milestones.last;
  }

  ChoreSession? get todaysChore {
    final p = _active;
    if (p == null) return null;
    final today = _isoDay(_now());
    for (final c in p.chores) {
      if (c.dayIso == today && c.state != ChoreState.superseded) {
        return c;
      }
    }
    // Fall back to next open chore.
    for (final c in p.chores) {
      if (c.state == ChoreState.scheduled ||
          c.state == ChoreState.due ||
          c.state == ChoreState.lapsed) {
        return c;
      }
    }
    return null;
  }

  /// Resolve store from GetIt when registered; optional history for soft-warn.
  factory ProgramsController.fromGetIt(GetIt sl) {
    return ProgramsController(
      store: sl<ProgramStore>(),
      prefs: sl.isRegistered<SharedPreferences>()
          ? sl<SharedPreferences>()
          : null,
      workoutHistory: sl.isRegistered<WorkoutHistoryRepository>()
          ? sl<WorkoutHistoryRepository>()
          : null,
    );
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _active = await _store.loadActive();
      _ledger = await _store.loadLedger();
      await _refreshSoftWarn();
      _recomputeScorecards();
    } catch (e) {
      _error = 'Couldn’t load program.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Create + activate from intake. Uses history baseline when available;
  /// otherwise self-report path with [selfReportCapacityM].
  Future<bool> createAndActivate({
    required ProgramIntake intake,
    int? selfReportCapacityM,
    double? selfReportCssPaceSecPer100,
  }) async {
    if (!intake.poolOnlyAcknowledged) {
      _error = 'Confirm pool-only before starting.';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = null;
    _createHint = null;
    notifyListeners();

    try {
      Baseline baseline;
      final history = await _loadSwimsSafe();
      if (history != null && history.isNotEmpty) {
        baseline = _resolver.resolve(sessions: history, asOf: _now());
        if (baseline.guidedTestRequired ||
            baseline.confidence == BaselineConfidence.insufficient) {
          final capacity = selfReportCapacityM ??
              (baseline.capacityDistanceM > 0
                  ? baseline.capacityDistanceM
                  : intake.goalDistanceM ~/ 2);
          baseline = BaselineResolver.selfReport(
            capacityDistanceM: capacity.clamp(200, intake.goalDistanceM),
            cssPaceSecPer100:
                selfReportCssPaceSecPer100 ?? baseline.cssPaceSecPer100,
          );
          _createHint =
              'Thin pool history — used a self-reported starting distance.';
        }
      } else {
        final capacity =
            selfReportCapacityM ?? (intake.goalDistanceM * 0.8).round();
        baseline = BaselineResolver.selfReport(
          capacityDistanceM: capacity.clamp(200, intake.goalDistanceM),
          cssPaceSecPer100: selfReportCssPaceSecPer100,
        );
        _createHint =
            'No pool history yet — used a self-reported starting distance.';
      }

      final program = _planner.plan(
        intake: intake,
        baseline: baseline,
        startDate: _now(),
      );
      await _store.activate(program);

      var ledger = await _store.loadLedger();
      final atMs = _now().millisecondsSinceEpoch;
      ledger = ledger.appendXp(
        XpEvent(
          id: 'xp_baseline_$atMs',
          atMs: atMs,
          source: XpSource.baselineLocked,
          amount: XpTable.baselineLocked,
          programId: program.id,
        ),
      );
      await _store.saveLedger(ledger);

      _active = await _store.loadActive();
      _ledger = ledger;
      await _refreshSoftWarn();
      _recomputeScorecards();
      return true;
    } catch (_) {
      _error = 'Couldn’t build plan. Check your numbers and try again.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markChoreDone(String choreId) async {
    final program = _active;
    if (program == null) return;
    final idx = program.chores.indexWhere((c) => c.id == choreId);
    if (idx < 0) return;

    final updated = _matcher.applyManual(
      chore: program.chores[idx],
      action: ManualChoreAction.doneManual,
      asOf: _now(),
    );
    final chores = List<ChoreSession>.from(program.chores)..[idx] = updated;
    final next = program.copyWith(chores: chores);
    await _store.save(next);

    var ledger = _ledger;
    ledger = ProgressEngine.recordChoreCompletion(
      ledger,
      chore: updated,
      sessionsPerWeek: program.intake.sessionsPerWeek,
      asOf: _now(),
      structureMatched: updated.hasWuMainCd,
    );
    await _store.saveLedger(ledger);

    _active = next;
    _ledger = ledger;
    _recomputeScorecards();
    notifyListeners();
  }

  Future<void> skipChore(String choreId, SkipReason reason) async {
    final program = _active;
    if (program == null) return;
    final idx = program.chores.indexWhere((c) => c.id == choreId);
    if (idx < 0) return;

    final excused = reason == SkipReason.otherLoad ||
        reason == SkipReason.recovery ||
        reason == SkipReason.ill ||
        reason == SkipReason.poolClosed;
    final updated = _matcher.applyManual(
      chore: program.chores[idx],
      action: excused
          ? ManualChoreAction.skippedExcused
          : ManualChoreAction.skippedOther,
      skipReason: reason,
      asOf: _now(),
    );
    final chores = List<ChoreSession>.from(program.chores)..[idx] = updated;
    final next = program.copyWith(chores: chores);
    await _store.save(next);

    var ledger = _ledger;
    ledger = ProgressEngine.recordChoreCompletion(
      ledger,
      chore: updated,
      sessionsPerWeek: program.intake.sessionsPerWeek,
      asOf: _now(),
    );
    await _store.saveLedger(ledger);

    _active = next;
    _ledger = ledger;
    _recomputeScorecards();
    notifyListeners();
  }

  /// Apply a proof outcome; returns updated program (with slipped dates on fail).
  Future<Program?> applyProof({
    required String milestoneId,
    required ProofOutcome outcome,
    int? judgedDistanceM,
  }) async {
    final program = _active;
    if (program == null) return null;

    final slipped = _planner.applyProofOutcome(
      program,
      milestoneId: milestoneId,
      outcome: outcome,
      asOf: _now(),
    );
    await _store.save(slipped);

    var ledger = ProgressEngine.recordProofAttempt(
      _ledger,
      passed: outcome == ProofOutcome.pass,
      programId: program.id,
      milestoneId: milestoneId,
      asOf: _now(),
    );
    await _store.saveLedger(ledger);

    _active = slipped;
    _ledger = ledger;
    _recomputeScorecards();
    notifyListeners();
    return slipped;
  }

  ChoreSession? choreById(String id) {
    final p = _active;
    if (p == null) return null;
    for (final c in p.chores) {
      if (c.id == id) return c;
    }
    return null;
  }

  Milestone? milestoneById(String id) {
    final p = _active;
    if (p == null) return null;
    for (final m in p.milestones) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _refreshSoftWarn() async {
    final history = _workoutHistory;
    if (history == null) {
      _softWarn = const SoftLoadWarnResult(
        warn: false,
        level: SoftLoadWarnLevel.none,
        copy: '',
      );
      return;
    }
    try {
      final workouts = await history.loadLocal();
      final samples = workouts
          .where((w) => w.type != 6 && w.type != 8)
          .map(_toOtherLoad)
          .toList(growable: false);
      _softWarn = SoftLoadWarn.evaluate(
        recent: samples,
        day: _now(),
      );
    } catch (_) {
      _softWarn = const SoftLoadWarnResult(
        warn: false,
        level: SoftLoadWarnLevel.none,
        copy: '',
      );
    }
  }

  void _recomputeScorecards() {
    final p = _active;
    if (p == null) {
      _scorecards = null;
      return;
    }
    _scorecards = Scorecards.compute(program: p, ledger: _ledger);
  }

  Future<List<CanonicalSwimSession>?> _loadSwimsSafe() async {
    final history = _workoutHistory;
    if (history == null) return null;
    try {
      return await history.loadAllCanonicalSwims();
    } catch (_) {
      return null;
    }
  }

  static OtherLoadSample _toOtherLoad(WorkoutSummary w) {
    return OtherLoadSample(
      type: w.type,
      typeLabel: _typeLabel(w.type),
      startTimeMs: w.startTime * 1000,
      durationSec: w.durationSec,
      loadOrTe: w.load?.toDouble() ?? w.aerobicEffect?.toDouble(),
      hrPeak: w.hrPeak ?? w.hrMax,
    );
  }

  static String _typeLabel(int type) {
    const names = <int, String>{
      1: 'Walk',
      2: 'Run',
      3: 'Cycle',
      4: 'Climb',
      5: 'Indoor run',
      7: 'Indoor cycle',
      9: 'Elliptical',
      10: 'Rower',
      140: 'Strength',
    };
    return names[type] ?? 'Workout';
  }

  static String _isoDay(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
