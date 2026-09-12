import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';

class WorkoutHistoryBloc
    extends Bloc<WorkoutHistoryEvent, WorkoutHistoryState> {
  WorkoutHistoryBloc({required WorkoutHistoryRepository repository})
      : _repository = repository,
        super(const WorkoutHistoryState()) {
    on<WorkoutHistoryStarted>(_onStarted);
    on<WorkoutHistorySyncRequested>(_onSync);
  }

  final WorkoutHistoryRepository _repository;

  Future<void> _onStarted(
    WorkoutHistoryStarted event,
    Emitter<WorkoutHistoryState> emit,
  ) async {
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
}
