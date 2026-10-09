import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';
import 'package:fitness_os/features/programs/presentation/widgets/scorecard_row.dart';

/// Odyssey: Areté / Depth / Streak (when game layer on) + three scorecards.
class ProgramsProgressScreen extends StatelessWidget {
  const ProgramsProgressScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final ledger = controller.ledger;
    final hideGame = controller.hideGameLayer;
    final cards = controller.scorecards;
    final bronze = agonBronzeOf(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Odyssey',
        subtitle: hideGame ? 'Scorecards' : 'Areté · Depth · Streak',
        showPoolPill: false,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!hideGame) ...[
            AgonCard(
              key: const Key('programs-game-layer'),
              radius: 22,
              borderColor: Color.lerp(bronze, colors.line, 0.68),
              background: Color.lerp(bronze, colors.bgElev, 0.88),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THE ODYSSEY',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w500,
                      color: Color.lerp(bronze, colors.ink, 0.1),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Depth',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.inkDim,
                              ),
                            ),
                            Text(
                              '${ledger.level}',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -2.5,
                                height: 0.95,
                                color: Color.lerp(bronze, colors.ink, 0.15),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Areté',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.inkDim,
                            ),
                          ),
                          Text(
                            formatMeters(ledger.totalXp),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: colors.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            'progress points',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.bgElev,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Color.lerp(bronze, colors.line, 0.68)!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Streak',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${ledger.currentStreakWeeks} wk'
                          '${ledger.bestStreakWeeks > 0 ? ' · best ${ledger.bestStreakWeeks}' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          const LayerTag('Scorecards'),
          const SizedBox(height: 10),
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
