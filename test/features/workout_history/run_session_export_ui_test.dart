import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';

WorkoutSummary _run({required int number, int type = 2}) {
  const start = 1700000000;
  return WorkoutSummary(
    number: number,
    startTime: start,
    endTime: start + 1800,
    durationSec: 1800,
    type: type,
    distanceM: 5000,
    observedType: type == 2 ? 2 : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late RunSessionStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fos_run_export_ui_');
    store = RunSessionStore(rootOverride: () => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  testWidgets('Run/Walk detail shows Export for AI for Walk, Indoor, Outdoor',
      (tester) async {
    Future<void> pumpType(int type) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: _run(number: 60, type: type),
            runSessionStore: store,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
            sessionExportOverride: () async =>
                const RunSessionExportResult.failed('unused'),
            sessionExportBusyOverride: () => false,
            shareSessionExport: (_) async {},
          ),
        ),
      );
      await tester.pump();
    }

    await pumpType(2);
    expect(find.byTooltip('Export for AI'), findsOneWidget);

    await pumpType(1);
    expect(find.byTooltip('Export for AI'), findsOneWidget);

    await pumpType(5);
    expect(find.byTooltip('Export for AI'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutDetailScreen(
          workout: _run(number: 34, type: 140),
          runSessionStore: store,
          preloadedPaceSplits: const [],
          preloadedStreamPoints: const [],
          sessionExportOverride: () async =>
              const RunSessionExportResult.failed('unused'),
          sessionExportBusyOverride: () => false,
          shareSessionExport: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Export for AI'), findsNothing);
  });

  test('confirm identity lines match Outdoor session key fields', () {
    final workout = _run(number: 9);
    final lines = RunSessionExportService.confirmIdentityLines(workout);
    expect(lines, contains('Workout #9'));
    expect(lines, contains('Type: 2 (Run)'));
    expect(lines, contains('5000 m'));
    expect(lines, contains('30:00'));
  });
}
