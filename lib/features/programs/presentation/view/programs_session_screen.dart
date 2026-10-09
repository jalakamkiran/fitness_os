import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/widgets/chore_checklist.dart';

/// Session detail: WU/main/CD checklist + Done / Skip with reason chips.
class ProgramsSessionScreen extends StatefulWidget {
  const ProgramsSessionScreen({
    super.key,
    required this.controller,
    required this.choreId,
  });

  final ProgramsController controller;
  final String choreId;

  @override
  State<ProgramsSessionScreen> createState() => _ProgramsSessionScreenState();
}

class _ProgramsSessionScreenState extends State<ProgramsSessionScreen> {
  final List<bool> _segDone = [false, false, false];
  bool _busy = false;

  ChoreSession? get _chore => widget.controller.choreById(widget.choreId);

  Future<void> _done() async {
    setState(() => _busy = true);
    await widget.controller.markChoreDone(widget.choreId);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  Future<void> _skip(SkipReason reason) async {
    setState(() => _busy = true);
    await widget.controller.skipChore(widget.choreId, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  void _showSkipSheet() {
    final colors = FathomColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.bgElev,
      builder: (ctx) {
        final chips = <(SkipReason, String)>[
          (SkipReason.otherLoad, 'Other load'),
          (SkipReason.recovery, 'Recovery'),
          (SkipReason.ill, 'Not well'),
          (SkipReason.travel, 'Travel'),
          (SkipReason.poolClosed, 'Pool closed'),
          (SkipReason.other, 'Other'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Skip reason',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (reason, label) in chips)
                      ActionChip(
                        key: Key('programs-skip-${reason.name}'),
                        label: Text(label),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _skip(reason);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final chore = _chore;
    if (chore == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('Session not found.')),
      );
    }

    final open = chore.state == ChoreState.scheduled ||
        chore.state == ChoreState.due ||
        chore.state == ChoreState.lapsed;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Session'),
        backgroundColor: colors.bg,
        foregroundColor: colors.ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            chore.focusLine ?? 'Pool session',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${chore.dayIso} · ${chore.targetDistanceM} m',
            style: TextStyle(fontSize: 14, color: colors.inkDim),
          ),
          const SizedBox(height: 16),
          ChoreChecklist(
            chore: chore,
            segDone: _segDone,
            onToggleSeg: (i) {
              setState(() => _segDone[i] = !_segDone[i]);
            },
          ),
          if (open) ...[
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('programs-chore-done'),
              onPressed: _busy ? null : _done,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Done'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('programs-chore-skip'),
              onPressed: _busy ? null : _showSkipSheet,
              child: const Text('Skip'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              'Status: ${chore.state.name}',
              style: TextStyle(color: colors.inkDim, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
