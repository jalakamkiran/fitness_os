import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';

/// Warm-up / main / cool-down segment cards for today’s course.
class ChoreChecklist extends StatelessWidget {
  const ChoreChecklist({
    super.key,
    required this.chore,
    this.segDone,
    this.onToggleSeg,
  });

  final ChoreSession chore;

  /// Optional local checkmarks for WU/main/CD (UI-only until Done).
  final List<bool>? segDone;
  final ValueChanged<int>? onToggleSeg;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final groups = <String, List<ChoreBlock>>{
      'warmUp': [],
      'main': [],
      'coolDown': [],
    };
    for (final b in chore.blocks) {
      groups.putIfAbsent(b.part, () => []).add(b);
    }

    final parts = [
      ('warmUp', 'Warm-up', 0, false),
      ('main', 'Main set', 1, true),
      ('coolDown', 'Cool-down', 2, false),
    ];

    return Column(
      key: const Key('programs-chore-checklist'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (part, title, idx, isMain) in parts) ...[
          if ((groups[part] ?? const []).isNotEmpty) ...[
            _SegmentCard(
              title: title,
              blocks: groups[part]!,
              isMain: isMain,
              done: segDone != null &&
                  idx < segDone!.length &&
                  segDone![idx],
              onToggle: onToggleSeg == null ? null : () => onToggleSeg!(idx),
              colors: colors,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    required this.title,
    required this.blocks,
    required this.isMain,
    required this.done,
    required this.onToggle,
    required this.colors,
  });

  final String title;
  final List<ChoreBlock> blocks;
  final bool isMain;
  final bool done;
  final VoidCallback? onToggle;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final totalM = blocks.fold<int>(0, (s, b) => s + b.distanceM);
    final border = isMain
        ? Color.lerp(colors.accent, colors.line, 0.62)!
        : colors.line;
    final headBg = isMain
        ? Color.lerp(colors.accent, colors.bgElev, 0.91)!
        : colors.bgElev;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: headBg,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    _SegCheck(done: done, colors: colors, onTap: onToggle),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${formatMeters(totalM)} m',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '${blocks.length} set${blocks.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.inkFaint,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final b in blocks)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.ink.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      formatMeters(b.distanceM),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: colors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: colors.ink,
                          ),
                        ),
                        if (b.effortBand != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            b.effortBand!,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: colors.inkDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRestGuidance(b.restGuidanceSec),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.inkDim,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SegCheck extends StatelessWidget {
  const _SegCheck({
    required this.done,
    required this.colors,
    required this.onTap,
  });

  final bool done;
  final FathomColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
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
      ),
    );
  }
}
