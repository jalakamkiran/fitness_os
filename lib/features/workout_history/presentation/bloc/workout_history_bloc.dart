import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/workout_history/domain/huawei_workout_types.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';

class WorkoutHistoryBloc
    extends Bloc<WorkoutHistoryEvent, WorkoutHistoryState> {
  WorkoutHistoryBloc({
    required WorkoutHistoryRepository repository,
    StoreInvalidation? invalidation,
  })  : _repository = repository,
        super(const WorkoutHistoryState()) {
    on<WorkoutHistoryStarted>(_onStarted);
    on<WorkoutHistorySyncRequested>(_onSync);
    on<WorkoutHistoryReloadRequested>(_onReload);
    if (invalidation != null) {
      _sub = invalidation.stream.listen((_) {
        if (!isClosed) add(const WorkoutHistoryReloadRequested());
      });
    }
  }

  final WorkoutHistoryRepository _repository;
  StreamSubscription<void>? _sub;

  Future<void> _onStarted(
    WorkoutHistoryStarted event,
    Emitter<WorkoutHistoryState> emit,
  ) async {
    await _reload(emit);
  }

  Future<void> _onReload(
    WorkoutHistoryReloadRequested event,
    Emitter<WorkoutHistoryState> emit,
  ) async {
    await _reload(emit);
  }

  Future<void> _reload(Emitter<WorkoutHistoryState> emit) async {
    final passed = await _repository.isGateAPassed();
    final local = await _repository.loadLocal();
    emit(
      state.copyWith(
        gateAPassed: passed,
        workouts: local,
        phase: passed ? WorkoutHistoryPhase.idle : WorkoutHistoryPhase.blocked,
        clearMessage: true,
      ),
    );
  }

  Future<void> _onSync(
    WorkoutHistorySyncRequested event,
    Emitter<WorkoutHistoryState> emit,
  ) async {
    if (!await _repository.isGateAPassed()) {
      emit(
        state.copyWith(
          phase: WorkoutHistoryPhase.blocked,
          message: 'Gate A unlock required before Sync',
        ),
      );
      return;
    }
    emit(state.copyWith(phase: WorkoutHistoryPhase.syncing, clearMessage: true));
    final result = await _repository.syncFromWatch(
      forceFullHistory: event.forceFullHistory,
    );
    switch (result) {
      case Left(:final value):
        final stuck = value.message.toLowerCase().contains('stuck');
        emit(
          state.copyWith(
            phase: stuck ? WorkoutHistoryPhase.stuck : WorkoutHistoryPhase.idle,
            message: value.message,
          ),
        );
      case Right(:final value):
        // Add Sentry breadcrumb for sync results
        _addSyncBreadcrumb(value, event.forceFullHistory);
        
        final prefix = event.forceFullHistory ? 'Full-history sync: ' : '';
        emit(
          state.copyWith(
            phase: WorkoutHistoryPhase.idle,
            workouts: value,
            message: value.isEmpty
                ? '${prefix}No workouts in Count window — watch may still '
                    'treat older sessions as already synced'
                : '$prefix'
                    'Synced ${value.length} workout(s)',
          ),
        );
    }
  }

  void _addSyncBreadcrumb(
    List<dynamic> workouts,
    bool forceFullHistory,
  ) {
    try {
      final typeCounts = <int, int>{};
      for (final workout in workouts) {
        if (workout is Map && workout.containsKey('type')) {
          final type = workout['type'] as int;
          typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        }
      }

      final typeSummary = typeCounts.entries
          .map((e) => '${workoutTypeLabel(e.key)}: ${e.value}')
          .join(', ');

      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'Workout sync completed',
          category: 'workout.sync',
          level: SentryLevel.info,
          data: {
            'count': workouts.length,
            'forceFullHistory': forceFullHistory,
            'types': typeSummary,
            'isEmpty': workouts.isEmpty,
          },
        ),
      );
    } catch (e) {
      // Never crash on observability
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
