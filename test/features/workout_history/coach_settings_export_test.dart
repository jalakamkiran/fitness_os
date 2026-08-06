import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/diagnostics/data/app_data_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory('build/export_ui_test_${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<AppDataExportResult> Function()? exportOverride,
    bool Function()? exportBusyOverride,
    Future<void> Function(File file)? shareExport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CoachSettingsScreen(
          exportOverride: exportOverride,
          exportBusyOverride: exportBusyOverride ?? () => false,
          shareExport: shareExport,
          isQwenInstalledOverride: () async => false,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tap Export → confirm → share invoked once under export cache',
      (tester) async {
    var exportCalls = 0;
    var shareCalls = 0;
    File? shared;

    final file = File(
      '${tempDir.path}/${AppDataExportEnvelope.exportCacheDirName}/fitness_os_export_v1_test.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"schemaVersion":1}');

    await pumpScreen(
      tester,
      exportOverride: () async {
        exportCalls++;
        return AppDataExportResult.success(file: file, byteLength: 20);
      },
      shareExport: (f) async {
        shareCalls++;
        shared = f;
      },
    );

    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pump();
    expect(find.text('Export data?'), findsOneWidget);

    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(exportCalls, 1);
    expect(shareCalls, 1);
    expect(shared!.path, file.path);
    expect(
      shared!.path.contains('/${AppDataExportEnvelope.exportCacheDirName}/'),
      isTrue,
    );
  });

  testWidgets('confirm cancel → no assemble call', (tester) async {
    var exportCalls = 0;
    await pumpScreen(
      tester,
      exportOverride: () async {
        exportCalls++;
        return const AppDataExportResult.failed('should not run');
      },
    );

    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(exportCalls, 0);
  });

  testWidgets('service blocked → status message; no share', (tester) async {
    var shareCalls = 0;
    await pumpScreen(
      tester,
      exportBusyOverride: () => true,
      shareExport: (_) async => shareCalls++,
    );

    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pump();

    expect(find.textContaining('Export blocked'), findsOneWidget);
    expect(find.text('Export data?'), findsNothing);
    expect(shareCalls, 0);
  });

  testWidgets('service failure → error status; no share', (tester) async {
    var shareCalls = 0;
    await pumpScreen(
      tester,
      exportOverride: () async =>
          const AppDataExportResult.failed('Export write failed — disk'),
      shareExport: (_) async => shareCalls++,
    );

    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pump();
    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Export write failed'), findsOneWidget);
    expect(shareCalls, 0);
  });

  testWidgets('double-tap while busy → second export not started',
      (tester) async {
    var exportCalls = 0;
    await pumpScreen(
      tester,
      exportOverride: () async {
        exportCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final file = File('${tempDir.path}/exports/one.json');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('{}');
        return AppDataExportResult.success(file: file, byteLength: 2);
      },
      shareExport: (_) async {},
    );

    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pump();
    await tester.tap(find.text('Export').last);
    await tester.pump();
    await tester.tap(find.text('Export data'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 350));

    expect(exportCalls, 1);
  });

  testWidgets('Qwen download busy → Export disabled', (tester) async {
    await pumpScreen(
      tester,
      exportOverride: () async => const AppDataExportResult.failed('no'),
    );

    await tester.tap(find.textContaining('Download Qwen3'));
    await tester.pump();

    final tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Export data'));
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);

    // Clear fake-download timer so the binding can dispose cleanly.
    await tester.pump(const Duration(milliseconds: 30));
  });
}
