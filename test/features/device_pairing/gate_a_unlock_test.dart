import 'dart:io';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubLink extends HuaweiLink {
  _StubLink() : super();

  LinkState forced = LinkState.gateAIncomplete;

  @override
  LinkState get state => forced;

  @override
  Future<void> start() async {}

  @override
  Future<void> clearSecrets() async {}

  @override
  Future<void> disconnect() async {
    forced = LinkState.disconnected;
  }

  @override
  void markGateAPassed() {
    forced = LinkState.connected;
  }
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportRoot, this.tempRoot);

  final Directory supportRoot;
  final Directory tempRoot;

  @override
  Future<String?> getApplicationSupportPath() async => supportRoot.path;

  @override
  Future<String?> getTemporaryPath() async => tempRoot.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportRoot;
  late Directory tempRoot;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    supportRoot = await Directory.systemTemp.createTemp('gate_a_support_');
    tempRoot = await Directory.systemTemp.createTemp('gate_a_temp_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(supportRoot, tempRoot);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    for (final d in [supportRoot, tempRoot]) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('Gate A unlock only when all three interrupt bits set', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final link = _StubLink();
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    var status = await repo.creditInterrupt(
      interrupt: GateAInterrupt.kill,
      reachedAuthenticated: true,
    );
    expect(status.getOrThrow().passed, isFalse);

    status = await repo.creditInterrupt(
      interrupt: GateAInterrupt.reboot,
      reachedAuthenticated: true,
    );
    expect(status.getOrThrow().passed, isFalse);

    status = await repo.creditInterrupt(
      interrupt: GateAInterrupt.btToggle,
      reachedAuthenticated: true,
    );
    expect(status.getOrThrow().passed, isTrue);
    expect(prefs.getBool(GateAPrefs.gateAPassed), isTrue);
  });

  test('Forget clears five categories', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'GT5',
      GateAPrefs.gateAKillOk: true,
      GateAPrefs.gateARebootOk: true,
      GateAPrefs.gateABtToggleOk: true,
      GateAPrefs.gateAPassed: true,
      GateAPrefs.lastSyncCursor: '123',
      GateAPrefs.lastActivitySyncCursor: 456,
      GateAPrefs.activitySyncImplVersion: 1,
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _StubLink();
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    await repo.forgetDevice();
    expect(prefs.getString(GateAPrefs.rememberedMac), isNull);
    expect(prefs.getBool(GateAPrefs.gateAPassed), isNull);
    expect(prefs.getString(GateAPrefs.lastSyncCursor), isNull);
    expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), isNull);
    expect(prefs.getInt(GateAPrefs.activitySyncImplVersion), isNull);
  });

  test('Forget clears vitals keys via wipe callback and is idempotent', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.gateAPassed: true,
      GateAPrefs.sleepSessionsJson: '[{"beginUnix":1,"endUnix":2}]',
      GateAPrefs.dailyHrJson:
          '[{"dayKey":"2023-01-01","minBpm":1,"avgBpm":1,"maxBpm":1,"sampleCount":1}]',
      GateAPrefs.fitnessTotalsDayJson:
          '[{"dayKey":"2023-01-01","dayStartUnix":1,"calories":1,"steps":1,"exerciseDurationSec":1}]',
      GateAPrefs.workoutsJson:
          '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
      GateAPrefs.lastActivitySyncCursor: 999,
      GateAPrefs.activitySyncImplVersion: 1,
      GateAPrefs.leftoverKeepImplVersion: 1,
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _StubLink();
    var wipeCalls = 0;
    final repo = DevicePairingRepositoryImpl(
      link: link,
      prefs: prefs,
      onForgetWipeExtras: () async {
        wipeCalls++;
        await prefs.remove(GateAPrefs.sleepSessionsJson);
        await prefs.remove(GateAPrefs.dailyHrJson);
        await prefs.remove(GateAPrefs.fitnessTotalsDayJson);
      },
    );

    final first = await repo.forgetDevice();
    expect(first.isRight, isTrue);
    expect(wipeCalls, 1);
    expect(prefs.getString(GateAPrefs.sleepSessionsJson), isNull);
    expect(prefs.getString(GateAPrefs.dailyHrJson), isNull);
    expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), isNull);
    expect(prefs.getString(GateAPrefs.workoutsJson), isNull);
    expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), isNull);
    expect(prefs.getInt(GateAPrefs.activitySyncImplVersion), isNull);
    expect(prefs.getInt(GateAPrefs.leftoverKeepImplVersion), isNull);

    final second = await repo.forgetDevice();
    expect(second.isRight, isTrue);
    expect(wipeCalls, 2);
  });

  test('Forget verify fails when fitness totals residue remains', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.gateAPassed: true,
      GateAPrefs.fitnessTotalsDayJson:
          '[{"dayKey":"2023-01-01","dayStartUnix":1,"calories":1,"steps":1,"exerciseDurationSec":1}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = DevicePairingRepositoryImpl(
      link: _StubLink(),
      prefs: prefs,
      onForgetWipeExtras: () async {
        // Intentionally leave fitness totals — verify must catch residue.
      },
    );

    final out = await repo.forgetDevice();
    expect(out.isLeft, isTrue);
    expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), isNotNull);
  });

  test('Forget verify fails closed when leftover files remain', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.gateAPassed: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final leftover = File(
      '${supportRoot.path}/${GateAPrefs.workoutLeftoversDir}/34.bin',
    );
    await leftover.parent.create(recursive: true);
    await leftover.writeAsBytes([1, 2, 3]);

    final repo = DevicePairingRepositoryImpl(
      link: _StubLink(),
      prefs: prefs,
      onForgetWipeExtras: () async {
        // Intentionally leave leftover files — verify must catch residue.
      },
    );

    final out = await repo.forgetDevice();
    expect(out.isLeft, isTrue);
    expect(await leftover.exists(), isTrue);
  });

  test('Forget verify fails closed when share_plus residue remains', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.gateAPassed: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final share = File('${tempRoot.path}/share_plus/leaked.json');
    await share.parent.create(recursive: true);
    await share.writeAsString('prove');

    final repo = DevicePairingRepositoryImpl(
      link: _StubLink(),
      prefs: prefs,
      onForgetWipeExtras: () async {},
    );

    final out = await repo.forgetDevice();
    expect(out.isLeft, isTrue);
    expect(await share.exists(), isTrue);
  });
}

extension<L, R> on Either<L, R> {
  R getOrThrow() => fold((l) => throw Exception(l), (r) => r);
}
