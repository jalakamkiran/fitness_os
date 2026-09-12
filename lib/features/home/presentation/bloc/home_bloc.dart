import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/domain/repositories/home_repository.dart';
import 'package:fitness_os/features/home/domain/usecases/get_home_data.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_event.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_state.dart';

/// Home now-state: binds to link/sync and emits precedence snapshots.
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required GetHomeData getHomeData,
    required HomeRepository repository,
    required DevicePairingRepository pairing,
    StoreInvalidation? invalidation,
  })  : _getHomeData = getHomeData,
        _repository = repository,
        _pairing = pairing,
        _invalidation = invalidation,
        super(const HomeInitial()) {
    on<HomeStarted>(_onStarted);
    on<HomeRefreshed>(_onRefreshed);
    on<HomeSyncRequested>(_onSyncRequested);
  }

  final GetHomeData _getHomeData;
  final HomeRepository _repository;
  final DevicePairingRepository _pairing;
  final StoreInvalidation? _invalidation;
  StreamSubscription<HuaweiLinkEvent>? _linkSub;
  StreamSubscription<void>? _invalidationSub;

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    await _linkSub?.cancel();
    await _invalidationSub?.cancel();
    _linkSub = _pairing.linkEvents.listen((_) {
      if (!isClosed) add(const HomeRefreshed());
    });
    _invalidationSub = _invalidation?.stream.listen((_) {
      if (!isClosed) add(const HomeRefreshed());
    });
    await _load(emit);
  }

  Future<void> _onRefreshed(
    HomeRefreshed event,
    Emitter<HomeState> emit,
  ) async {
    await _load(emit, keepPrior: true);
  }

  Future<void> _onSyncRequested(
    HomeSyncRequested event,
    Emitter<HomeState> emit,
  ) async {
    final prior = state is HomeReady ? (state as HomeReady).snapshot : null;
    if (prior != null) {
      emit(
        HomeReady(
          HomeSnapshot(
            precedence: HomePrecedence.syncInProgress,
            deviceLabel: prior.deviceLabel,
            brandSubtitle: 'GT5 · syncing…',
            syncPillLabel: 'Syncing',
            syncTitle: 'Pulling today’s data',
            syncCaption: 'One-shot pass on open · keep UI calm.',
            lastSyncedLabel: prior.lastSyncedLabel,
            caloriesLabel: prior.caloriesLabel,
            stepsLabel: prior.stepsLabel,
            workoutTimeLabel: prior.workoutTimeLabel,
            sleepDurationLabel: prior.sleepDurationLabel,
            sleepWindowLabel: prior.sleepWindowLabel,
            sleepFeelCue: prior.sleepFeelCue,
            bodyHrLabel: prior.bodyHrLabel,
            bodyHrSparkSamples: prior.bodyHrSparkSamples,
            todaySessions: prior.todaySessions,
          ),
        ),
      );
    }

    final ok = await _repository.syncNow();
    final snap = await _getHomeData();
    emit(
      HomeReady(
        snap,
        message: ok ? null : 'Sync failed — retry when ready.',
      ),
    );
  }

  Future<void> _load(
    Emitter<HomeState> emit, {
    bool keepPrior = false,
  }) async {
    if (!keepPrior || state is HomeInitial) {
      emit(const HomeLoadInProgress());
    }
    try {
      final snap = await _getHomeData();
      emit(HomeReady(snap));
    } catch (e) {
      emit(HomeFailure(e.toString()));
    }
  }

  @override
  Future<void> close() async {
    await _linkSub?.cancel();
    await _invalidationSub?.cancel();
    return super.close();
  }
}
