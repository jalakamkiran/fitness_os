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
}

extension<L, R> on Either<L, R> {
  R getOrThrow() => fold((l) => throw Exception(l), (r) => r);
}
