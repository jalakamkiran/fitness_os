import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';

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
                      onPressed: !state.gateAPassed || syncing
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
                      child: _HrSummary(day: state.latestHrDay),
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
    if (state.phase == VitalsPhase.stuck) {
      return 'Sync stuck — switch to Home, disconnect and reconnect, then return and Sync.';
    }
    if (!state.everSynced) {
      return 'Pull sleep and whole-day heart rate from the watch (last 14 days).';
    }
    return 'Gate A unlocked — Sync refreshes sleep and whole-day HR.';
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

class _HrSummary extends StatelessWidget {
  const _HrSummary({this.day});

  final DailyHrDaySummary? day;

  @override
  Widget build(BuildContext context) {
    if (day == null) {
      return const Text(
        'No whole-day heart rate for a recent day.\n'
        'Wear the watch for several hours with auto-HR on, then Sync.',
      );
    }
    return Text(
      '${day!.dayKey}: min ${day!.minBpm} · avg ${day!.avgBpm} · '
      'max ${day!.maxBpm} bpm (${day!.sampleCount} samples)',
    );
  }
}

String _formatRange(int beginUnix, int endUnix) {
  final begin = DateTime.fromMillisecondsSinceEpoch(beginUnix * 1000);
  final end = DateTime.fromMillisecondsSinceEpoch(endUnix * 1000);
  String two(int n) => n.toString().padLeft(2, '0');
  final sameDay = begin.year == end.year &&
      begin.month == end.month &&
      begin.day == end.day;
  final day =
      '${begin.year}-${two(begin.month)}-${two(begin.day)}';
  final start = '${two(begin.hour)}:${two(begin.minute)}';
  final stop = '${two(end.hour)}:${two(end.minute)}';
  if (sameDay) return '$day · $start – $stop';
  return '$day $start – ${end.year}-${two(end.month)}-${two(end.day)} $stop';
}

String _formatDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m sleep';
  return '${m}m sleep';
}
