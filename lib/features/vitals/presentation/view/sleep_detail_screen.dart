import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_hypnogram.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mix.dart';

/// Sleep session detail: file-window timing + attached stages (no continuous HR).
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

  VitalsRepository get _repo => widget.repository ?? sl<VitalsRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stages = await _repo.loadSleepStages(widget.session);
    if (!mounted) return;
    setState(() {
      _stages = stages;
      _loading = false;
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
                const SizedBox(height: 16),
                _StructureSection(stages: _stages),
              ],
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
                'wear overnight · Sync · stages attach when available',
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
