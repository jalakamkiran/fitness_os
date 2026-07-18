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

final class VitalsReloadRequested extends VitalsEvent {
  const VitalsReloadRequested();
}
