import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/presentation/view/advanced_tools_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('swim dig-deeper defaults false on fresh prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GateAPrefs.swimDigDeeper), isNull);
    expect(prefs.getBool(GateAPrefs.swimDigDeeper) ?? false, isFalse);
  });

  testWidgets('Advanced host shows dig-deeper toggle and export tile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MaterialApp(
        home: AdvancedToolsScreen(prefs: prefs),
      ),
    );

    expect(find.byKey(const Key('swim-dig-deeper-toggle')), findsOneWidget);
    expect(find.byKey(const Key('advanced-export-tile')), findsOneWidget);
    expect(find.textContaining('Qwen'), findsNothing);
    expect(find.textContaining('Run reasoner'), findsNothing);

    await tester.tap(find.byKey(const Key('swim-dig-deeper-toggle')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(GateAPrefs.swimDigDeeper), isTrue);
  });
}
