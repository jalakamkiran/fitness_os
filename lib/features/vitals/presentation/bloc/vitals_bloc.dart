import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';

class VitalsBloc extends Bloc<VitalsEvent, VitalsState> {
  VitalsBloc({
    required VitalsRepository repository,
    HuaweiLink? link,
    StoreInvalidation? invalidation,
  })  : _repository = repository,
        _link = link,
        super(const VitalsState()) {
    on<VitalsStarted>(_onStarted);
    on<VitalsSyncRequested>(_onSync);
    on<VitalsEnableRequested>(_onEnable);
    on<VitalsReloadRequested>(_onReload);
    on<VitalsSessionReadyChanged>(_onSessionReady);
    if (invalidation != null) {
      _sub = invalidation.stream.listen((_) {
        add(const VitalsReloadRequested());
      });
    }
    final link = _link;
    if (link != null) {
      _linkSub = link.events.listen((event) {
        if (event is LinkStateChanged) {
          add(VitalsSessionReadyChanged(link.sessionReady));
        }
      });
    }
  }

  final VitalsRepository _repository;
  final HuaweiLink? _link;
  StreamSubscription<void>? _sub;
  StreamSubscription<HuaweiLinkEvent>? _linkSub;

  Future<void> _onStarted(
    VitalsStarted event,
    Emitter<VitalsState> emit,
  ) async {
    await _reload(emit);
  }

  Future<void> _onReload(
    VitalsReloadRequested event,
    Emitter<VitalsState> emit,
  ) async {
    await _reload(emit);
  }

  void _onSessionReady(
    VitalsSessionReadyChanged event,
    Emitter<VitalsState> emit,
  ) {
    emit(state.copyWith(sessionReady: event.sessionReady));
  }

  Future<void> _reload(Emitter<VitalsState> emit) async {
    final passed = await _repository.isGateAPassed();
    final sessionReady = _repository.sessionReady;
    var sleep = const <SleepSessionSummary>[];
    var hr = const <DailyHrDaySummary>[];
    var hrSeries = const <DailyHrSample>[];
    String? loadError;
    try {
      sleep = await _repository.loadSleepSessions();
      hr = await _repository.loadDailyHr();
      if (hr.isNotEmpty) {
        hrSeries = await _repository.loadDailyHrSeries(hr.first.dayKey);
      }
    } catch (_) {
      loadError = 'Local vitals unreadable';
    }
    final lastEnable = await _repository.loadLastEnable();
    emit(
      state.copyWith(
        gateAPassed: passed,
        sessionReady: sessionReady,
        sleepSessions: sleep,
        dailyHr: hr,
        latestHrSeries: hrSeries,
        phase: passed ? VitalsPhase.idle : VitalsPhase.blocked,
        message: loadError,
        clearMessage: loadError == null,
        everSynced: sleep.isNotEmpty || hr.isNotEmpty,
        lastEnable: lastEnable,
        clearLastEnable: lastEnable == null,
        clearEnableNextStep: true,
      ),
    );
  }

  Future<void> _onSync(
    VitalsSyncRequested event,
    Emitter<VitalsState> emit,
  ) async {
    if (state.phase == VitalsPhase.syncing ||
        state.phase == VitalsPhase.enabling) {
      return;
    }
    if (!await _repository.isGateAPassed()) {
      emit(
        state.copyWith(
          phase: VitalsPhase.blocked,
          message: 'Gate A unlock required before Sync',
        ),
      );
      return;
    }
    emit(state.copyWith(phase: VitalsPhase.syncing, clearMessage: true));
    final result = await _repository.syncFromWatch();
    switch (result) {
      case Left(:final value):
        final msg = value.message;
        final stuck = msg.toLowerCase().contains('stuck');
        final busy = msg.toLowerCase().contains('another sync');
        final enableBusy = msg.toLowerCase().contains('enable');
        emit(
          state.copyWith(
            phase: stuck ? VitalsPhase.stuck : VitalsPhase.idle,
            message: busy
                ? (enableBusy
                    ? 'Wait for enable to finish, then Sync'
                    : 'Workout Sync in progress — try again when it finishes')
                : msg,
          ),
        );
      case Right(:final value):
        var hrSeries = const <DailyHrSample>[];
        if (value.dailyHr.isNotEmpty) {
          hrSeries =
              await _repository.loadDailyHrSeries(value.dailyHr.first.dayKey);
        }
        emit(
          state.copyWith(
            phase: value.partial ? VitalsPhase.stuck : VitalsPhase.idle,
            sleepSessions: value.sleepSessions,
            dailyHr: value.dailyHr,
            latestHrSeries: hrSeries,
            message: value.message ??
                (value.sleepSessions.isEmpty && value.dailyHr.isEmpty
                    ? 'No sleep data in range'
                    : 'Vitals updated'),
            partial: value.partial,
            enableSkipped: value.enableSkipped,
            everSynced: true,
          ),
        );
    }
  }

  Future<void> _onEnable(
    VitalsEnableRequested event,
    Emitter<VitalsState> emit,
  ) async {
    if (state.enableDisabled) return;
    if (!await _repository.isGateAPassed()) {
      emit(
        state.copyWith(
          phase: VitalsPhase.blocked,
          message: 'Gate A unlock required before Enable',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        phase: VitalsPhase.enabling,
        clearMessage: true,
        clearEnableNextStep: true,
      ),
    );
    final result = await _repository.enableAutoTracking();
    switch (result) {
      case Left(:final value):
        final msg = value.message;
        final busy = msg.toLowerCase().contains('another sync');
        emit(
          state.copyWith(
            phase: VitalsPhase.idle,
            message: busy
                ? 'Sync in progress — try Enable when it finishes'
                : msg,
          ),
        );
      case Right(:final value):
        emit(
          state.copyWith(
            phase: VitalsPhase.idle,
            lastEnable: value,
            message: _overallCopy(value),
            enableNextStep:
                'Auto-HR is armed on the watch. Sync refreshes sleep only — '
                'it does not refill whole-day HR.',
          ),
        );
    }
  }

  String _overallCopy(AutoTrackingEnableResult value) {
    return switch (value.overall) {
      AutoTrackingOverall.allArmed => 'Last enable: all armed',
      AutoTrackingOverall.partial => 'Last enable: partial — tap to retry',
      AutoTrackingOverall.noneArmed => 'Last enable: none armed — tap to retry',
    };
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _linkSub?.cancel();
    return super.close();
  }
}
