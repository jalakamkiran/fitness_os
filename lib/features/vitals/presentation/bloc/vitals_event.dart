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

final class VitalsReloadRequested extends VitalsEvent {
  const VitalsReloadRequested();
}

final class VitalsSessionReadyChanged extends VitalsEvent {
  const VitalsSessionReadyChanged(this.sessionReady);

  final bool sessionReady;

  @override
  List<Object?> get props => [sessionReady];
}
