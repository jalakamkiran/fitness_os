import 'package:fitness_os/core/backend/backend_sync_service.dart'
    show BackendPusher, BackendSyncService;
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

/// Backend sync status + manual push (Diagnostics).
class BackendSyncTile extends StatelessWidget {
  const BackendSyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<BackendPusher>()) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<BackendSyncStatus>(
      valueListenable: GetIt.I<BackendSyncService>().status,
      builder: (context, syncStatus, _) {
        final last = syncStatus.lastSuccessfulSync;
        final lastLabel =
            last == null ? 'Never' : '${last.toLocal()}'.substring(0, 16);
        var subtitle = 'Last synced $lastLabel';
        if (syncStatus.pendingCount > 0) {
          subtitle += ' · ${syncStatus.pendingCount} pending';
        }
        if (syncStatus.quarantinedCount > 0) {
          subtitle += ' · ${syncStatus.quarantinedCount} quarantined';
        }
        if (syncStatus.inFlight) {
          subtitle += ' · syncing…';
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Backend sync'),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncStatus.quarantinedItems.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Quarantine reasons',
                  onPressed: () =>
                      _showQuarantineSheet(context, syncStatus.quarantinedItems),
                ),
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: syncStatus.inFlight
                    ? null
                    : () => GetIt.I<BackendPusher>().push(SyncTrigger.manual),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuarantineSheet(
    BuildContext context,
    List<QuarantinedLedgerItem> items,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shrinkWrap: true,
            children: [
              Text(
                'Quarantined records',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${item.kind.name} · ${item.id}'),
                  subtitle: Text(item.reason),
                ),
            ],
          ),
        );
      },
    );
  }
}