import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/features/lift/data/lift_watch_bridge.dart';
import 'package:fitness_os/features/lift/presentation/view/lift_debug_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel('fitness_os/huawei_bt');

  setUp(() {
    LiftDebugScreen.debugForceEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
      switch (call.method) {
        case 'liftConfigure':
        case 'liftCapabilities':
        case 'liftSendTestNotification':
        case 'liftQueryQuickReplies':
        case 'liftSetQuickReplies':
        case 'liftRemove':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    LiftDebugScreen.debugForceEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, null);
  });

  testWidgets('renders without throw when watch disconnected (fake bridge)',
      (tester) async {
    final bridge = LiftWatchBridge(
      HuaweiBtChannel(),
      events: const Stream<HuaweiBtEvent>.empty(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LiftDebugScreen(bridge: bridge),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Lift watch debug'), findsOneWidget);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}