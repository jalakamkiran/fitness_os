import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
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
  bool _selectInFlight = false;

  Future<void> _onStarted(
    DevicePairingStarted event,
    Emitter<DevicePairingState> emit,
  ) async {
    FosHuaweiLog.i('bloc started', op: 'ui');
    await _repository.startLink();
    await _sub?.cancel();
    _sub = _repository.linkEvents.listen((_) {
      add(const DevicePairingLinkUpdated());
    });

    final remembered = await _repository.loadRemembered();
    final gateA = await _repository.loadGateAStatus();
    FosHuaweiLog.i(
      'remembered=${remembered != null} gateA.passed=${gateA.passed}',
      op: 'ui',
    );
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
    FosHuaweiLog.i('ui Scan pressed', op: 'ui');
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
    FosHuaweiLog.i('ui Stop scan pressed', op: 'ui');
    await _repository.stopScan();
    emit(
      state.copyWith(
        linkState: _repository.linkState,
        devices: _repository.discovered,
      ),
    );
  }

  Future<void> _onSelect(
    DevicePairingSelectDevice event,
    Emitter<DevicePairingState> emit,
  ) async {
    if (_selectInFlight) {
      FosHuaweiLog.w('ui select dropped — already pairing', op: 'ui');
      return;
    }
    final busy = state.linkState == LinkState.connecting ||
        state.linkState == LinkState.authenticating;
    if (busy) {
      FosHuaweiLog.w('ui select ignored — already ${state.linkState}', op: 'ui');
      return;
    }
    _selectInFlight = true;
    FosHuaweiLog.i('ui select ${event.name}', op: 'ui');
    emit(state.copyWith(linkState: LinkState.connecting, clearMessage: true));
    try {
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
    } finally {
      _selectInFlight = false;
    }
  }

  Future<void> _onAuthKey(
    DevicePairingAuthKeySubmitted event,
    Emitter<DevicePairingState> emit,
  ) async {
    final result = await _repository.setAuthKey(event.userId);
    result.fold(
      (f) => emit(state.copyWith(message: f.message)),
      (_) {
        final raw = event.userId.trim();
        final hex = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
        final isMac = hex.length == 12;
        emit(
          state.copyWith(
            authKeyMasked: raw.isNotEmpty && !isMac,
            message: isMac
                ? 'Phone MAC saved. Tap the GT5 in the list to pair again.'
                : 'Auth key saved. Tap the GT5 to pair again.',
          ),
        );
      },
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
    FosHuaweiLog.d(
      'ui linkUpdated → ${_repository.linkState} devices=${_repository.discovered.length}',
      op: 'ui',
    );
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
