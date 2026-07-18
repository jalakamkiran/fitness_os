import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    final unlocked = status.getOrThrow();
    expect(unlocked.passed, isTrue);
    expect(prefs.getBool(GateAPrefs.gateAPassed), isTrue);
    expect(link.state, LinkState.connected);
  });

  test('reject interrupt credit after reconnect_failed only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final link = _StubLink()..forced = LinkState.reconnectFailed;
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    final result = await repo.creditInterrupt(
      interrupt: GateAInterrupt.kill,
      reachedAuthenticated: false,
    );
    expect(result.isLeft, isTrue);
    expect(prefs.getBool(GateAPrefs.gateAKillOk) ?? false, isFalse);
  });

  test('Forget clears five categories', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'GT5',
      GateAPrefs.gateAKillOk: true,
      GateAPrefs.gateARebootOk: true,
      GateAPrefs.gateABtToggleOk: true,
      GateAPrefs.gateAPassed: true,
      GateAPrefs.lastSyncCursor: 'cursor',
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _StubLink();
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    await repo.forgetDevice();
    expect(prefs.getString(GateAPrefs.rememberedMac), isNull);
    expect(prefs.getBool(GateAPrefs.gateAPassed), isNull);
    expect(prefs.getString(GateAPrefs.lastSyncCursor), isNull);
  });

  test('Forget clears vitals keys via wipe callback and is idempotent', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.gateAPassed: true,
      GateAPrefs.sleepSessionsJson: '[{"beginUnix":1,"endUnix":2}]',
      GateAPrefs.dailyHrJson:
          '[{"dayKey":"2023-01-01","minBpm":1,"avgBpm":1,"maxBpm":1,"sampleCount":1}]',
      GateAPrefs.workoutsJson:
          '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
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
      },
    );

    final first = await repo.forgetDevice();
    expect(first.isRight, isTrue);
    expect(wipeCalls, 1);
    expect(prefs.getString(GateAPrefs.sleepSessionsJson), isNull);
    expect(prefs.getString(GateAPrefs.dailyHrJson), isNull);
    expect(prefs.getString(GateAPrefs.workoutsJson), isNull);

    final second = await repo.forgetDevice();
    expect(second.isRight, isTrue);
    expect(wipeCalls, 2);
  });
}

extension<L, R> on Either<L, R> {
  R getOrThrow() => fold((l) => throw Exception(l), (r) => r);
}
