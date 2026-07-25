/// Events for home feature
sealed class HomeEvent {
  const HomeEvent();
}

final class HomeStarted extends HomeEvent {
  const HomeStarted();
}

final class HomeRefreshed extends HomeEvent {
  const HomeRefreshed();
}

final class HomeSyncRequested extends HomeEvent {
  const HomeSyncRequested();
}
