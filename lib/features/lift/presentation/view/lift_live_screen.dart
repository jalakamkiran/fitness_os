import 'package:flutter/material.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/session_runner.dart';
import 'package:fitness_os/features/lift/presentation/controller/lift_session_controller.dart';

class LiftLiveScreen extends StatefulWidget {
  const LiftLiveScreen({
    super.key,
    required this.session,
    required this.controller,
  });

  final PlannedSession session;
  final LiftSessionController controller;

  @override
  State<LiftLiveScreen> createState() => _LiftLiveScreenState();
}

class _LiftLiveScreenState extends State<LiftLiveScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.startSession(widget.session);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.controller.currentSet;
    final state = widget.controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Live lift')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Phase: ${state.phase.name}', style: Theme.of(context).textTheme.titleMedium),
            if (set != null) ...[
              Text('${set.name} set ${set.setIndex}'),
              Text('${set.plannedKg} kg × ${set.plannedReps}'),
            ],
            if (widget.controller.lastReplyText != null)
              Text('Last reply: ${widget.controller.lastReplyText}'),
            const Spacer(),
            Row(
              children: [
                OutlinedButton(
                  onPressed: widget.controller.pause,
                  child: const Text('Pause'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.controller.skipSet,
                  child: const Text('Skip set'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await widget.controller.endSession();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('End'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}