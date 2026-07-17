import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_event.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_state.dart';

class DevicePairingBloc extends Bloc<DevicePairingEvent, DevicePairingState> {
  DevicePairingBloc({required DevicePairingRepository repository})
      : _repository = repository,
        super(const DevicePairingState()) {
    on<DevicePairingStarted>(_onStarted);
    on<DevicePairingScanRequested>(_onScan);
    on<DevicePairingStopScanRequested>(_onStopScan);
    on<DevicePairingSelectDevice>(_onSelect);
    on<DevicePairingAuthKeySubmitted>(_onAuthKey);
    on<DevicePairingForgetRequested>(_onForget);
    on<DevicePairingR11Recorded>(_onR11);
    on<DevicePairingCreditInterrupt>(_onCredit);
    on<DevicePairingLinkUpdated>(_onLinkUpdated);
  }

  final DevicePairingRepository _repository;
  StreamSubscription<HuaweiLinkEvent>? _sub;

  Future<void> _onStarted(
    DevicePairingStarted event,
    Emitter<DevicePairingState> emit,
  ) async {
    await _repository.startLink();
    await _sub?.cancel();
    _sub = _repository.linkEvents.listen((_) {
      add(const DevicePairingLinkUpdated());
    });

    final remembered = await _repository.loadRemembered();
    final gateA = await _repository.loadGateAStatus();
    emit(state.copyWith(remembered: remembered, gateA: gateA));

    if (remembered != null) {
      final result = await _repository.reconnectRemembered();
      result.fold(
        (f) => emit(
          state.copyWith(
            linkState: _repository.linkState,
            remembered: remembered,
            gateA: gateA,
            message: f.message,
            recoveryHint: _repository.recoveryHint,
          ),
        ),
        (_) => emit(
          state.copyWith(
            linkState: gateA.passed
                ? LinkState.connected
                : _repository.linkState,
            remembered: remembered,
            gateA: gateA,
            clearMessage: true,
          ),
        ),
      );
    } else {
      emit(
        state.copyWith(
          linkState: _repository.linkState,
          gateA: gateA,
          clearRemembered: true,
        ),
      );
    }
  }

  Future<void> _onScan(
    DevicePairingScanRequested event,
    Emitter<DevicePairingState> emit,
  ) async {
    final result = await _repository.startScan();
    result.fold(
      (f) => emit(
        state.copyWith(
          linkState: _repository.linkState,
          message: f.message,
        ),
      ),
      (_) => emit(
        state.copyWith(
          linkState: _repository.linkState,
          devices: _repository.discovered,
          clearMessage: true,
        ),
      ),
    );
  }

  Future<void> _onStopScan(
    DevicePairingStopScanRequested event,
    Emitter<DevicePairingState> emit,
  ) async {
    await _repository.stopScan();
    emit(state.copyWith(linkState: _repository.linkState));
  }

  Future<void> _onSelect(
    DevicePairingSelectDevice event,
    Emitter<DevicePairingState> emit,
  ) async {
    emit(state.copyWith(linkState: LinkState.connecting, clearMessage: true));
    final result = await _repository.pair(event.mac, event.name);
    final remembered = await _repository.loadRemembered();
    result.fold(
      (f) => emit(
        state.copyWith(
          linkState: _repository.linkState,
          remembered: remembered,
          message: f.message,
          recoveryHint: _repository.recoveryHint,
        ),
      ),
      (_) => emit(
        state.copyWith(
          linkState: _repository.linkState,
          remembered: remembered,
          clearMessage: true,
        ),
      ),
    );
  }

  Future<void> _onAuthKey(
    DevicePairingAuthKeySubmitted event,
    Emitter<DevicePairingState> emit,
  ) async {
    final result = await _repository.setAuthKey(event.userId);
    result.fold(
      (f) => emit(state.copyWith(message: f.message)),
      (_) => emit(
        state.copyWith(
          authKeyMasked: event.userId.trim().isNotEmpty,
          message: 'Auth key saved (masked). Retry connect.',
        ),
      ),
    );
  }

  Future<void> _onForget(
    DevicePairingForgetRequested event,
    Emitter<DevicePairingState> emit,
  ) async {
    await _repository.forgetDevice();
    emit(
      const DevicePairingState(
        message: 'Device forgotten — identity, secrets, and Gate A cleared',
      ),
    );
  }

  Future<void> _onR11(
    DevicePairingR11Recorded event,
    Emitter<DevicePairingState> emit,
  ) async {
    await _repository.recordR11Path(event.path);
    emit(state.copyWith(message: 'Recorded R11 path: ${event.path}'));
  }

  Future<void> _onCredit(
    DevicePairingCreditInterrupt event,
    Emitter<DevicePairingState> emit,
  ) async {
    final authenticated = state.linkState == LinkState.gateAIncomplete ||
        state.linkState == LinkState.connected;
    final result = await _repository.creditInterrupt(
      interrupt: event.interrupt,
      reachedAuthenticated: authenticated,
    );
    result.fold(
      (f) => emit(state.copyWith(message: f.message)),
      (status) => emit(
        state.copyWith(
          gateA: status,
          linkState: status.passed
              ? LinkState.connected
              : state.linkState,
          message: status.passed
              ? 'Gate A unlocked'
              : 'Interrupt credited',
        ),
      ),
    );
  }

  void _onLinkUpdated(
    DevicePairingLinkUpdated event,
    Emitter<DevicePairingState> emit,
  ) {
    emit(
      state.copyWith(
        linkState: _repository.linkState,
        devices: _repository.discovered,
        message: _repository.lastError ?? state.message,
        recoveryHint: _repository.recoveryHint,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
