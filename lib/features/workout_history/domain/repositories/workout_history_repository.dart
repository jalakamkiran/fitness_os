import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';

abstract class WorkoutHistoryRepository {
  Future<bool> isGateAPassed();
  Future<List<WorkoutSummary>> loadLocal();
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch();
}
