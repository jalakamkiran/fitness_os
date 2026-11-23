import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/diagnostics/presentation/widgets/backend_sync_tile.dart';

/// Permanent dig-deeper host: swim pipeline toggle + App Data Export.
///
/// Not Qwen-branded. Does not host Run reasoner / LLM ranking.
class AdvancedToolsScreen extends StatefulWidget {
  const AdvancedToolsScreen({
    super.key,
    this.prefs,
    this.exportService,
    this.shareExport,
    this.exportOverride,
    this.exportBusyOverride,
  });

  final SharedPreferences? prefs;
  final AppDataExportService? exportService;
  final Future<void> Function(File file)? shareExport;
  final Future<AppDataExportResult> Function()? exportOverride;
  final bool Function()? exportBusyOverride;

  @override
  State<AdvancedToolsScreen> createState() => _AdvancedToolsScreenState();
}

class _AdvancedToolsScreenState extends State<AdvancedToolsScreen> {
  bool _digDeeper = false;
  bool _busy = false;
  String? _status;

  SharedPreferences get _prefs => widget.prefs ?? sl<SharedPreferences>();
  AppDataExportService get _export =>
      widget.exportService ?? sl<AppDataExportService>();

  bool get _exportBusy =>
      widget.exportBusyOverride?.call() ?? _export.isBusy;

  Future<AppDataExportResult> _runExport() =>
      widget.exportOverride?.call() ?? _export.exportToCache();

  @override
  void initState() {
    super.initState();
    _digDeeper = _prefs.getBool(GateAPrefs.swimDigDeeper) ?? false;
  }

  Future<void> _setDigDeeper(bool value) async {
    await _prefs.setBool(GateAPrefs.swimDigDeeper, value);
    if (!mounted) return;
    setState(() => _digDeeper = value);
  }

  Future<void> _onExportTapped() async {
    if (_busy) return;
    if (_exportBusy) {
      setState(() {
        _status =
            'Export blocked — wait for sync or Forget to finish, then try again.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export data?'),
        content: const Text(
          'This creates a JSON file of local workout, sleep, and heart-rate '
          'data. It contains health biometrics and is not anonymized. '
          'After you share it, recipients may keep copies — deleting the '
          'app export cache does not revoke shared copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _status = 'Assembling export…';
    });

    final result = await _runExport();
    if (!mounted) return;

    if (!result.isSuccess || result.file == null) {
      setState(() {
        _busy = false;
        _status = result.message ?? 'Export failed.';
      });
      return;
    }

    final file = result.file!;
    final bytes = result.byteLength ?? await file.length();
    if (!mounted) return;
    if (bytes > AppDataExportEnvelope.softWarnBytes) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large export'),
          content: Text(
            'Export is about $mb MB. Continue to the share sheet?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (cont != true) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = 'Export saved locally. Share cancelled.';
        });
        return;
      }
    }

    if (!mounted) return;
    final sharePath = file.absolute.path;
    if (!sharePath.contains('/${AppDataExportEnvelope.exportCacheDirName}/')) {
      setState(() {
        _busy = false;
        _status = 'Export path refused — not under export cache.';
      });
      return;
    }
    try {
      final share = widget.shareExport;
      if (share != null) {
        await share(file);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Fathom app data export',
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Export ready. Share sheet dismissed is OK.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Share failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Swim dig-deeper',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When on, pool/open-water workout detail shows pipeline chrome '
            '(enrichment counts, invent-guard include, Dev columns). '
            'Off by default for the athlete coaching path.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('swim-dig-deeper-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show dig-deeper surfaces'),
            subtitle: Text(_digDeeper ? 'On' : 'Off'),
            value: _digDeeper,
            onChanged: _busy ? null : _setDigDeeper,
          ),
          const SizedBox(height: 24),
          Text(
            'Diagnostics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const BackendSyncTile(),
          ListTile(
            key: const Key('advanced-export-tile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.ios_share),
            title: const Text('Export data'),
            subtitle: const Text(
              'Share a redacted JSON snapshot of local app data for offline analysis.',
            ),
            enabled: !_busy,
            onTap: _busy ? null : _onExportTapped,
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
