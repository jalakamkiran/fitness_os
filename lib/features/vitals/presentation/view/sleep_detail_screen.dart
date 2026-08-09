import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_hr_chart.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_hypnogram.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mix.dart';

enum _DetailMode { continuousHr, truSleepEnrich }

/// Sleep session detail (S1): hypnogram + mix + windowed HR + conditional toggle.
class SleepDetailScreen extends StatefulWidget {
  const SleepDetailScreen({
    super.key,
    required this.session,
    this.repository,
  });

  final SleepSessionSummary session;

  /// Optional override for widget tests.
  final VitalsRepository? repository;

  @override
  State<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends State<SleepDetailScreen> {
  bool _loading = true;
  List<SleepStageSummary> _stages = const [];
  List<DailyHrSample> _hr = const [];
  bool _enrichPresent = false;
  _DetailMode _mode = _DetailMode.continuousHr;

  VitalsRepository get _repo => widget.repository ?? sl<VitalsRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = widget.session;
    final stages = await _repo.loadSleepStages(session);
    final hr = await _repo.loadSleepHrWindow(
      beginUnix: session.beginUnix,
      endUnix: session.endUnix,
    );
    final enrich = await _repo.isSleepEnrichPresent(session);
    if (!mounted) return;
    setState(() {
      _stages = stages;
      _hr = hr;
      _enrichPresent = enrich;
      _loading = false;
      if (!enrich) _mode = _DetailMode.continuousHr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final session = widget.session;
    final overnight = sleepCrossesLocalMidnight(session);
    final end = sleepLocalFromUnix(session.endUnix);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sleep',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            Text(
              'Sleep · session',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  sleepFormatShortDate(end),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${sleepFormatWindow(session.beginUnix, session.endUnix)}'
                  '${overnight ? ' · overnight' : ''} · '
                  '${sleepFormatDuration(session.durationSec)}',
                  style: FathomTextStyles.mono(
                    fontSize: 12,
                    color: colors.inkFaint,
                  ),
                ),
                if (overnight) ...[
                  const SizedBox(height: 4),
                  Text(
                    'window crossed midnight · both dayKeys',
                    style: FathomTextStyles.mono(
                      fontSize: 11,
                      color: colors.inkFaint,
                    ),
                  ),
                ],
                if (_enrichPresent) ...[
                  const SizedBox(height: 16),
                  _EnrichModeToggle(
                    mode: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                ],
                const SizedBox(height: 16),
                _StructureSection(stages: _stages),
                const SizedBox(height: 12),
                if (_mode == _DetailMode.truSleepEnrich && _enrichPresent)
                  const _TruSleepEnrichPlaceholder()
                else
                  _HrSection(
                    samples: _hr,
                    stagesPresent: _stages.isNotEmpty,
                    overnight: overnight,
                  ),
              ],
            ),
    );
  }
}

class _EnrichModeToggle extends StatelessWidget {
  const _EnrichModeToggle({
    required this.mode,
    required this.onChanged,
  });

  final _DetailMode mode;
  final ValueChanged<_DetailMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              key: const ValueKey('sleep_mode_continuous_hr'),
              label: 'Continuous HR',
              selected: mode == _DetailMode.continuousHr,
              onTap: () => onChanged(_DetailMode.continuousHr),
            ),
          ),
          Expanded(
            child: _ModeTab(
              key: const ValueKey('sleep_mode_trusleep'),
              label: 'TruSleep enrich',
              selected: mode == _DetailMode.truSleepEnrich,
              onTap: () => onChanged(_DetailMode.truSleepEnrich),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Material(
      color: selected
          ? Color.lerp(colors.accent, colors.bgElev, 0.82) ?? colors.bgElev
          : colors.bgElev,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.ink : colors.inkFaint,
                ),
          ),
        ),
      ),
    );
  }
}

class _StructureSection extends StatelessWidget {
  const _StructureSection({required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    if (stages.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Stage structure',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No stage blocks for this session. Message-path stages '
                'absent — not invented.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.inkDim,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'wear overnight · Sync · stages from FitnessData',
                style: FathomTextStyles.mono(
                  fontSize: 11,
                  color: colors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stage structure',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SleepHypnogram(stages: stages),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stage mix',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SleepStageMixBars(stages: stages),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HrSection extends StatelessWidget {
  const _HrSection({
    required this.samples,
    required this.stagesPresent,
    required this.overnight,
  });

  final List<DailyHrSample> samples;
  final bool stagesPresent;
  final bool overnight;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    if (samples.isEmpty) {
      final body = stagesPresent
          ? 'Stages synced. Overnight HR needs auto-HR armed and wear — '
              'Sync again after.'
          : 'Overnight HR needs auto-HR armed and wear — Sync again after.';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Continuous HR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.inkDim,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'wear → Enable auto-HR → Sync',
                style: FathomTextStyles.mono(
                  fontSize: 11,
                  color: colors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Continuous HR',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SleepHrChart(
              samples: samples,
              overnightCaption: overnight,
            ),
          ],
        ),
      ),
    );
  }
}

class _TruSleepEnrichPlaceholder extends StatelessWidget {
  const _TruSleepEnrichPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'TruSleep enrich',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TruSleep file on device · enrich preview',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.inkDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PPG decode deferred · not a BPM claim',
                    style: FathomTextStyles.mono(
                      fontSize: 11,
                      color: colors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
