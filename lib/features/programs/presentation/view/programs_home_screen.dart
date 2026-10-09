import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_progress_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_proof_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_session_screen.dart';
import 'package:fitness_os/features/programs/presentation/widgets/soft_warn_banner.dart';

/// Active program home: next milestone, forecast, today’s chore, soft-warn.
class ProgramsHomeScreen extends StatelessWidget {
  const ProgramsHomeScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final program = controller.active!;
    final ms = controller.nextMilestone;
    final chore = controller.todaysChore;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Programs'),
        backgroundColor: colors.bg,
        foregroundColor: colors.ink,
        elevation: 0,
        actions: [
          TextButton(
            key: const Key('programs-open-progress'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ProgramsProgressScreen(controller: controller),
                ),
              );
            },
            child: Text('Progress', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (program.feasibilityWarning != null) ...[
              Text(
                program.feasibilityWarning!,
                key: const Key('programs-feasibility-warning'),
                style:
                    TextStyle(fontSize: 13, color: colors.amber, height: 1.35),
              ),
              const SizedBox(height: 12),
            ],
            SoftWarnBanner(result: controller.softWarn),
            if (controller.softWarn.warn) const SizedBox(height: 14),
            if (ms != null) _MilestoneCard(milestone: ms, colors: colors),
            const SizedBox(height: 14),
            _ForecastCard(program: program, colors: colors),
            const SizedBox(height: 14),
            if (chore != null)
              _ChoreCard(
                chore: chore,
                colors: colors,
                onOpen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProgramsSessionScreen(
                        controller: controller,
                        choreId: chore.id,
                      ),
                    ),
                  );
                },
              )
            else
              Text(
                'No session scheduled for today.',
                style: TextStyle(color: colors.inkDim, fontSize: 14),
              ),
            if (ms != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                key: const Key('programs-open-proof'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProgramsProofScreen(
                        controller: controller,
                        milestoneId: ms.id,
                      ),
                    ),
                  );
                },
                child: const Text('Record proof'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestone, required this.colors});

  final Milestone milestone;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('programs-next-milestone'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next milestone',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatMeters(milestone.targetDistanceM)} m continuous',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Forecast ${milestone.forecastDateIso}',
            key: const Key('programs-milestone-date'),
            style: TextStyle(fontSize: 14, color: colors.inkDim),
          ),
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.program, required this.colors});

  final Program program;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final likely = program.goalForecastLikelyIso;
    final earliest = program.goalForecastEarliestIso;
    final latest = program.goalForecastLatestIso;
    return Container(
      key: const Key('programs-forecast'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Goal forecast',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            likely ?? 'Building forecast…',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          if (earliest != null && latest != null) ...[
            const SizedBox(height: 4),
            Text(
              'Range $earliest – $latest',
              style: TextStyle(fontSize: 13, color: colors.inkDim),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoreCard extends StatelessWidget {
  const _ChoreCard({
    required this.chore,
    required this.colors,
    required this.onOpen,
  });

  final ChoreSession chore;
  final FathomColors colors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final hasStructure = chore.hasWuMainCd;
    return Material(
      color: colors.bgElev,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('programs-today-chore'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today’s session',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                chore.focusLine ?? _roleLabel(chore.role),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasStructure
                    ? 'Warm-up · Main · Cool-down · ${formatMeters(chore.targetDistanceM)} m'
                    : '${formatMeters(chore.targetDistanceM)} m',
                key: const Key('programs-chore-structure'),
                style: TextStyle(fontSize: 13, color: colors.inkDim),
              ),
              const SizedBox(height: 10),
              Text(
                'Open session',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleLabel(ChoreRole role) {
    switch (role) {
      case ChoreRole.endurance:
        return 'Endurance swim';
      case ChoreRole.quality:
        return 'Quality set';
      case ChoreRole.technique:
        return 'Technique';
      case ChoreRole.recovery:
        return 'Recovery';
      case ChoreRole.proof:
        return 'Proof swim';
      case ChoreRole.guidedTest:
        return 'Guided test';
      case ChoreRole.easy:
        return 'Easy swim';
    }
  }
}
