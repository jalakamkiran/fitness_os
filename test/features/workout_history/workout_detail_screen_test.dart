import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory(
      'build/strength_export_ui_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  WorkoutSummary strengthWorkout({int number = 34}) {
    return WorkoutSummary(
      number: number,
      startTime: 1723400000,
      endTime: 1723402850,
      durationSec: 2850,
      type: 140,
      calories: 220,
      hrMin: 90,
      hrMax: 150,
    );
  }

  WorkoutSummary runWorkout() {
    return const WorkoutSummary(
      number: 35,
      startTime: 1723000000,
      endTime: 1723000433,
      durationSec: 433,
      type: 5,
      distanceM: 1000,
      calories: 80,
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required WorkoutSummary workout,
    Future<StrengthSessionExportResult> Function(int workoutNumber)?
        exportOverride,
    bool Function()? exportBusyOverride,
    Future<void> Function(File file)? shareExport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: WorkoutDetailScreen(
          workout: workout,
          exportOverride: exportOverride,
          exportBusyOverride: exportBusyOverride ?? () => false,
          shareExport: shareExport,
        ),
        routes: {
          '/coach_settings': (_) => const CoachSettingsScreen(
                isQwenInstalledOverride: _alwaysFalse,
              ),
        },
      ),
    );
    await tester.pump();
  }

  testWidgets('AE4: confirm → one session dump; cancel → no file',
      (tester) async {
    var exportCalls = 0;
    var shareCalls = 0;
    File? shared;

    final file = File(
      '${tempDir.path}/${StrengthSessionExportService.exportCacheDirName}/'
      'strength_session_34_test.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"schemaVersion":1,"sessions":[{"number":34}]}');

    await pumpDetail(
      tester,
      workout: strengthWorkout(),
      exportOverride: (n) async {
        exportCalls++;
        expect(n, 34);
        return StrengthSessionExportResult.success(
          file: file,
          byteLength: file.lengthSync(),
        );
      },
      shareExport: (f) async {
        shareCalls++;
        shared = f;
      },
    );

    expect(find.byTooltip('Export this session'), findsOneWidget);
    expect(find.byTooltip('Reasoner settings'), findsNothing);
    expect(find.textContaining('Recovery'), findsNothing);
    expect(find.textContaining('recovery %'), findsNothing);

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();
    expect(find.text('Export this session?'), findsOneWidget);
    expect(find.textContaining('leftover Totals bytes'), findsOneWidget);
    expect(find.textContaining('HR sample'), findsOneWidget);
    expect(find.textContaining('recovery-HR'), findsOneWidget);
    expect(find.textContaining('recipients may keep copies'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(exportCalls, 0);
    expect(shareCalls, 0);

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();
    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(exportCalls, 1);
    expect(shareCalls, 1);
    expect(shared!.path, file.path);
    expect(
      shared!.path.contains(
        '/${StrengthSessionExportService.exportCacheDirName}/',
      ),
      isTrue,
    );
  });

  testWidgets('CTA does not navigate to Coach Settings / Reasoner',
      (tester) async {
    await pumpDetail(
      tester,
      workout: strengthWorkout(),
      exportOverride: (_) async =>
          const StrengthSessionExportResult.failed('should not run'),
    );

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();
    expect(find.text('Export this session?'), findsOneWidget);
    expect(find.text('Reasoner settings'), findsNothing);
    expect(find.byType(CoachSettingsScreen), findsNothing);
  });

  testWidgets('two sessions: detail CTA dumps opened number only',
      (tester) async {
    final exported = <int>[];
    final file = File(
      '${tempDir.path}/${StrengthSessionExportService.exportCacheDirName}/one.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{}');

    await pumpDetail(
      tester,
      workout: strengthWorkout(number: 99),
      exportOverride: (n) async {
        exported.add(n);
        return StrengthSessionExportResult.success(file: file, byteLength: 2);
      },
      shareExport: (_) async {},
    );

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();
    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(exported, [99]);
  });

  testWidgets('service blocked → status message; no share', (tester) async {
    var shareCalls = 0;
    await pumpDetail(
      tester,
      workout: strengthWorkout(),
      exportBusyOverride: () => true,
      shareExport: (_) async => shareCalls++,
    );

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();

    expect(find.textContaining('Export blocked'), findsOneWidget);
    expect(find.text('Export this session?'), findsNothing);
    expect(shareCalls, 0);
  });

  testWidgets('service failure → error status; no share', (tester) async {
    var shareCalls = 0;
    await pumpDetail(
      tester,
      workout: strengthWorkout(),
      exportOverride: (_) async => const StrengthSessionExportResult.failed(
        'Session no longer on this device',
      ),
      shareExport: (_) async => shareCalls++,
    );

    await tester.tap(find.byTooltip('Export this session'));
    await tester.pump();
    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('no longer on this device'), findsOneWidget);
    expect(shareCalls, 0);
  });

  testWidgets('swim/run keep Reasoner settings action', (tester) async {
    // Use run (not swim) so diagnoses/reasoner loaders do not require GetIt.
    await pumpDetail(tester, workout: runWorkout());

    expect(find.byTooltip('Reasoner settings'), findsOneWidget);
    expect(find.byTooltip('Export this session'), findsNothing);
  });
}

Future<bool> _alwaysFalse() async => false;
