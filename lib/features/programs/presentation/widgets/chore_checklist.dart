import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';

/// Warm-up / main / cool-down checklist for a chore session.
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
      ('warmUp', 'Warm-up', 0),
      ('main', 'Main set', 1),
      ('coolDown', 'Cool-down', 2),
    ];

    return Column(
      key: const Key('programs-chore-checklist'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (part, title, idx) in parts) ...[
          if ((groups[part] ?? const []).isNotEmpty) ...[
            InkWell(
              onTap: onToggleSeg == null ? null : () => onToggleSeg!(idx),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      (segDone != null &&
                              idx < segDone!.length &&
                              segDone![idx])
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: (segDone != null &&
                              idx < segDone!.length &&
                              segDone![idx])
                          ? colors.accent
                          : colors.inkFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Text(
                      '${_sumM(groups[part]!)} m',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.inkDim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final b in groups[part]!)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 6),
                child: Text(
                  '${b.label} · ${b.distanceM} m'
                  '${b.restGuidanceSec != null ? ' · rest ${b.restGuidanceSec}s' : ''}',
                  style: TextStyle(fontSize: 13, color: colors.inkDim),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }

  int _sumM(List<ChoreBlock> blocks) =>
      blocks.fold<int>(0, (s, b) => s + b.distanceM);
}
