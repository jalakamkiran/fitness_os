import 'package:fitness_os/features/home/domain/home_precedence.dart';

/// States for home feature
sealed class HomeState {
  const HomeState();
}

final class HomeInitial extends HomeState {
  const HomeInitial();
}

final class HomeLoadInProgress extends HomeState {
  const HomeLoadInProgress();
}

final class HomeReady extends HomeState {
  const HomeReady(this.snapshot, {this.message, this.errorDetails});

  final HomeSnapshot snapshot;
  final String? message;
  final String? errorDetails;
}

final class HomeFailure extends HomeState {
  const HomeFailure(this.message);

  final String message;
}
