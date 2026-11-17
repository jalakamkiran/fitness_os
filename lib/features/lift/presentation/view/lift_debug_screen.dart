import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:flutter/services.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/features/lift/data/lift_watch_bridge.dart';

/// Phase 0 on-watch probe UI (behind [FeatureFlags.liftWatch]).
class LiftDebugScreen extends StatefulWidget {
  const LiftDebugScreen({super.key, LiftWatchBridge? bridge})
      : _bridge = bridge;

  final LiftWatchBridge? _bridge;

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

  LiftWatchBridge get _bridge => widget._bridge ?? sl<LiftWatchBridge>();

  @override
  void initState() {
    super.initState();
    if (FeatureFlags.liftWatch) {
      unawaited(_bridge.configure(enabled: true));
      _bridge.events.listen(_onEvent);
    }
  }

  void _onEvent(LiftReplyEvent e) {
    final latency = _lastSentAtMs != null ? e.rxAtMs - _lastSentAtMs! : null;
    final ist = _formatIst(e.rxAtMs);
  final line = e.kind == 'lift_reply'
        ? '$ist reply "${e.text}" key=${_redactKey(e.key)}'
            '${latency != null ? ' Δ${latency}ms' : ''}'
        : '$ist ${e.kind} cmd=${e.replyType} ${e.text}';
    setState(() => _log.insert(0, line));
  }

  String _formatIst(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toUtc().add(const Duration(hours: 5, minutes: 30));
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

  Future<void> _capabilities() async {
    final snap = await _bridge.capabilities();
    setState(() => _log.insert(0, 'Capabilities: $snap'));
  }

  Future<void> _sendTest() async {
    final result = await _bridge.sendSetNotification(
      set: PlannedSet(
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
    setState(() => _log.insert(0, 'Sent test set msgId=${result['msgId']}'));
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.liftWatch) {
      return const Scaffold(
        body: Center(child: Text('Lift watch flag is off')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Lift watch debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _capabilities, child: const Text('Capabilities')),
              FilledButton(onPressed: () => _bridge.queryQuickReplies(), child: const Text('Query quick replies')),
              FilledButton(
                onPressed: () => _bridge.setQuickReplies(
                  const ['Done', '-1 rep', '-2 reps', '+2.5 kg', 'Failed'],
                ),
                child: const Text('Set Fathom quick replies'),
              ),
              FilledButton(onPressed: _sendTest, child: const Text('Send test set')),
              OutlinedButton(onPressed: () => _bridge.removeLast(), child: const Text('Remove last')),
              OutlinedButton(onPressed: () => setState(() => _log.clear()), child: const Text('Clear log')),
            ],
          ),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: _body, decoration: const InputDecoration(labelText: 'Body')),
          DropdownButton<int>(
            value: _notifyType,
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
            hint: const Text('Category'),
            items: const [
              DropdownMenuItem(value: null, child: Text('none')),
              DropdownMenuItem(value: 'msg', child: Text('msg')),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),
          Text('Event log', style: Theme.of(context).textTheme.titleMedium),
          ..._log.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              )),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: _log.join('\n'))),
            child: const Text('Copy log'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }
}