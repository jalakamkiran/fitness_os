import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/hr_sparkline.dart';

class VitalsScreen extends StatelessWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<VitalsBloc>()..add(const VitalsStarted()),
      child: const _VitalsView(),
    );
  }
}

class _VitalsView extends StatelessWidget {
  const _VitalsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vitals')),
      body: BlocBuilder<VitalsBloc, VitalsState>(
        builder: (context, state) {
          final enabling = state.phase == VitalsPhase.enabling;
          final syncing = state.phase == VitalsPhase.syncing;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_statusCopy(state)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: state.enableDisabled
                          ? null
                          : () => context
                              .read<VitalsBloc>()
                              .add(const VitalsEnableRequested()),
                      icon: enabling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.monitor_heart_outlined),
                      label: Text(
                        enabling ? 'Enabling…' : 'Enable auto-tracking',
                      ),
                    ),
                    if (state.lastEnable != null) ...[
                      const SizedBox(height: 8),
                      _LastEnablePanel(result: state.lastEnable!),
                    ],
                    if (state.enableNextStep != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.enableNextStep!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: state.syncDisabled
                          ? null
                          : () => context
                              .read<VitalsBloc>()
                              .add(const VitalsSyncRequested()),
                      icon: syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(syncing ? 'Syncing…' : 'Sync'),
                    ),
                    if (state.message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.message!,
                        style: TextStyle(
                          color: state.phase == VitalsPhase.stuck
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Sleep sessions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (state.sleepSessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          'No sleep sessions stored yet.\n'
                          'Wear overnight (prefer night 2 after pairing), then Sync.',
                        ),
                      )
                    else
                      ...state.sleepSessions.map(_SleepRow.new),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'Whole-day heart rate',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: _HrDayPanel(
                        day: state.latestHrDay,
                        series: state.latestHrSeries,
                        lastEnable: state.lastEnable,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusCopy(VitalsState state) {
    if (!state.gateAPassed) {
      return 'Gate A incomplete — finish the interrupt checklist on Home first.';
    }
    if (!state.sessionReady) {
      return 'Connect the watch (encrypted session) before Enable auto-tracking.';
    }
    if (state.phase == VitalsPhase.stuck) {
      return 'Sync stuck — switch to Home, disconnect and reconnect, then return and Sync.';
    }
    if (!state.everSynced) {
      return 'Enable auto-tracking on the watch, wear several hours, then Sync.';
    }
    return 'Gate A unlocked — Enable arms tracking; Sync refreshes sleep and HR.';
  }
}

class _LastEnablePanel extends StatelessWidget {
  const _LastEnablePanel({required this.result});

  final AutoTrackingEnableResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (result.overall) {
            AutoTrackingOverall.allArmed => 'Last enable: all armed',
            AutoTrackingOverall.partial => 'Last enable: partial — tap to retry',
            AutoTrackingOverall.noneArmed =>
              'Last enable: none armed — tap to retry',
          },
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final f in result.features)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _featureLine(f),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _featureLine(AutoTrackingFeatureOutcome f) {
    final label = switch (f.id) {
      'trusleep' => 'TruSleep',
      'auto_hr' => 'Auto heart rate',
      'auto_spo2' => 'Auto SpO2',
      _ => f.id,
    };
    final note = f.id == 'auto_spo2' && f.outcome == 'armed'
        ? ' — tracking armed on watch, not shown in app yet'
        : '';
    return '$label: ${f.outcome}$note';
  }
}

class _SleepRow extends StatelessWidget {
  const _SleepRow(this.session);

  final SleepSessionSummary session;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_formatDuration(session.durationSec)),
      subtitle: Text(
        _formatRange(session.beginUnix, session.endUnix),
      ),
    );
  }
}

class _HrDayPanel extends StatelessWidget {
  const _HrDayPanel({
    this.day,
    this.series = const [],
    this.lastEnable,
  });

  final DailyHrDaySummary? day;
  final List<DailyHrSample> series;
  final AutoTrackingEnableResult? lastEnable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (day == null) {
      return _HrEmptyCopy(lastEnable: lastEnable);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              day!.dayKey,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'min ${day!.minBpm} · avg ${day!.avgBpm} · max ${day!.maxBpm} bpm '
              '(${day!.sampleCount} samples)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            HrSparkline(samples: series),
          ],
        ),
      ),
    );
  }
}

class _HrEmptyCopy extends StatelessWidget {
  const _HrEmptyCopy({this.lastEnable});

  final AutoTrackingEnableResult? lastEnable;

  @override
  Widget build(BuildContext context) {
    final hrOutcome = lastEnable?.outcomeFor('auto_hr');
    if (hrOutcome == 'armed') {
      return const Text(
        'No whole-day heart rate for a recent day.\n'
        'Wear the watch for several hours, then Sync — '
        'fresh auto-HR may not backfill older minutes.',
      );
    }
    if (hrOutcome == 'skipped' ||
        hrOutcome == 'failed' ||
        hrOutcome == 'timed_out') {
      return Text(
        'No whole-day heart rate for a recent day.\n'
        'Auto-HR last Enable was $hrOutcome — tap Enable auto-tracking, '
        'then wear and Sync.',
      );
    }
    if (lastEnable == null) {
      return const Text(
        'No whole-day heart rate for a recent day.\n'
        'Tap Enable auto-tracking, wear several hours, then Sync.',
      );
    }
    return const Text(
      'No whole-day heart rate for a recent day.\n'
      'Wear the watch for several hours with auto-HR on, then Sync.',
    );
  }
}
String _formatRange(int beginUnix, int endUnix) {
  // Wire timestamps are UTC unix seconds; show device local (IST on your phone).
  final begin =
      DateTime.fromMillisecondsSinceEpoch(beginUnix * 1000, isUtc: true)
          .toLocal();
  final end =
      DateTime.fromMillisecondsSinceEpoch(endUnix * 1000, isUtc: true).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';
  final start = '${two(begin.hour)}:${two(begin.minute)}';
  final stop = '${two(end.hour)}:${two(end.minute)}';
  final sameDay = begin.year == end.year &&
      begin.month == end.month &&
      begin.day == end.day;
  if (sameDay) return '${dayLabel(begin)} · $start – $stop';
  return '${dayLabel(begin)} $start – ${dayLabel(end)} $stop';
}

String _formatDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
