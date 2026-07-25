import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/domain/repositories/home_repository.dart';

/// Loads the Home now-state snapshot.
class GetHomeData {
  const GetHomeData({required this.repository});

  final HomeRepository repository;

  Future<HomeSnapshot> call() => repository.loadSnapshot();
}
