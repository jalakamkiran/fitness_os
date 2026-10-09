import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/week_adherence.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_navigation.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_route.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';

/// Where Agon content sits in the Home stack.
enum HomeAgonSlot {
  /// Active Agon hybrid hero (progress + CTA). Idle → empty.
  hero,

  /// Idle Odyssey snapshot/upsell, or active week-adherence dots.
  afterSessions,
}

/// Bridges [ProgramsController] into Home without hub hops.
class HomeAgonSlotView extends StatefulWidget {
  const HomeAgonSlotView({
    super.key,
    required this.slot,
    this.now,
  });

  final HomeAgonSlot slot;
  final DateTime Function()? now;

  @override
  State<HomeAgonSlotView> createState() => _HomeAgonSlotViewState();
}

class _HomeAgonSlotViewState extends State<HomeAgonSlotView> {
  ProgramsController? _controller;

  @override
  void initState() {
    super.initState();
    if (GetIt.I.isRegistered<ProgramsController>()) {
      _controller = GetIt.I<ProgramsController>();
      _controller!.addListener(_onChanged);
      if (_controller!.active == null) {
        // ignore: discarded_futures
        _controller!.load();
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    switch (widget.slot) {
      case HomeAgonSlot.hero:
        if (!c.hasActive || c.active == null) {
          return const SizedBox.shrink();
        }
        return _HybridHero(
          controller: c,
          now: _now,
        );
      case HomeAgonSlot.afterSessions:
        if (c.hasActive && c.active != null) {
          final slots = HomeAgonDay.weekAdherenceSlots(c.active!, now: _now);
          if (slots.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _WeekAdherenceCard(
              slots: slots,
              onOpenProgress: () => ProgramsNavigation.openOdyssey(
                context,
                controller: c,
              ),
            ),
          );
        }
        if (HomeAgonDay.hasOdysseySnapshot(c.ledger)) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _OdysseyIdleCard(
              snapshot: true,
              controller: c,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _OdysseyIdleCard(
            snapshot: false,
            controller: c,
          ),
        );
    }
  }
}

class _HybridHero extends StatelessWidget {
  const _HybridHero({
    required this.controller,
    required this.now,
  });

  final ProgramsController controller;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final bronze = agonBronzeOf(context);
    final program = controller.active!;
    final today = HomeAgonDay.classifyHomeToday(program, now: now);
    final hideGame = controller.hideGameLayer;
    final ledger = controller.ledger;

    return Container(
      key: const Key('home-hybrid-hero'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Color.lerp(bronze, colors.line, 0.55)!,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(bronze, colors.bgElev, 0.82)!,
            colors.bgElev,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideGame) ...[
            // Progress strip → full Odyssey; primary CTA below stays session/proof.
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('home-progress-strip'),
                onTap: () => ProgramsNavigation.openOdyssey(
                  context,
                  controller: controller,
                ),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ProgressPill(
                        label: 'Streak · ${ledger.currentStreakWeeks} wk',
                        bronze: bronze,
                        colors: colors,
                      ),
                      _ProgressPill(
                        label: 'Areté · ${formatMeters(ledger.totalXp)}',
                        bronze: bronze,
                        colors: colors,
                      ),
                      _ProgressPill(
                        label: 'Depth · L${ledger.level}',
                        bronze: bronze,
                        colors: colors,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (today.kind == HomeTodayKind.choreOpen && today.chore != null)
            _PrimaryCourseCta(
              chore: today.chore!,
              onTap: () => ProgramsNavigation.openSession(
                context,
                controller: controller,
                choreId: today.chore!.id,
              ),
            )
          else if (today.kind == HomeTodayKind.proofOpen && today.chore != null)
            _PrimaryCourseCta(
              chore: today.chore!,
              kicker: 'Today’s trial',
              onTap: () => ProgramsNavigation.openProof(
                context,
                controller: controller,
                milestoneId: today.chore!.milestoneId,
                fallbackChoreId: today.chore!.id,
              ),
            )
          else if (today.kind == HomeTodayKind.done && today.chore != null)
            _ReceiptCta(
              chore: today.chore!,
              onTap: () => ProgramsNavigation.openSession(
                context,
                controller: controller,
                choreId: today.chore!.id,
              ),
            ),
          // Rest: strip + hub CTA (no session primary).
          if (today.kind == HomeTodayKind.choreOpen ||
              today.kind == HomeTodayKind.proofOpen ||
              today.kind == HomeTodayKind.done)
            const SizedBox(height: 10),
          _AgonHubCta(program: program, now: now),
        ],
      ),
    );
  }
}

/// Secondary entry to the Agon hub (milestones, forecast) — not a shell tab.
class _AgonHubCta extends StatelessWidget {
  const _AgonHubCta({required this.program, required this.now});

