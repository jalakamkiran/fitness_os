import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';

/// Download / manage on-device Qwen3 reasoner (no cloud API required).
class CoachSettingsScreen extends StatefulWidget {
  const CoachSettingsScreen({super.key});

  @override
  State<CoachSettingsScreen> createState() => _CoachSettingsScreenState();
}

class _CoachSettingsScreenState extends State<CoachSettingsScreen> {
  bool _ready = false;
  bool _busy = false;
  double? _progress;
  String? _status;

  SwimReasonerService get _service => sl<SwimReasonerService>();
  Qwen3SwimReasoner get _qwen => _service.qwen3;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ready = await _qwen.isInstalled();
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
    final ok = await _qwen.ensureInstalled(
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
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_ready ? 'Already installed' : 'Download Qwen3 (~586MB)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Refresh status'),
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
