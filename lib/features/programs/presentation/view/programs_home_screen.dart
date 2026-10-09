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
    final todayIso = _localIsoDay(now);
    final showManualTrial = ms != null && controller.trialNeedsManualRecord;

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
                todayIso: todayIso,
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
                controller.todaysChoreIncludingDone != null
                    ? 'Today’s course is done. No further sessions scheduled.'
                    : 'No course scheduled for today.',
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
            if (showManualTrial) ...[
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
                  'Record trial manually',
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
  });

  final Milestone milestone;
  final Program program;
  final FathomColors colors;

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
          // Trials auto-record from a synced proof swim; no manual CTA here.
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
    final planned = program.milestones.isNotEmpty
        ? program.milestones.last.plannedDateIso
        : likely;
    final slipped = earliest != null &&
        latest != null &&
        likely != null &&
        (earliest != likely || latest != likely || planned != likely);
    final timeline = _ForecastTimelineData.fromProgram(
      program,
      now: DateTime.now(),
    );

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
                    Text.rich(
                      TextSpan(
                        text: likely == null
                            ? 'Building forecast…'
                            : formatShortDate(likely),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: colors.ink,
                        ),
                        children: likely == null
                            ? null
                            : [
                                TextSpan(
                                  text: slipped && planned != null
                                      ? '  was ${formatShortDate(planned)}'
                                      : '  as planned',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: colors.inkDim,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
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
          if (timeline != null) ...[
            const SizedBox(height: 14),
            _ForecastTimeline(data: timeline, colors: colors),
          ] else if (earliest != null && latest != null) ...[
            const SizedBox(height: 8),
            Text(
              'Range ${formatShortDate(earliest)} – ${formatShortDate(latest)}',
              style: TextStyle(fontSize: 13, color: colors.inkDim),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            ),
            child: Text(
              slipped
                  ? 'Already updated after a trial moved.'
                  : 'Matches the course you activated. Updates only when a trial moves.',
              style: TextStyle(fontSize: 11.5, color: colors.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TlKind { start, done, next, ghost }

class _TlPoint {
  const _TlPoint({
    required this.day,
    required this.kind,
    required this.label,
    required this.sub,
    required this.above,
  });

  final int day;
  final _TlKind kind;
  final String label;
  final String sub;
  final bool above;
}

class _ForecastTimelineData {
  const _ForecastTimelineData({
    required this.span,
    required this.today,
    required this.points,
    this.bandFrom,
    this.bandTo,
    this.todayNearStart = false,
  });

  final int span;
  final int today;
  final List<_TlPoint> points;
  final int? bandFrom;
  final int? bandTo;

  /// When true, "Today" is folded into the start marker (no separate tick).
  final bool todayNearStart;

  static _ForecastTimelineData? fromProgram(
    Program program, {
    required DateTime now,
  }) {
    final start = _programStart(program);
    final likely = tryParseIsoDay(program.goalForecastLikelyIso ?? '');
    final earliest = tryParseIsoDay(program.goalForecastEarliestIso ?? '');
    final latest = tryParseIsoDay(program.goalForecastLatestIso ?? '');
    if (start == null) return null;

    final today = DateTime(now.year, now.month, now.day);
    var end = latest ?? likely ?? today.add(const Duration(days: 14));
    for (final m in program.milestones) {
      for (final iso in [m.forecastDateIso, m.plannedDateIso, m.passedAtIso]) {
        if (iso == null) continue;
        final d = tryParseIsoDay(iso);
        if (d != null && d.isAfter(end)) end = d;
      }
    }
    if (today.isAfter(end)) end = today;

    // Keep at least ~3 weeks of span so early-program timelines aren't cramped.
    final minEnd = start.add(const Duration(days: 21));
    if (end.isBefore(minEnd)) end = minEnd;

    final span = end.difference(start).inDays.clamp(1, 365);
    int dayOf(DateTime d) => d.difference(start).inDays.clamp(0, span);
    final todayDay = dayOf(today);
    final todayNearStart = todayDay <= 1;

    final points = <_TlPoint>[
      _TlPoint(
        day: 0,
        kind: _TlKind.start,
        label: formatShortDate(_isoFromDate(start)),
        sub: todayNearStart ? 'today' : 'start',
        above: false,
      ),
    ];

    // Passed milestones — use passedAt when available; skip if on start day.
    for (final m in program.milestones) {
      if (m.status != MilestoneStatus.passed) continue;
      final when = tryParseIsoDay(m.passedAtIso ?? m.forecastDateIso);
      if (when == null) continue;
      final day = dayOf(when);
      if (day <= 1) continue;
      points.add(
        _TlPoint(
          day: day,
          kind: _TlKind.done,
          label: formatShortDate(m.passedAtIso ?? m.forecastDateIso),
          sub: formatMeters(m.targetDistanceM),
          above: true,
        ),
      );
    }

    Milestone? nextOpen;
    for (final m in program.milestones) {
      if (m.status == MilestoneStatus.passed) continue;
      nextOpen = m;
      break;
    }

    if (nextOpen != null) {
      final forecast = tryParseIsoDay(nextOpen.forecastDateIso);
      final planned = tryParseIsoDay(nextOpen.plannedDateIso);
      if (planned != null &&
          forecast != null &&
          planned != forecast &&
          (forecast.difference(planned).inDays).abs() >= 4) {
        points.add(
          _TlPoint(
            day: dayOf(planned),
            kind: _TlKind.ghost,
            label: formatShortDate(nextOpen.plannedDateIso),
            sub: formatMeters(nextOpen.targetDistanceM),
            above: true,
          ),
        );
      }
      if (forecast != null) {
        points.add(
          _TlPoint(
            day: dayOf(forecast),
            kind: _TlKind.next,
            label: formatShortDate(nextOpen.forecastDateIso),
            sub: formatMeters(nextOpen.targetDistanceM),
            above: true,
          ),
        );
      }
    }

    // Goal likely only when clearly after the next trial.
    if (likely != null && nextOpen != null) {
      final nextDay = dayOf(tryParseIsoDay(nextOpen.forecastDateIso) ?? likely);
      final goalDay = dayOf(likely);
      if (goalDay - nextDay >= 4) {
        points.add(
          _TlPoint(
            day: goalDay,
            kind: _TlKind.next,
            label: formatShortDate(program.goalForecastLikelyIso!),
            sub: 'goal',
            above: true,
          ),
        );
      }
    }

    points.sort((a, b) => a.day.compareTo(b.day));

    int? bandFrom;
    int? bandTo;
    if (earliest != null && latest != null && earliest != latest) {
      bandFrom = dayOf(earliest);
      bandTo = dayOf(latest);
    }

    return _ForecastTimelineData(
      span: span,
      today: todayDay,
      points: points,
      bandFrom: bandFrom,
      bandTo: bandTo,
      todayNearStart: todayNearStart,
    );
  }

  static DateTime? _programStart(Program program) {
    if (program.activatedAtMs != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(program.activatedAtMs!);
      return DateTime(t.year, t.month, t.day);
    }
    if (program.chores.isNotEmpty) {
      final sorted = [...program.chores]
        ..sort((a, b) => a.dayIso.compareTo(b.dayIso));
      return tryParseIsoDay(sorted.first.dayIso);
    }
    if (program.milestones.isNotEmpty) {
      return tryParseIsoDay(program.milestones.first.plannedDateIso);
    }
    return null;
  }

  static String _isoFromDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

/// Compact HTML-style forecast rail: labels above/below, no overlapping Stack text.
class _ForecastTimeline extends StatelessWidget {
  const _ForecastTimeline({required this.data, required this.colors});

  final _ForecastTimelineData data;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('programs-forecast-timeline'),
      height: 96,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // Inset so edge labels don't clip.
          const inset = 18.0;
          final usable = (w - inset * 2).clamp(1.0, w);
          double xOf(int day) =>
              inset + (day / data.span).clamp(0.0, 1.0) * usable;

          final above = data.points.where((p) => p.above).toList();
          final below = data.points.where((p) => !p.above).toList();
          final aboveXs = _spread(
            above.map((p) => xOf(p.day)).toList(),
            usable,
            inset,
            minGap: 56,
          );
          final belowXs = _spread(
            below.map((p) => xOf(p.day)).toList(),
            usable,
            inset,
            minGap: 56,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Above labels
              for (var i = 0; i < above.length; i++)
                Positioned(
                  left: aboveXs[i] - 28,
                  top: 0,
                  width: 56,
                  child: _TlLabel(point: above[i], colors: colors),
                ),
              // Rail
              Positioned(
                left: inset,
                right: inset,
                top: 44,
                child: Container(height: 2, color: colors.gaugeTrack),
              ),
              if (data.bandFrom != null && data.bandTo != null)
                Positioned(
                  left: xOf(data.bandFrom!),
                  top: 36,
                  width: (xOf(data.bandTo!) - xOf(data.bandFrom!))
                      .clamp(12.0, usable),
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: colors.accent.withValues(alpha: 0.14),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: inset,
                top: 44,
                width: (xOf(data.today) - inset).clamp(0.0, usable),
                child: Container(height: 2, color: colors.accent),
              ),
              // Dots on rail
              for (final p in data.points)
                Positioned(
                  left: xOf(p.day) - (p.kind == _TlKind.start ? 5 : 7),
                  top: p.kind == _TlKind.start ? 40 : 38,
                  child: _TlDot(kind: p.kind, colors: colors),
                ),
              // Today tick (only when not folded into start)
              if (!data.todayNearStart)
                Positioned(
                  left: xOf(data.today) - 0.75,
                  top: 28,
                  child: Column(
                    children: [
                      Text(
                        'TODAY',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(width: 1.5, height: 22, color: colors.ink),
                    ],
                  ),
                ),
              // Below labels
              for (var i = 0; i < below.length; i++)
                Positioned(
                  left: belowXs[i] - 28,
                  top: 58,
                  width: 56,
                  child: _TlLabel(point: below[i], colors: colors),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Nudge label centers apart so they don't sit on top of each other.
  static List<double> _spread(
    List<double> xs,
    double usable,
    double inset, {
    required double minGap,
  }) {
    if (xs.length <= 1) return List<double>.from(xs);
    final out = List<double>.from(xs);
    final order = List<int>.generate(xs.length, (i) => i)
      ..sort((a, b) => out[a].compareTo(out[b]));
    final maxX = inset + usable;
    for (var pass = 0; pass < 6; pass++) {
      for (var i = 1; i < order.length; i++) {
        final left = order[i - 1];
        final right = order[i];
        final gap = out[right] - out[left];
        if (gap >= minGap) continue;
        final push = (minGap - gap) / 2;
        out[left] = (out[left] - push).clamp(inset, maxX);
        out[right] = (out[right] + push).clamp(inset, maxX);
      }
    }
    return out;
  }
}

class _TlLabel extends StatelessWidget {
  const _TlLabel({required this.point, required this.colors});

  final _TlPoint point;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final ghost = point.kind == _TlKind.ghost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          point.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.15,
            color: ghost ? colors.inkFaint : colors.ink,
            decoration: ghost ? TextDecoration.lineThrough : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          point.sub,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            height: 1.15,
            color: colors.inkDim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TlDot extends StatelessWidget {
  const _TlDot({required this.kind, required this.colors});

  final _TlKind kind;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final start = kind == _TlKind.start;
    final size = start ? 10.0 : 14.0;
    late Color border;
    late Color fill;
    switch (kind) {
      case _TlKind.done:
        border = colors.accent;
        fill = colors.accent;
      case _TlKind.next:
        border = colors.accent;
        fill = colors.bgElev;
      case _TlKind.ghost:
        border = colors.inkFaint;
        fill = Colors.transparent;
      case _TlKind.start:
        border = colors.inkFaint;
        fill = colors.bgElev;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: start ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: start ? null : BorderRadius.circular(3),
        border: Border.all(color: border, width: 2),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.chore,
    required this.todayIso,
    required this.colors,
    required this.onOpen,
  });

  final ChoreSession chore;
  final String todayIso;
  final FathomColors colors;
  final VoidCallback onOpen;

  bool get _isToday => chore.dayIso == todayIso;

  bool get _isDone =>
      chore.state == ChoreState.doneSynced ||
      chore.state == ChoreState.doneManual ||
      chore.state == ChoreState.adjusted;

  @override
  Widget build(BuildContext context) {
    final title = formatCourseTitle(chore);
    final structure = formatCourseStructureLine(chore);
    final wu = sumPartMeters(chore.blocks, 'warmUp').clamp(1, 100000);
    final main = sumPartMeters(chore.blocks, 'main').clamp(1, 100000);
    final cd = sumPartMeters(chore.blocks, 'coolDown').clamp(1, 100000);
    final dayLabel = formatCourseDayTag(chore.dayIso).split(' · ').first;
    final layer = _isToday
        ? (_isDone ? 'Today’s course · done' : 'Today’s course · $dayLabel')
        : 'Next course · $dayLabel';
    final badge = _isDone
        ? (chore.state == ChoreState.doneSynced ? 'Synced' : 'Done')
        : (_isToday ? 'Due today' : 'Up next');
    final cta = _isDone
        ? 'Review course'
        : (_isToday ? 'Open today’s course' : 'Open next course');

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
                    LayerTag(layer),
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
                  color: _isDone
                      ? colors.up.withValues(alpha: 0.18)
                      : colors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
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
                backgroundColor: _isDone ? colors.bgElev : colors.accent,
                foregroundColor: _isDone ? colors.ink : colors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: _isDone
                      ? BorderSide(color: colors.line)
                      : BorderSide.none,
                ),
              ),
              child: Text(
                cta,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
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

String _localIsoDay(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
