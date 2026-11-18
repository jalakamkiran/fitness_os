import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/features/lift/data/lift_watch_bridge.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';

/// Phase 0 on-watch probe UI (behind [FeatureFlags.liftWatch]).
class LiftDebugScreen extends StatefulWidget {
  const LiftDebugScreen({super.key, LiftWatchBridge? bridge})
      : _bridge = bridge;

  /// Widget tests only — does not affect release builds.
  @visibleForTesting
  static bool debugForceEnabled = false;

  final LiftWatchBridge? _bridge;

  static bool get _liftFlagOn =>
      debugForceEnabled || FeatureFlags.liftWatch;

  @override
  State<LiftDebugScreen> createState() => _LiftDebugScreenState();
}

class _LiftDebugScreenState extends State<LiftDebugScreen> {
  final _log = <String>[];
  final _title = TextEditingController(text: 'Set 1/4 · Bench press');
  final _body = TextEditingController(text: '60 kg × 8 · rest 120s');
  int _notifyType = 0x7F;
  bool _replyKey = true;
  String? _category;
  int? _lastSentAtMs;

  LiftWatchBridge? _bridge;
  String? _initError;
  String? _connectionHint = 'Watch link unknown — connect from Home if needed.';
  StreamSubscription<LiftReplyEvent>? _eventSub;
  ErrorWidgetBuilder? _priorErrorWidget;

  @override
  void initState() {
    super.initState();
    _priorErrorWidget = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Scaffold(
          appBar: AppBar(title: const Text('Lift watch debug')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              details.exceptionAsString(),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
      );
    };
    if (!LiftDebugScreen._liftFlagOn) return;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final bridge = widget._bridge ?? sl<LiftWatchBridge>();
      _bridge = bridge;
      try {
        await bridge.configure(enabled: true);
      } catch (e) {
        _appendLog('Configure skipped (watch may be disconnected): $e');
      }
      _eventSub = bridge.events.listen(
        _onEvent,
        onError: (Object e) {
          if (!mounted) return;
          _appendLog('Event stream error: $e');
        },
      );
      if (mounted) setState(() => _connectionHint = null);
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _initError = '$e';
        debugPrint('LiftDebugScreen bootstrap failed: $e\n$st');
      });
    }
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  void _onEvent(LiftReplyEvent e) {
    final latency = _lastSentAtMs != null ? e.rxAtMs - _lastSentAtMs! : null;
    final ist = _formatIst(e.rxAtMs);
    final line = e.kind == 'lift_reply'
        ? '$ist reply "${e.text}" key=${_redactKey(e.key)}'
            '${latency != null ? ' Δ${latency}ms' : ''}'
        : '$ist ${e.kind} cmd=${e.replyType} ${e.text}';
    _appendLog(line);
  }

  String _formatIst(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms)
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${(dt.millisecond).toString().padLeft(3, '0')} IST';
  }

  String _redactKey(String key) {
    final parts = key.split(':');
    if (parts.length < 2) return '***';
    return 'lift:***:${parts.last}';
  }

  Future<void> _safeAction(String label, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      _appendLog('$label failed: $e');
    }
  }

  Future<void> _capabilities() async {
    final bridge = _bridge;
    if (bridge == null) {
      _appendLog('Capabilities: bridge not ready');
      return;
    }
    try {
      final snap = await bridge.capabilities();
      _appendLog('Capabilities: $snap');
    } catch (e) {
      _appendLog('Capabilities failed: $e');
    }
  }

  Future<void> _sendTest() async {
    final bridge = _bridge;
    if (bridge == null) return;
    try {
      final result = await bridge.sendSetNotification(
        set: const PlannedSet(
          exerciseId: 'debug',
          name: 'Debug',
          setIndex: 1,
          globalIndex: 1,
          plannedKg: 60,
          plannedReps: 8,
          restSec: 120,
        ),
        sessionId: 'debug_session',
        title: _title.text,
        body: _body.text,
        type: _notifyType,
        withReplyKey: _replyKey,
        category: _category,
      );
      _lastSentAtMs = result['sentAtMs'] as int?;
      _appendLog('Sent test set msgId=${result['msgId']} error=${result['error']}');
    } catch (e) {
      _appendLog('Send test set failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!LiftDebugScreen._liftFlagOn) {
      return const Scaffold(
        body: Center(child: Text('Lift watch flag is off')),
      );
    }
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lift watch debug')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'Could not start lift debug:\n$_initError',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Lift watch debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_connectionHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _connectionHint!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _bridge == null ? null : _capabilities,
                child: const Text('Capabilities'),
              ),
              FilledButton(
                onPressed: _bridge == null
                    ? null
                    : () => _safeAction(
                          'Query quick replies',
                          () => _bridge!.queryQuickReplies(),
                        ),
                child: const Text('Query quick replies'),
              ),
              FilledButton(
                onPressed: _bridge == null
                    ? null
                    : () => _safeAction(
                          'Set quick replies',
                          () => _bridge!.setQuickReplies(
                            const [
                              'Done',
                              '-1 rep',
                              '-2 reps',
                              '+2.5 kg',
                              'Failed',
                            ],
                          ),
                        ),
                child: const Text('Set Fathom quick replies'),
              ),
              FilledButton(
                onPressed: _bridge == null ? null : _sendTest,
                child: const Text('Send test set'),
              ),
              OutlinedButton(
                onPressed: _bridge == null
                    ? null
                    : () => _safeAction(
                          'Remove last',
                          () => _bridge!.removeLast(),
                        ),
                child: const Text('Remove last'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _log.clear()),
                child: const Text('Clear log'),
              ),
            ],
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Body'),
          ),
          DropdownButton<int>(
            value: _notifyType,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 0x7F, child: Text('Type 0x7F generic')),
              DropdownMenuItem(value: 0x02, child: Text('Type 0x02 sms')),
            ],
            onChanged: (v) => setState(() => _notifyType = v ?? 0x7F),
          ),
          SwitchListTile(
            title: const Text('Reply key'),
            value: _replyKey,
            onChanged: (v) => setState(() => _replyKey = v),
          ),
          DropdownButton<String?>(
            value: _category,
            isExpanded: true,
            hint: const Text('Category'),
            items: const [
              DropdownMenuItem(value: null, child: Text('none')),
              DropdownMenuItem(value: 'msg', child: Text('msg')),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),
          Text('Event log', style: Theme.of(context).textTheme.titleMedium),
          if (_log.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No events yet — actions log here when the watch replies.'),
            ),
          ..._log.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _log.join('\n'))),
            child: const Text('Copy log'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_priorErrorWidget != null) {
      ErrorWidget.builder = _priorErrorWidget!;
    }
    _eventSub?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }
}