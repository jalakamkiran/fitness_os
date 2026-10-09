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
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';
import 'package:fitness_os/features/programs/presentation/widgets/soft_warn_banner.dart';

/// Agon home: next trial, forecast, soft-warn, today’s course, Odyssey strip.
class ProgramsHomeScreen extends StatelessWidget {
  const ProgramsHomeScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final program = controller.active!;
    final ms = controller.nextMilestone;
    final chore = controller.todaysChore;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Agon · Pool',
        subtitle: formatGoalLine(program.intake),
        onBack: Navigator.of(context).canPop()
            ? () => Navigator.of(context).pop()
            : null,
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz, color: colors.inkDim),
          onSelected: (v) async {
            if (v == 'new') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Start a new Agon?'),
                  content: const Text(
                    'This archives the current plan so you can chart a new one. '
                    'Streak and Areté stay on your device.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('New Agon'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await controller.archiveActiveAndReset();
              }
            } else if (v == 'odyssey') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ProgramsProgressScreen(controller: controller),
                ),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'odyssey', child: Text('Odyssey')),
            PopupMenuItem(value: 'new', child: Text('New Agon…')),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(
              program: program,
              now: now,
              colors: colors,
            ),
            const SizedBox(height: 12),
            if (ms != null)
              _MilestoneCard(
                milestone: ms,
                program: program,
                colors: colors,
                onOpenProof: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProgramsProofScreen(
                        controller: controller,
                        milestoneId: ms.id,
                      ),
                    ),
                  );
                },
              ),
            if (ms != null) const SizedBox(height: 12),
            _ForecastCard(program: program, colors: colors),
            const SizedBox(height: 12),
            if (program.feasibilityWarning != null) ...[
              Text(
                program.feasibilityWarning!,
                key: const Key('programs-feasibility-warning'),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.amber,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SoftWarnBanner(result: controller.softWarn),
            if (controller.softWarn.warn) const SizedBox(height: 12),
            if (controller.asOfLastSyncLabel != null) ...[
              Text(
                controller.asOfLastSyncLabel!,
                key: const Key('programs-as-of-sync'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.inkDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (chore != null)
              _CourseCard(
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
                'No course scheduled for today.',
                style: TextStyle(color: colors.inkDim, fontSize: 14),
              ),
            if (!controller.hideGameLayer) ...[
              const SizedBox(height: 12),
              _OdysseyStrip(
                controller: controller,
                colors: colors,
                onOpen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProgramsProgressScreen(controller: controller),
                    ),
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('programs-open-progress'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ProgramsProgressScreen(controller: controller),
                      ),
                    );
                  },
                  child: Text(
                    'Scorecards',
                    style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            if (ms != null) ...[
              const SizedBox(height: 8),
              TextButton(
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
                child: Text(
                  'Record trial',
                  style: TextStyle(
                    color: colors.inkDim,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.ink.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.program,
    required this.now,
    required this.colors,
  });

  final Program program;
  final DateTime now;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agon · Pool swim',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: colors.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatGoalLine(program.intake),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.12,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AgonChip(formatWeekChip(program, now)),
            AgonChip(formatSessionsChip(program.intake)),
          ],
        ),
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.program,
    required this.colors,
    required this.onOpenProof,
  });

  final Milestone milestone;
  final Program program;
  final FathomColors colors;
  final VoidCallback onOpenProof;

  @override
  Widget build(BuildContext context) {
    final startM = program.baseline?.capacityDistanceM ?? 0;
    final trialM = milestone.targetDistanceM;

    return AgonCard(
      key: const Key('programs-next-milestone'),
      radius: 14,
      borderColor: colors.ink.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LayerTag('Next milestone'),
                    const SizedBox(height: 5),
                    Text(
                      formatTrialName(milestone),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.12,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatTrialSpec(
                        milestone,
                        goalTimeSec: program.intake.targetTimeSec,
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.inkDim,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    key: const Key('programs-milestone-date'),
                    milestone.forecastDateIso,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'forecast',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.inkFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RungRow(
            startM: startM > 0 ? startM : trialM,
            trialM: trialM,
            colors: colors,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpenProof,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Record trial',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.inkDim,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.ink.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RungRow extends StatelessWidget {
  const _RungRow({
    required this.startM,
    required this.trialM,
    required this.colors,
  });

  final int startM;
  final int trialM;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Rung(
          value: formatMeters(startM),
          label: 'Sounding',
          done: true,
          colors: colors,
        ),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 18),
            color: colors.accent,
          ),
        ),
        _Rung(
          value: formatMeters(trialM),
          label: 'Trial',
          done: false,
          next: true,
          colors: colors,
        ),
      ],
    );
  }
}

class _Rung extends StatelessWidget {
  const _Rung({
    required this.value,
    required this.label,
    required this.done,
    required this.colors,
    this.next = false,
  });

  final String value;
  final String label;
  final bool done;
  final bool next;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: done ? colors.accent : colors.bgElev,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: done || next ? colors.accent : colors.gaugeTrack,
              width: 2,
            ),
            boxShadow: next
                ? [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.24),
                      blurRadius: 0,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.5,
            color: colors.inkFaint,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
    final slipped = earliest != null &&
        latest != null &&
        likely != null &&
        (earliest != likely || latest != likely);

    return AgonCard(
      key: const Key('programs-forecast'),
      radius: 14,
      borderColor: colors.ink.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LayerTag('Goal forecast'),
                    const SizedBox(height: 4),
                    Text(
                      likely ?? 'Building forecast…',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: slipped
                      ? colors.ink.withValues(alpha: 0.09)
                      : colors.up.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  slipped ? 'Window' : 'On plan',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w500,
                    color: slipped
                        ? colors.ink
                        : Color.lerp(colors.up, colors.ink, 0.22),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (earliest != null && latest != null) ...[
            const SizedBox(height: 6),
            Text(
              'Range $earliest – $latest',
              style: TextStyle(fontSize: 13, color: colors.inkDim),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'The forecast updates only when a trial moves.',
            style: TextStyle(fontSize: 11.5, color: colors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.chore,
    required this.colors,
    required this.onOpen,
  });

  final ChoreSession chore;
  final FathomColors colors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = formatCourseTitle(chore);
    final structure = formatCourseStructureLine(chore);
    final wu = sumPartMeters(chore.blocks, 'warmUp').clamp(1, 100000);
    final main = sumPartMeters(chore.blocks, 'main').clamp(1, 100000);
    final cd = sumPartMeters(chore.blocks, 'coolDown').clamp(1, 100000);

    return AgonCard(
      key: const Key('programs-today-chore'),
      radius: 18,
      borderColor: colors.ink.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayerTag(
                      'Today’s course · ${formatCourseDayTag(chore.dayIso).split(' · ').first}',
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.2,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      structure,
                      key: const Key('programs-chore-structure'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Due today',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w500,
                    color: colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (chore.hasWuMainCd) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: wu,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(colors.accent, colors.bgElev, 0.66),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  flex: main,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  flex: cd,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(colors.accent, colors.bgElev, 0.66),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _StructLabel(
                    name: 'Warm-up',
                    meters: wu,
                    align: TextAlign.left,
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _StructLabel(
                    name: 'Main',
                    meters: main,
                    align: TextAlign.center,
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _StructLabel(
                    name: 'Cool-down',
                    meters: cd,
                    align: TextAlign.right,
                    colors: colors,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Open today’s course',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StructLabel extends StatelessWidget {
  const _StructLabel({
    required this.name,
    required this.meters,
    required this.align,
    required this.colors,
  });

  final String name;
  final int meters;
  final TextAlign align;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align == TextAlign.left
          ? CrossAxisAlignment.start
          : align == TextAlign.right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.center,
      children: [
        Text(
          name,
          textAlign: align,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        Text(
          '${formatMeters(meters)} m',
          textAlign: align,
          style: TextStyle(
            fontSize: 10.5,
            color: colors.inkDim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _OdysseyStrip extends StatelessWidget {
  const _OdysseyStrip({
    required this.controller,
    required this.colors,
    required this.onOpen,
  });

  final ProgramsController controller;
  final FathomColors colors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ledger = controller.ledger;
    final bronze = agonBronzeOf(context);
    final wash = Color.lerp(bronze, colors.bgElev, 0.87)!;
    final line = Color.lerp(bronze, colors.line, 0.68)!;

    return Material(
      color: wash,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('programs-open-progress'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(bronze, colors.bgElev, 0.87)!,
                colors.bgElev,
              ],
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _OdCell(
                  label: 'Streak',
                  value: '${ledger.currentStreakWeeks}',
                  unit: ' wk',
                  sub: 'weeks in a row',
                  bronze: bronze,
                  colors: colors,
                ),
                VerticalDivider(width: 1, thickness: 1, color: line),
                _OdCell(
                  label: 'Areté',
                  value: formatMeters(ledger.totalXp),
                  sub: 'progress points',
                  bronze: bronze,
                  colors: colors,
                ),
                VerticalDivider(width: 1, thickness: 1, color: line),
                _OdCell(
                  label: 'Depth',
                  value: '${ledger.level}',
                  sub: 'progression',
                  bronze: bronze,
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OdCell extends StatelessWidget {
  const _OdCell({
    required this.label,
    required this.value,
    required this.sub,
    required this.bronze,
    required this.colors,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final String sub;
  final Color bronze;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w500,
                color: Color.lerp(bronze, colors.ink, 0.15),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: colors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                children: unit == null
                    ? null
                    : [
                        TextSpan(
                          text: unit,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.inkDim,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
              ),
            ),
            Text(
              sub,
              style: TextStyle(fontSize: 10.5, color: colors.inkDim),
            ),
          ],
        ),
      ),
    );
  }
}
