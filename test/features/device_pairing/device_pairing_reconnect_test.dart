import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReconnectLink extends HuaweiLink {
  _ReconnectLink() : super();

  LinkState forced = LinkState.disconnected;
  int reconnectCalls = 0;
  bool hasSecretsValue = true;

  @override
  LinkState get state => forced;

  @override
  Future<void> start() async {}

  @override
  Future<bool> hasSecrets() async => hasSecretsValue;

  @override
  Future<void> reconnect(String mac) async {
    reconnectCalls++;
    if (!hasSecretsValue) {
      forced = LinkState.authFailed;
      return;
    }
    forced = LinkState.gateAIncomplete;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AE2: prefs reload reconnect reaches authenticated session', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'HUAWEI Watch GT 5-A07',
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _ReconnectLink();
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    // Simulate process death: new repo, same prefs.
    final result = await repo.reconnectRemembered();
    expect(result.isRight, isTrue);
    expect(link.reconnectCalls, 1);
    expect(link.state, LinkState.gateAIncomplete);
    expect(prefs.getString(GateAPrefs.rememberedMac), isNotNull);
  });

  test('AE2 failure-accept: reconnect_failed keeps remembered device', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'GT5',
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _ReconnectLink()..hasSecretsValue = false;
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);

    // Bypass link.reconnect stub: repository calls link.reconnect which sets authFailed
    // but repository interprets non-ready as ReconnectFailure while keeping prefs.
    final result = await repo.reconnectRemembered();
    expect(result.isLeft, isTrue);
    expect(prefs.getString(GateAPrefs.rememberedMac), 'AA:BB:CC:DD:EE:FF');
    expect(prefs.getBool(GateAPrefs.gateAPassed) ?? false, isFalse);
  });

  test('missing secrets fail closed without spinning', () async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'GT5',
    });
    final prefs = await SharedPreferences.getInstance();
    final link = _ReconnectLink()..hasSecretsValue = false;
    final repo = DevicePairingRepositoryImpl(link: link, prefs: prefs);
    final result = await repo.reconnectRemembered();
    expect(result, isA<Left<Failure, void>>());
  });
}
