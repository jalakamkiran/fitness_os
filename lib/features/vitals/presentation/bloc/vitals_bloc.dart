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
    StoreInvalidation? invalidation,
  })  : _repository = repository,
        super(const VitalsState()) {
    on<VitalsStarted>(_onStarted);
    on<VitalsSyncRequested>(_onSync);
    on<VitalsReloadRequested>(_onReload);
    if (invalidation != null) {
      _sub = invalidation.stream.listen((_) {
        add(const VitalsReloadRequested());
      });
    }
  }

  final VitalsRepository _repository;
  StreamSubscription<void>? _sub;

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

  Future<void> _reload(Emitter<VitalsState> emit) async {
    final passed = await _repository.isGateAPassed();
    var sleep = const <SleepSessionSummary>[];
    var hr = const <DailyHrDaySummary>[];
    String? loadError;
    try {
      sleep = await _repository.loadSleepSessions();
      hr = await _repository.loadDailyHr();
    } catch (_) {
      loadError = 'Local vitals unreadable';
    }
    emit(
      state.copyWith(
        gateAPassed: passed,
        sleepSessions: sleep,
        dailyHr: hr,
        phase: passed ? VitalsPhase.idle : VitalsPhase.blocked,
        message: loadError,
        clearMessage: loadError == null,
        everSynced: sleep.isNotEmpty || hr.isNotEmpty,
      ),
    );
  }

  Future<void> _onSync(
    VitalsSyncRequested event,
    Emitter<VitalsState> emit,
  ) async {
    if (state.phase == VitalsPhase.syncing) return;
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
        emit(
          state.copyWith(
            phase: stuck ? VitalsPhase.stuck : VitalsPhase.idle,
            message: busy
                ? 'Workout Sync in progress — try again when it finishes'
                : msg,
          ),
        );
      case Right(:final value):
        emit(
          state.copyWith(
            phase: value.partial ? VitalsPhase.stuck : VitalsPhase.idle,
            sleepSessions: value.sleepSessions,
            dailyHr: value.dailyHr,
            message: value.message ??
                (value.sleepSessions.isEmpty && value.dailyHr.isEmpty
                    ? 'No sleep or whole-day heart rate in range'
                    : 'Vitals updated'),
            partial: value.partial,
            enableSkipped: value.enableSkipped,
            everSynced: true,
          ),
        );
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
