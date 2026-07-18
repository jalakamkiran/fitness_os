import 'package:equatable/equatable.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';

enum VitalsPhase { blocked, idle, syncing, stuck }

class VitalsState extends Equatable {
  const VitalsState({
    this.gateAPassed = false,
    this.phase = VitalsPhase.blocked,
    this.sleepSessions = const [],
    this.dailyHr = const [],
    this.message,
    this.partial = false,
    this.enableSkipped = false,
    this.everSynced = false,
  });

  final bool gateAPassed;
  final VitalsPhase phase;
  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrDaySummary> dailyHr;
  final String? message;
  final bool partial;
  final bool enableSkipped;
  final bool everSynced;

  DailyHrDaySummary? get latestHrDay =>
      dailyHr.isEmpty ? null : dailyHr.first;

  VitalsState copyWith({
    bool? gateAPassed,
    VitalsPhase? phase,
    List<SleepSessionSummary>? sleepSessions,
    List<DailyHrDaySummary>? dailyHr,
    String? message,
    bool clearMessage = false,
    bool? partial,
    bool? enableSkipped,
    bool? everSynced,
  }) {
    return VitalsState(
      gateAPassed: gateAPassed ?? this.gateAPassed,
      phase: phase ?? this.phase,
      sleepSessions: sleepSessions ?? this.sleepSessions,
      dailyHr: dailyHr ?? this.dailyHr,
      message: clearMessage ? null : (message ?? this.message),
      partial: partial ?? this.partial,
      enableSkipped: enableSkipped ?? this.enableSkipped,
      everSynced: everSynced ?? this.everSynced,
    );
  }

  @override
  List<Object?> get props => [
        gateAPassed,
        phase,
        sleepSessions,
        dailyHr,
        message,
        partial,
        enableSkipped,
        everSynced,
      ];
}
