import 'package:equatable/equatable.dart';

sealed class VitalsEvent extends Equatable {
  const VitalsEvent();

  @override
  List<Object?> get props => [];
}

final class VitalsStarted extends VitalsEvent {
  const VitalsStarted();
}

final class VitalsSyncRequested extends VitalsEvent {
  const VitalsSyncRequested();
}

final class VitalsEnableRequested extends VitalsEvent {
  const VitalsEnableRequested();
}

/// Debug-only dict / sleep_data / path-2 capture probe (never product SoT).
final class VitalsPhysioProbeRequested extends VitalsEvent {
  const VitalsPhysioProbeRequested();
}

/// Debug-only: download and keep `sleep_data.bin` on disk (never product SoT).
final class VitalsPersistSleepDataRequested extends VitalsEvent {
  const VitalsPersistSleepDataRequested();
}

/// Debug-only: download and keep SEQUENCE_DATA SLEEP_DETAILS on disk.
final class VitalsPersistSleepDictRequested extends VitalsEvent {
  const VitalsPersistSleepDictRequested();
}

final class VitalsReloadRequested extends VitalsEvent {
  const VitalsReloadRequested();
}

final class VitalsSessionReadyChanged extends VitalsEvent {
  const VitalsSessionReadyChanged(this.sessionReady);

  final bool sessionReady;

  @override
  List<Object?> get props => [sessionReady];
}
