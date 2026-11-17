import 'package:flutter/material.dart';
import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/presentation/controller/lift_session_controller.dart';
import 'package:fitness_os/features/lift/presentation/view/lift_live_screen.dart';

class LiftHomeScreen extends StatelessWidget {
  const LiftHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.liftWatch) {
      return const Scaffold(body: Center(child: Text('Lift beta disabled')));
    }
    final debugSession = PlannedSession(
      sessionId: PlannedSession.newSessionId(),
      title: 'Debug lift',
      plannedFor: DateTime.now(),
      source: 'debug',
      exercises: [
        PlannedExercise(
          exerciseId: 'bench',
          name: 'Bench press',
          sets: 2,
          targetKg: 60,
          targetReps: 8,
          restSec: 120,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Lift (beta)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(debugSession.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${debugSession.exercises.length} exercises · local debug plan'),
            const Spacer(),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LiftLiveScreen(
                      session: debugSession,
                      controller: sl<LiftSessionController>(),
                    ),
                  ),
                );
              },
              child: const Text('Start session'),
            ),
          ],
        ),
      ),
    );
  }
}