  final Program program;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final bronze = agonBronzeOf(context);
    final goal = formatGoalLine(program.intake);
    final week = formatWeekChip(program, now);

    return Material(
      color: Color.lerp(bronze, colors.bg, 0.88),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('home-programs-cta'),
        onTap: () => ProgramsRoute.go(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.lerp(bronze, colors.line, 0.5)!,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agon plan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$week · $goal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Open',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: bronze,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: bronze, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({
    required this.label,
    required this.bronze,
    required this.colors,
  });

  final String label;
  final Color bronze;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Color.lerp(bronze, colors.bg, 0.78),
        border: Border.all(color: Color.lerp(bronze, colors.line, 0.45)!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: bronze, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCourseCta extends StatelessWidget {
  const _PrimaryCourseCta({
    required this.chore,
    required this.onTap,
    this.kicker = 'Today’s course',
  });

  final ChoreSession chore;
  final VoidCallback onTap;
  final String kicker;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('home-chore-cta'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.06 * 11,
                  color: colors.accentInk.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatCourseTitle(chore),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: colors.accentInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatCourseStructureLine(chore),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.accentInk.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptCta extends StatelessWidget {
  const _ReceiptCta({
    required this.chore,
    required this.onTap,
  });

  final ChoreSession chore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Material(
      color: colors.bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('home-chore-receipt'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Course done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCourseTitle(chore),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Review',
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
}

class _OdysseyIdleCard extends StatelessWidget {
  const _OdysseyIdleCard({
    required this.snapshot,
    required this.controller,
  });

  final bool snapshot;
  final ProgramsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final bronze = agonBronzeOf(context);
    final ledger = controller.ledger;

    return Material(
      color: Color.lerp(colors.accent, colors.bgElev, 0.9),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key(snapshot ? 'home-odyssey-snapshot' : 'home-odyssey-upsell'),
        onTap: () {
          if (snapshot) {
            ProgramsNavigation.openOdyssey(context, controller: controller);
          } else {
            ProgramsNavigation.openCreate(context, controller: controller);
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Color.lerp(colors.accent, colors.line, 0.55)!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot ? 'Odyssey · last voyage' : 'Begin an Odyssey',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                snapshot
                    ? 'Depth L${ledger.level} · Streak ${ledger.currentStreakWeeks} wk. Sleep and sessions still lead the day.'
                    : 'Chart a pool Agon toward a proof swim. Habit rewards stay forgiving; dates stay honest.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.inkDim,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Color.lerp(colors.accent, colors.line, 0.4)!,
                  ),
                  color: colors.bgElev,
                ),
                child: Text(
                  snapshot ? 'Open Odyssey' : 'Create Agon',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: bronze,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekAdherenceCard extends StatelessWidget {
  const _WeekAdherenceCard({
    required this.slots,
    required this.onOpenProgress,
  });

  final List<WeekAdherenceSlot> slots;
  final VoidCallback onOpenProgress;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final done = slots.where((s) => s.done).length;

    return Material(
      color: colors.bgElev,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('home-week-adherence'),
        onTap: onOpenProgress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Plan adherence',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$done / ${slots.length} sessions',
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.inkDim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final slot in slots)
                    Expanded(
                      child: _AdherenceDot(slot: slot, colors: colors),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdherenceDot extends StatelessWidget {
  const _AdherenceDot({required this.slot, required this.colors});

  final WeekAdherenceSlot slot;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final label = _weekdayLabel(slot.dayIso);
    final border = slot.isToday
        ? colors.amber
        : slot.done
            ? colors.accent
            : colors.line;
    final bg = slot.done
        ? Color.lerp(colors.accent, colors.bg, 0.82)!
        : colors.bg;

    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: Border.all(color: border, width: slot.isToday ? 2.5 : 2),
            boxShadow: slot.isToday
                ? [
                    BoxShadow(
                      color: colors.amber.withValues(alpha: 0.25),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Text(
            slot.done ? '✓' : '·',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: slot.done ? colors.accentInk : colors.inkFaint,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.inkFaint,
          ),
        ),
      ],
    );
  }

  String _weekdayLabel(String dayIso) {
    final parts = dayIso.split('-');
    if (parts.length != 3) return '·';
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return '·';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dt = DateTime(y, m, d);
    return names[dt.weekday - 1];
  }
}
