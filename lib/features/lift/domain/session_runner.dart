import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/reply_parser.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';

enum LiftCaptureMode { reply, ackOnly }

enum LiftRunnerPhase {
  idle,
  notifying,
  awaitingReply,
  resting,
  done,
  paused,
}

class LiftRunnerState {
  const LiftRunnerState({
    required this.phase,
    this.currentIndex = 0,
    this.nextNotifyAtMs,
    this.resendCount = 0,
    this.paused = false,
  });

  final LiftRunnerPhase phase;
  final int currentIndex;
  final int? nextNotifyAtMs;
  final int resendCount;
  final bool paused;

  LiftRunnerState copyWith({
    LiftRunnerPhase? phase,
    int? currentIndex,
    int? nextNotifyAtMs,
    int? resendCount,
    bool? paused,
  }) =>
      LiftRunnerState(
        phase: phase ?? this.phase,
        currentIndex: currentIndex ?? this.currentIndex,
        nextNotifyAtMs: nextNotifyAtMs ?? this.nextNotifyAtMs,
        resendCount: resendCount ?? this.resendCount,
        paused: paused ?? this.paused,
      );
}

typedef Clock = int Function();

class SessionRunner {
  SessionRunner({
    required this.session,
    required this.plannedSets,
    this.captureMode = LiftCaptureMode.reply,
    Clock? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PlannedSession session;
  final List<PlannedSet> plannedSets;
  final LiftCaptureMode captureMode;
  final Clock _clock;

  LiftRunnerState state = const LiftRunnerState(phase: LiftRunnerPhase.idle);
  final Map<String, int> _lastReplyAtByKey = {};

  PlannedSet? get currentSet {
    if (state.currentIndex < 0 || state.currentIndex >= plannedSets.length) {
      return null;
    }
    return plannedSets[state.currentIndex];
  }

  void start() {
    if (plannedSets.isEmpty) {
      state = const LiftRunnerState(phase: LiftRunnerPhase.done);
      return;
    }
    state = const LiftRunnerState(
      phase: LiftRunnerPhase.notifying,
      currentIndex: 0,
    );
  }

  void onNotified(int notifiedAtMs) {
    state = state.copyWith(
      phase: LiftRunnerPhase.awaitingReply,
      resendCount: 0,
    );
  }

  /// Returns a [StrengthSet] when reply produces data, or null if ignored.
  StrengthSet? onReply({
    required String key,
    required String text,
    required int rxAtMs,
  }) {
    final idx = _indexForKey(key);
    if (idx == null) return null;

    final duplicateWindow = _lastReplyAtByKey[key];
    if (duplicateWindow != null && (rxAtMs - duplicateWindow).abs() < 5000) {
      return null;
    }

    final current = currentSet;
    if (current != null && key == current.notificationKey(session.sessionId)) {
      _lastReplyAtByKey[key] = rxAtMs;
      final plan = plannedSets[idx];
      final outcome = parseReply(text, plan);
      final record = _buildSet(plan, outcome, rxAtMs, 'watch_reply', text: text);
      _advanceAfterReply(rxAtMs, plan.restSec);
      return record;
    }

    final now = _clock();
    if (idx < state.currentIndex && (now - rxAtMs) < 10 * 60 * 1000) {
      _lastReplyAtByKey[key] = rxAtMs;
      final plan = plannedSets[idx];
      final outcome = parseReply(text, plan);
      return _buildSet(plan, outcome, rxAtMs, 'watch_reply', text: text);
    }
    return null;
  }

  StrengthSet? onAckFrame({required int rxAtMs}) {
    if (captureMode != LiftCaptureMode.ackOnly) return null;
    final plan = currentSet;
    if (plan == null) return null;
    final record = _buildSet(
      plan,
      ReplyOutcome(
        actualKg: plan.plannedKg,
        actualReps: plan.plannedReps,
        failed: false,
        unknownReply: false,
      ),
      rxAtMs,
      'watch_ack',
    );
    _advanceAfterReply(rxAtMs, plan.restSec);
    return record;
  }

  LiftRunnerState tick() {
    final now = _clock();
    if (state.phase == LiftRunnerPhase.awaitingReply) {
      final waited = now - (state.nextNotifyAtMs ?? now);
      if (waited > 15 * 60 * 1000) {
        if (state.resendCount < 2) {
          state = state.copyWith(
            phase: LiftRunnerPhase.notifying,
            resendCount: state.resendCount + 1,
          );
        } else {
          state = state.copyWith(phase: LiftRunnerPhase.paused, paused: true);
        }
      }
    } else if (state.phase == LiftRunnerPhase.resting &&
        state.nextNotifyAtMs != null &&
        now >= state.nextNotifyAtMs!) {
      final nextIdx = state.currentIndex + 1;
      if (nextIdx >= plannedSets.length) {
        state = const LiftRunnerState(phase: LiftRunnerPhase.done);
      } else {
        state = LiftRunnerState(
          phase: LiftRunnerPhase.notifying,
          currentIndex: nextIdx,
        );
      }
    }
    return state;
  }

  void skipCurrent() {
    if (currentSet == null) return;
    _advanceIndex();
  }

  void pause() => state = state.copyWith(phase: LiftRunnerPhase.paused, paused: true);

  void end() => state = const LiftRunnerState(phase: LiftRunnerPhase.done);

  int? _indexForKey(String key) {
    final parts = key.split(':');
    if (parts.length < 3) return null;
    final global = int.tryParse(parts.last);
    if (global == null) return null;
    final idx = plannedSets.indexWhere((p) => p.globalIndex == global);
    if (idx < 0) return null;
    return idx;
  }

  StrengthSet _buildSet(
    PlannedSet plan,
    ReplyOutcome outcome,
    int loggedAtMs,
    String source, {
    String? text,
  }) =>
      StrengthSet(
        id: StrengthSet.idFor(
          sessionId: session.sessionId,
          exerciseId: plan.exerciseId,
          setIndex: plan.setIndex,
        ),
        sessionId: session.sessionId,
        exerciseId: plan.exerciseId,
        exercise: plan.name,
        setIndex: plan.setIndex,
        plannedKg: plan.plannedKg,
        plannedReps: plan.plannedReps,
        actualKg: outcome.actualKg,
        actualReps: outcome.actualReps,
        failed: outcome.failed,
        replyText: text,
        unknownReply: outcome.unknownReply,
        notifiedAtMs: loggedAtMs,
        loggedAtMs: loggedAtMs,
        source: source,
      );

  void _advanceAfterReply(int rxAtMs, int restSec) {
    if (state.currentIndex >= plannedSets.length - 1) {
      state = const LiftRunnerState(phase: LiftRunnerPhase.done);
      return;
    }
    state = LiftRunnerState(
      phase: LiftRunnerPhase.resting,
      currentIndex: state.currentIndex,
      nextNotifyAtMs: rxAtMs + restSec * 1000,
    );
  }

  void _advanceIndex() {
    if (state.currentIndex >= plannedSets.length - 1) {
      state = const LiftRunnerState(phase: LiftRunnerPhase.done);
    } else {
      state = LiftRunnerState(
        phase: LiftRunnerPhase.notifying,
        currentIndex: state.currentIndex + 1,
      );
    }
  }
}