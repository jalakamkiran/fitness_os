import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/hr_sparkline.dart';

/// Vitals surface: Enable / Sync / sleep; whole-day HR is Enable-only (not Sync).
///
/// When [embedded] under Recovery, omits AppBar (host owns Recovery chrome)
/// and reuses the parent [VitalsBloc] — no second bottom nav / provider.
class VitalsScreen extends StatelessWidget {
  const VitalsScreen({
    super.key,
    this.embedded = false,
    this.bloc,
  });

  /// True when hosted under [RecoveryTabHost] (no Scaffold / AppBar).
  final bool embedded;

  /// Optional override for standalone widget tests.
  final VitalsBloc? bloc;

  @override
  Widget build(BuildContext context) {
    const body = _VitalsBody();
    if (embedded) {
      // Parent RecoveryTabHost owns BlocProvider + Scaffold.
      return body;
    }
    final override = bloc;
    if (override != null) {
      return BlocProvider.value(
        value: override,
        child: Scaffold(
          appBar: AppBar(title: const Text('Vitals')),
          body: body,
        ),
      );
    }
    return BlocProvider(
      create: (_) => sl<VitalsBloc>()..add(const VitalsStarted()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Vitals')),
        body: body,
      ),
    );
  }
}

class _VitalsBody extends StatelessWidget {
  const _VitalsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VitalsBloc, VitalsState>(
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
      return 'Enable auto-tracking on the watch if needed, then Sync for sleep.';
    }
    return 'Gate A unlocked — Enable arms tracking; Sync refreshes sleep.';
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
        'No whole-day heart rate stored.\n'
        'Sync does not pull continuous HR — Enable arms auto-HR on the watch only.',
      );
    }
    if (hrOutcome == 'skipped' ||
        hrOutcome == 'failed' ||
        hrOutcome == 'timed_out') {
      return Text(
        'No whole-day heart rate stored.\n'
        'Auto-HR last Enable was $hrOutcome — tap Enable auto-tracking if needed.',
      );
    }
    if (lastEnable == null) {
      return const Text(
        'No whole-day heart rate stored.\n'
        'Tap Enable auto-tracking to arm auto-HR on the watch (Sync will not refill it).',
      );
    }
    return const Text(
      'No whole-day heart rate stored.\n'
      'Sync does not pull continuous HR.',
    );
  }
}
