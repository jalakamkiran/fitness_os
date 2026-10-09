import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';

/// Intake: goal distance, optional target time, horizon, sessions/week +
/// required pool-only disclosure.
class ProgramsCreateScreen extends StatefulWidget {
  const ProgramsCreateScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  State<ProgramsCreateScreen> createState() => _ProgramsCreateScreenState();
}

class _ProgramsCreateScreenState extends State<ProgramsCreateScreen> {
  final _goalCtrl = TextEditingController(text: '1200');
  final _timeCtrl = TextEditingController();
  final _weeksCtrl = TextEditingController(text: '3');
  final _spwCtrl = TextEditingController(text: '3');
  final _selfCapCtrl = TextEditingController(text: '1000');
  bool _poolOnly = false;
  bool _submitting = false;

  @override
  void dispose() {
    _goalCtrl.dispose();
    _timeCtrl.dispose();
    _weeksCtrl.dispose();
    _spwCtrl.dispose();
    _selfCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final goal = int.tryParse(_goalCtrl.text.trim());
    final weeks = int.tryParse(_weeksCtrl.text.trim());
    final spw = int.tryParse(_spwCtrl.text.trim());
    if (goal == null || goal < 200 || weeks == null || weeks < 1 || spw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check goal distance, weeks, and sessions.')),
      );
      return;
    }
    if (!_poolOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm pool-only before starting.')),
      );
      return;
    }

    int? targetSec;
    final timeRaw = _timeCtrl.text.trim();
    if (timeRaw.isNotEmpty) {
      targetSec = _parseMmSs(timeRaw);
      if (targetSec == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Target time as mm:ss (e.g. 24:00).')),
        );
        return;
      }
    }

    final selfCap = int.tryParse(_selfCapCtrl.text.trim()) ?? 1000;

    setState(() => _submitting = true);
    final ok = await widget.controller.createAndActivate(
      intake: ProgramIntake(
        goalDistanceM: goal,
        targetTimeSec: targetSec,
        horizonWeeks: weeks,
        sessionsPerWeek: spw.clamp(2, 5),
        poolOnlyAcknowledged: true,
      ),
      selfReportCapacityM: selfCap,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final err = widget.controller.error ?? 'Couldn’t start program.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  int? _parseMmSs(String raw) {
    final parts = raw.split(':');
    if (parts.length == 1) {
      final m = int.tryParse(parts[0]);
      return m == null ? null : m * 60;
    }
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return m * 60 + s;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('New program'),
        backgroundColor: colors.bg,
        foregroundColor: colors.ink,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            'Set a continuous pool distance and a horizon. Fathom builds '
            'milestones and sessions from your recent swims when available.',
            style: TextStyle(fontSize: 14, color: colors.inkDim, height: 1.4),
          ),
          const SizedBox(height: 20),
          _field(
            label: 'Goal distance (m)',
            controller: _goalCtrl,
            keyName: 'programs-goal-distance',
          ),
          _field(
            label: 'Target time (optional, mm:ss)',
            controller: _timeCtrl,
            keyName: 'programs-target-time',
            optional: true,
          ),
          _field(
            label: 'Horizon (weeks)',
            controller: _weeksCtrl,
            keyName: 'programs-horizon-weeks',
          ),
          _field(
            label: 'Sessions per week (2–5)',
            controller: _spwCtrl,
            keyName: 'programs-sessions-week',
          ),
          _field(
            label: 'Starting continuous distance (m)',
            controller: _selfCapCtrl,
            keyName: 'programs-self-capacity',
            helper: 'Used when pool history is thin or missing.',
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('programs-pool-only-disclosure'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.bgElev,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pool only',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This program is for continuous pool swimming. Open-water '
                  'and mixed sessions are not used for milestones or proofs.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.inkDim,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('programs-pool-only-checkbox'),
                  onTap: () => setState(() => _poolOnly = !_poolOnly),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _poolOnly,
                        onChanged: (v) =>
                            setState(() => _poolOnly = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'I understand — pool only',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.controller.createHint != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.controller.createHint!,
              style: TextStyle(fontSize: 13, color: colors.amber),
            ),
          ],
          if (widget.controller.active?.feasibilityWarning != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.controller.active!.feasibilityWarning!,
              key: const Key('programs-feasibility-warning'),
              style: TextStyle(fontSize: 13, color: colors.amber, height: 1.35),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('programs-create-submit'),
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentInk,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start program'),
          ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String keyName,
    bool optional = false,
    String? helper,
  }) {
    final colors = FathomColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.inkDim,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: Key(keyName),
            controller: controller,
            keyboardType: optional
                ? TextInputType.text
                : TextInputType.number,
            inputFormatters: optional
                ? null
                : [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.bgElev,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.line),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(
              helper,
              style: TextStyle(fontSize: 12, color: colors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
