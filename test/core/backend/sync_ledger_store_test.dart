import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in-memory round-trip', () async {
    final store = InMemorySyncLedgerStore();
    const data = SyncLedgerData(lastSuccessfulSyncMs: 1000);
    await store.save(data);
    final loaded = await store.load();
    expect(loaded.lastSuccessfulSyncMs, 1000);
  });
}