import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/home/domain/home_precedence.dart';

void main() {
  HomePrecedence resolve({
    bool isPaired = true,
    bool everSynced = true,
    bool syncInProgress = false,
    bool syncFailed = false,
    bool hasSwimTakeaway = false,
  }) {
    return resolveHomePrecedence(
      HomePrecedenceInputs(
        isPaired: isPaired,
        everSynced: everSynced,
        syncInProgress: syncInProgress,
        syncFailed: syncFailed,
        hasSwimTakeaway: hasSwimTakeaway,
      ),
    );
  }

  test('1 not paired wins over everything', () {
    expect(
      resolve(
        isPaired: false,
        syncInProgress: true,
        syncFailed: true,
        hasSwimTakeaway: true,
      ),
      HomePrecedence.notPaired,
    );
  });

  test('2 sync in progress beats never synced / failed / data', () {
    expect(
      resolve(everSynced: false, syncInProgress: true),
      HomePrecedence.syncInProgress,
    );
    expect(
      resolve(syncInProgress: true, syncFailed: true, hasSwimTakeaway: true),
      HomePrecedence.syncInProgress,
    );
  });

  test('3 paired never synced', () {
    expect(
      resolve(everSynced: false),
      HomePrecedence.pairedNeverSynced,
    );
  });

  test('4 sync failed after a prior sync', () {
    expect(
      resolve(syncFailed: true, hasSwimTakeaway: true),
      HomePrecedence.syncFailed,
    );
  });

  test('5 data available when swim takeaway exists', () {
    expect(
      resolve(hasSwimTakeaway: true),
      HomePrecedence.dataAvailable,
    );
  });

  test('6 no swim data yet', () {
    expect(resolve(), HomePrecedence.noSwimDataYet);
  });
}
