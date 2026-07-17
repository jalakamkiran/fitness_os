import 'dart:async';
import 'dart:typed_data';

import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel('fitness_os/huawei_bt');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAdapterState':
          return 'on';
        case 'checkPermissions':
          return true;
        case 'requestPermissions':
          return true;
        case 'lastSocketSecure':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, null);
  });

  test('connect then write invoke expected method args', () async {
    final channel = HuaweiBtChannel();

    await channel.connect(mac: 'AA:BB:CC:DD:EE:FF');
    expect(calls.last.method, 'connect');
    expect(calls.last.arguments['mac'], 'AA:BB:CC:DD:EE:FF');
    expect(
      calls.last.arguments['sdpUuid'],
      HuaweiBtChannel.huaweiSdpUuid,
    );

    final payload = Uint8List.fromList([0x5A, 0x01, 0x02]);
    await channel.writeDebug(payload);
    expect(calls.last.method, 'write');
    expect(calls.last.arguments['bytes'], payload);
  });

  test('event mapping round-trips data bytes', () {
    final payload = Uint8List.fromList([0x5A, 0x01, 0x02]);
    final event = HuaweiBtChannel.mapEventForTest({
      'type': 'data',
      'bytes': payload,
    });
    expect(event, isA<DataEvent>());
    expect((event as DataEvent).bytes, payload);
  });

  test('discovery event with GT5 name is surfaced; filter helper works', () {
    expect(
      HuaweiBtChannel.matchesGt5Name('HUAWEI Watch GT 5-A07'),
      isTrue,
    );
    expect(
      HuaweiBtChannel.matchesGt5Name('Galaxy Watch'),
      isFalse,
    );

    final event = HuaweiBtChannel.mapEventForTest({
      'type': 'discovery',
      'mac': 'AA:BB:CC:DD:EE:FF',
      'name': 'HUAWEI Watch GT 5-A07',
      'rssi': -50,
    });
    expect(event, isA<DiscoveryEvent>());
    expect(
      HuaweiBtChannel.matchesGt5Name((event as DiscoveryEvent).name),
      isTrue,
    );
  });

  test('permission denied maps to PlatformException code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
      if (call.method == 'startBleDiscovery') {
        throw PlatformException(
          code: 'permission_denied',
          message: 'Bluetooth permissions required',
        );
      }
      return null;
    });

    final channel = HuaweiBtChannel();
    expect(
      () => channel.startBleDiscovery(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'permission_denied',
        ),
      ),
    );
  });

  test('adapter off surfaces illegal_state from native', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
      if (call.method == 'connect') {
        throw PlatformException(
          code: 'illegal_state',
          message: 'Bluetooth adapter is off',
        );
      }
      return null;
    });

    final channel = HuaweiBtChannel();
    expect(
      () => channel.connect(mac: 'AA:BB:CC:DD:EE:FF'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'illegal_state',
        ),
      ),
    );
  });
}
