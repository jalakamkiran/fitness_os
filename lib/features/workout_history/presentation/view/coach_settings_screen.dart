import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';

/// Download / manage on-device Qwen3 reasoner + owner data export.
class CoachSettingsScreen extends StatefulWidget {
  const CoachSettingsScreen({
    super.key,
    this.reasonerService,
    this.exportService,
    this.shareExport,
    this.exportOverride,
    this.exportBusyOverride,
    this.isQwenInstalledOverride,
  });

  final SwimReasonerService? reasonerService;
  final AppDataExportService? exportService;

  /// Test seam — production uses [SharePlus] with `application/json`.
  final Future<void> Function(File file)? shareExport;

  /// Test seam — when set, used instead of [AppDataExportService.exportToCache].
  final Future<AppDataExportResult> Function()? exportOverride;

  /// Test seam — when set, used instead of [AppDataExportService.isBusy].
  final bool Function()? exportBusyOverride;

  /// Test seam — skips [Qwen3SwimReasoner.isInstalled] (platform channel).
  final Future<bool> Function()? isQwenInstalledOverride;

  @override
  State<CoachSettingsScreen> createState() => _CoachSettingsScreenState();
}

class _CoachSettingsScreenState extends State<CoachSettingsScreen> {
  bool _ready = false;
  bool _busy = false;
  double? _progress;
  String? _status;

  SwimReasonerService get _service =>
      widget.reasonerService ?? sl<SwimReasonerService>();
  Qwen3SwimReasoner get _qwen => _service.qwen3;
  AppDataExportService get _export =>
      widget.exportService ?? sl<AppDataExportService>();

  bool get _exportBusy =>
      widget.exportBusyOverride?.call() ?? _export.isBusy;

  Future<AppDataExportResult> _runExport() =>
      widget.exportOverride?.call() ?? _export.exportToCache();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ready = widget.isQwenInstalledOverride != null
        ? await widget.isQwenInstalledOverride!()
        : await _qwen.isInstalled();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _status = ready
          ? 'Qwen3 0.6B ready on device (~586MB). Reasoning uses on-device model.'
          : 'Qwen3 not installed. Offline rule reasoner still works. '
              'Download for on-device LLM ranking.';
    });
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Downloading Qwen3 0.6B…';
    });
    final ok = widget.isQwenInstalledOverride != null
        ? await _fakeDownload()
        : await _qwen.ensureInstalled(
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _progress = p);
            },
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ready = ok;
      _progress = ok ? 100 : _progress;
      _status = ok
          ? 'Qwen3 installed.'
          : 'Download failed: ${_qwen.lastError ?? 'unknown'}';
    });
  }

  Future<bool> _fakeDownload() async {
    setState(() => _progress = 10);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted) return false;
    setState(() => _progress = 100);
    return true;
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
      _progress = null;
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
      appBar: AppBar(title: const Text('Reasoner settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'On-device reasoner — Qwen3 0.6B',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ranks allow-listed swim recommendations from diagnoses. '
            'Does not invent drills. Runs fully offline after download. '
            'Apache-2.0 weights via litert-community.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _RowStatus(
            label: 'Status',
            value: _ready ? 'Installed' : 'Not installed',
          ),
          if (_progress != null && _busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (_progress! / 100).clamp(0, 1)),
            const SizedBox(height: 4),
            Text('${_progress!.toStringAsFixed(0)}%'),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _ready ? null : _download,
            icon: _busy && _progress != null
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: (_progress! / 100).clamp(0, 1),
                    ),
                  )
                : const Icon(Icons.download),
            label: Text(_ready ? 'Already installed' : 'Download Qwen3 (~586MB)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Refresh status'),
          ),
          const SizedBox(height: 24),
          Text(
            'Diagnostics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
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
          const SizedBox(height: 24),
          Text(
            'Without the model, workout detail still runs the offline '
            'rule reasoner (deterministic priority from W3 diagnoses).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowStatus extends StatelessWidget {
  const _RowStatus({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}
