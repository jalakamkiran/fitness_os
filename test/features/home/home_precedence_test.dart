import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/home/domain/home_precedence.dart';

void main() {
  HomePrecedence resolve({
    bool isPaired = true,
    bool everSynced = true,
    bool syncInProgress = false,
    bool syncFailed = false,
  }) {
    return resolveHomePrecedence(
      HomePrecedenceInputs(
        isPaired: isPaired,
        everSynced: everSynced,
        syncInProgress: syncInProgress,
        syncFailed: syncFailed,
      ),
    );
  }

  test('1 not paired wins over everything', () {
    expect(
      resolve(
        isPaired: false,
        syncInProgress: true,
        syncFailed: true,
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
      resolve(syncInProgress: true, syncFailed: true),
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
      resolve(syncFailed: true),
      HomePrecedence.syncFailed,
    );
  });

  test('5 trusted day without swim is still dataAvailable', () {
    expect(resolve(), HomePrecedence.dataAvailable);
  });

  test('snapshot fixture can carry multi-sport sessions without swim gate', () {
    final snap = HomeSnapshot.forPrecedence(HomePrecedence.dataAvailable);
    expect(snap.todaySessions, hasLength(2));
    expect(snap.todaySessions.first.title, contains('Pool swim'));
    expect(snap.todaySessions.last.title, contains('Strength'));
    expect(snap.sleepDurationLabel, isNotNull);
    expect(snap.bodyHrLabel, isNotNull);
  });

  test('rest-day fixture has empty sessions list', () {
    final snap = HomeSnapshot.forPrecedence(
      HomePrecedence.dataAvailable,
      restDay: true,
    );
    expect(snap.todaySessions, isEmpty);
    expect(snap.sleepDurationLabel, isNotNull);
    expect(snap.bodyHrLabel, isNotNull);
  });
}
