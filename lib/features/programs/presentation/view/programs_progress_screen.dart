import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/widgets/scorecard_row.dart';

/// Progress: streak / XP / level (respect hideGameLayer) + three scorecards.
class ProgramsProgressScreen extends StatelessWidget {
  const ProgramsProgressScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final ledger = controller.ledger;
    final hideGame = controller.hideGameLayer;
    final cards = controller.scorecards;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Progress'),
        backgroundColor: colors.bg,
        foregroundColor: colors.ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!hideGame) ...[
            Container(
              key: const Key('programs-game-layer'),
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
                    'Streak ${ledger.currentStreakWeeks} wk'
                    '${ledger.bestStreakWeeks > 0 ? ' · best ${ledger.bestStreakWeeks}' : ''}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Level ${ledger.level} · ${ledger.totalXp} XP',
                    style: TextStyle(fontSize: 14, color: colors.inkDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (cards != null)
            ScorecardRow(bundle: cards)
          else
            Text(
              'Scorecards appear after sessions land.',
              style: TextStyle(color: colors.inkDim, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
