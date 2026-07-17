import 'package:equatable/equatable.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';

sealed class DevicePairingEvent extends Equatable {
  const DevicePairingEvent();
  @override
  List<Object?> get props => [];
}

final class DevicePairingStarted extends DevicePairingEvent {
  const DevicePairingStarted();
}

final class DevicePairingScanRequested extends DevicePairingEvent {
  const DevicePairingScanRequested();
}

final class DevicePairingStopScanRequested extends DevicePairingEvent {
  const DevicePairingStopScanRequested();
}

final class DevicePairingSelectDevice extends DevicePairingEvent {
  const DevicePairingSelectDevice({required this.mac, required this.name});
  final String mac;
  final String name;
  @override
  List<Object?> get props => [mac, name];
}

final class DevicePairingAuthKeySubmitted extends DevicePairingEvent {
  const DevicePairingAuthKeySubmitted(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

final class DevicePairingForgetRequested extends DevicePairingEvent {
  const DevicePairingForgetRequested();
}

final class DevicePairingR11Recorded extends DevicePairingEvent {
  const DevicePairingR11Recorded(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

final class DevicePairingCreditInterrupt extends DevicePairingEvent {
  const DevicePairingCreditInterrupt(this.interrupt);
  final GateAInterrupt interrupt;
  @override
  List<Object?> get props => [interrupt];
}

final class DevicePairingLinkUpdated extends DevicePairingEvent {
  const DevicePairingLinkUpdated();
}
