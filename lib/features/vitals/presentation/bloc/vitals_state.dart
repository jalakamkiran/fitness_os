import 'package:equatable/equatable.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';

enum VitalsPhase { blocked, idle, syncing, enabling, probing, stuck }

class VitalsState extends Equatable {
  const VitalsState({
    this.gateAPassed = false,
    this.sessionReady = false,
    this.phase = VitalsPhase.blocked,
    this.sleepSessions = const [],
    this.dailyHr = const [],
    this.latestHrSeries = const [],
    this.message,
    this.partial = false,
    this.enableSkipped = false,
    this.everSynced = false,
    this.lastEnable,
    this.enableNextStep,
  });

  final bool gateAPassed;
  final bool sessionReady;
  final VitalsPhase phase;
  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrDaySummary> dailyHr;
  final List<DailyHrSample> latestHrSeries;
  final String? message;
  final bool partial;
  final bool enableSkipped;
  final bool everSynced;
  final AutoTrackingEnableResult? lastEnable;
  final String? enableNextStep;

  DailyHrDaySummary? get latestHrDay =>
      dailyHr.isEmpty ? null : dailyHr.first;

  bool get enableDisabled =>
      !gateAPassed ||
      !sessionReady ||
      phase == VitalsPhase.enabling ||
      phase == VitalsPhase.syncing ||
      phase == VitalsPhase.probing;

  bool get syncDisabled =>
      !gateAPassed ||
      phase == VitalsPhase.enabling ||
      phase == VitalsPhase.syncing ||
      phase == VitalsPhase.probing;

  bool get probeDisabled =>
      !gateAPassed ||
      !sessionReady ||
      phase == VitalsPhase.enabling ||
      phase == VitalsPhase.syncing ||
      phase == VitalsPhase.probing;

  VitalsState copyWith({
    bool? gateAPassed,
    bool? sessionReady,
    VitalsPhase? phase,
    List<SleepSessionSummary>? sleepSessions,
    List<DailyHrDaySummary>? dailyHr,
    List<DailyHrSample>? latestHrSeries,
    String? message,
    bool clearMessage = false,
    bool? partial,
    bool? enableSkipped,
    bool? everSynced,
    AutoTrackingEnableResult? lastEnable,
    bool clearLastEnable = false,
    String? enableNextStep,
    bool clearEnableNextStep = false,
  }) {
    return VitalsState(
      gateAPassed: gateAPassed ?? this.gateAPassed,
      sessionReady: sessionReady ?? this.sessionReady,
      phase: phase ?? this.phase,
      sleepSessions: sleepSessions ?? this.sleepSessions,
      dailyHr: dailyHr ?? this.dailyHr,
      latestHrSeries: latestHrSeries ?? this.latestHrSeries,
      message: clearMessage ? null : (message ?? this.message),
      partial: partial ?? this.partial,
      enableSkipped: enableSkipped ?? this.enableSkipped,
      everSynced: everSynced ?? this.everSynced,
      lastEnable: clearLastEnable ? null : (lastEnable ?? this.lastEnable),
      enableNextStep: clearEnableNextStep
          ? null
          : (enableNextStep ?? this.enableNextStep),
    );
  }

  @override
  List<Object?> get props => [
        gateAPassed,
        sessionReady,
        phase,
        sleepSessions,
        dailyHr,
        latestHrSeries,
        message,
        partial,
        enableSkipped,
        everSynced,
        lastEnable,
        enableNextStep,
      ];
}
