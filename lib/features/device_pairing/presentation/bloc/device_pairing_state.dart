import 'package:equatable/equatable.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';

class DevicePairingState extends Equatable {
  const DevicePairingState({
    this.linkState = LinkState.disconnected,
    this.devices = const [],
    this.remembered,
    this.gateA = const GateAStatus(
      killOk: false,
      rebootOk: false,
      btToggleOk: false,
      passed: false,
    ),
    this.message,
    this.recoveryHint,
    this.authKeyMasked = false,
  });

  final LinkState linkState;
  final List<DiscoveredDevice> devices;
  final RememberedDevice? remembered;
  final GateAStatus gateA;
  final String? message;
  final String? recoveryHint;
  final bool authKeyMasked;

  DevicePairingState copyWith({
    LinkState? linkState,
    List<DiscoveredDevice>? devices,
    RememberedDevice? remembered,
    bool clearRemembered = false,
    GateAStatus? gateA,
    String? message,
    bool clearMessage = false,
    String? recoveryHint,
    bool? authKeyMasked,
  }) {
    return DevicePairingState(
      linkState: linkState ?? this.linkState,
      devices: devices ?? this.devices,
      remembered: clearRemembered ? null : (remembered ?? this.remembered),
      gateA: gateA ?? this.gateA,
      message: clearMessage ? null : (message ?? this.message),
      recoveryHint: recoveryHint ?? this.recoveryHint,
      authKeyMasked: authKeyMasked ?? this.authKeyMasked,
    );
  }

  @override
  List<Object?> get props => [
        linkState,
        devices,
        remembered,
        gateA,
        message,
        recoveryHint,
        authKeyMasked,
      ];
}
