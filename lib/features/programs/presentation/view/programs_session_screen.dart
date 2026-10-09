import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';
import 'package:fitness_os/features/programs/presentation/widgets/chore_checklist.dart';

/// Today’s course: WU / main / CD segment cards + Mark session done / Skip.
class ProgramsSessionScreen extends StatefulWidget {
  const ProgramsSessionScreen({
    super.key,
    required this.controller,
    required this.choreId,
  });

  final ProgramsController controller;
  final String choreId;

  @override
  State<ProgramsSessionScreen> createState() => _ProgramsSessionScreenState();
}

class _ProgramsSessionScreenState extends State<ProgramsSessionScreen> {
  final List<bool> _segDone = [false, false, false];
  bool _preLandDone = false;
  bool _postLandDone = false;
  bool _busy = false;

  ChoreSession? get _chore => widget.controller.choreById(widget.choreId);

  Future<void> _done() async {
    setState(() => _busy = true);
    await widget.controller.markChoreDone(widget.choreId);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  Future<void> _skip(SkipReason reason) async {
    setState(() => _busy = true);
    await widget.controller.skipChore(widget.choreId, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  void _showSkipSheet() {
    final colors = FathomColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final chips = <(SkipReason, String, String)>[
          (SkipReason.recovery, 'Recovery / other load', 'Counts as rest'),
          (SkipReason.ill, 'Ill', 'Counts as rest'),
          (SkipReason.travel, 'Travel', 'Counts as rest'),
          (SkipReason.poolClosed, 'Pool closed', 'Counts as rest'),
          (SkipReason.other, 'Something else', 'No effect on your dates'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.ink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Skip today',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'What’s getting in the way?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                for (final (reason, title, sub) in chips) ...[
                  OutlinedButton(
                    key: Key('programs-skip-${reason.name}'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _skip(reason);
                    },
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.inkDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                const SizedBox(height: 4),
                Text(
                  'Skipping never moves your dates.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.inkDim,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAdjustSheet() {
    final colors = FathomColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Adjust today',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Make it fit',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Shorter or easier options still count as done. Dates stay put.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.inkDim,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _done();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.accentInk,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Mark shorter session done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final chore = _chore;
    if (chore == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AgonAppHeader(
          title: 'Agon · Pool',
          subtitle: 'Course',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: const Center(child: Text('Course not found.')),
      );
    }

    final open = chore.state == ChoreState.scheduled ||
        chore.state == ChoreState.due ||
        chore.state == ChoreState.lapsed;
    final title = formatCourseTitle(chore);
    final sub = formatMainSetSummary(chore);
    final dayTag = formatCourseDayTag(chore.dayIso);
    final segDone = open ? _segDone : const [true, true, true];
    final preLandDone = open ? _preLandDone : true;
    final postLandDone = open ? _postLandDone : true;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Agon · Pool',
        subtitle: '${formatMeters(chore.targetDistanceM)} m course',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                LayerTag(dayTag),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.inkDim,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                AgonCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Kpi(
                              label: 'Distance',
                              value: '${formatMeters(chore.targetDistanceM)} m',
                              colors: colors,
                            ),
                          ),
                          Expanded(
                            child: _Kpi(
                              label: 'Est.',
                              value: '~',
                              colors: colors,
                            ),
                          ),
                          Expanded(
                            child: _Kpi(
                              label: 'Volume',
                              value: 'broken',
                              note: 'with rest',
                              colors: colors,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Not a continuous swim — warm-up, main with rests, cool-down',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _LandBlock(
                  title: 'Before you swim',
                  subtitle: 'Land · 3–5 min',
                  lines: const [
                    'Arm circles + scap squeezes',
                    'Hip openers / world’s greatest',
                    'Ankle rocks · easy breathing',
                  ],
                  done: preLandDone,
                  onToggle: open
                      ? () => setState(() => _preLandDone = !_preLandDone)
                      : null,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                ChoreChecklist(
                  chore: chore,
                  segDone: segDone,
                  onToggleSeg: open
                      ? (i) {
                          setState(() => _segDone[i] = !_segDone[i]);
                        }
                      : null,
                ),
                _LandBlock(
                  title: 'After you swim',
                  subtitle: 'Land · stretch as needed',
                  lines: const [
                    'Easy pec / lat stretch',
                    'Hip flexor + calf',
                    'Slow nasal breaths · 1–2 min',
                  ],
                  done: postLandDone,
                  onToggle: open
                      ? () => setState(() => _postLandDone = !_postLandDone)
                      : null,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                if (chore.focusLine != null &&
                    chore.focusLine!.trim().isNotEmpty) ...[
                  AgonCard(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Why this set: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: colors.ink,
                              height: 1.45,
                            ),
                          ),
                          TextSpan(
                            text: chore.focusLine!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.inkDim,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!open) ...[
                  AgonCard(
                    key: const Key('programs-chore-receipt'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chore.state == ChoreState.doneSynced
                              ? 'Course synced'
                              : chore.state == ChoreState.doneManual ||
                                      chore.state == ChoreState.adjusted
                                  ? 'Course marked done'
                                  : 'Course closed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          chore.matchedWorkoutNumber != null
                              ? 'Matched pool swim · #${chore.matchedWorkoutNumber}'
                                  '${chore.judgedDistanceM != null ? ' · ${formatMeters(chore.judgedDistanceM!)} m' : ''}'
                              : 'This session is complete — no further action needed.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.inkDim,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 72),
              ],
            ),
          ),
          if (open)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.bg.withValues(alpha: 0), colors.bg],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('programs-chore-done'),
                        onPressed: _busy ? null : _done,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.accentInk,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Mark session done',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'You confirm this swim',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.accentInk.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _showAdjustSheet,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: colors.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Adjust',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: colors.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('programs-chore-skip'),
                            onPressed: _busy ? null : _showSkipSheet,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: colors.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: colors.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LandBlock extends StatelessWidget {
  const _LandBlock({
    required this.title,
    required this.subtitle,
    required this.lines,
    required this.done,
    required this.onToggle,
    required this.colors,
  });

  final String title;
  final String subtitle;
  final List<String> lines;
  final bool done;
  final VoidCallback? onToggle;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.bgElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.line,
          style: BorderStyle.solid,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LandCheck(done: done, colors: colors),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: colors.ink,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colors.inkFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(left: 36, bottom: 4),
                  child: Text(
                    '· $line',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: colors.inkDim,
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

class _LandCheck extends StatelessWidget {
  const _LandCheck({required this.done, required this.colors});

  final bool done;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.accent : colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done ? colors.accent : colors.ink.withValues(alpha: 0.14),
          width: 1.8,
        ),
      ),
      child: done
          ? Icon(Icons.check, size: 14, color: colors.accentInk)
          : const SizedBox.shrink(),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.colors,
    this.note,
  });

  final String label;
  final String value;
  final String? note;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: colors.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: colors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (note != null)
          Text(
            note!,
            style: TextStyle(
              fontSize: 11,
              color: colors.inkDim,
            ),
          ),
      ],
    );
  }
}
