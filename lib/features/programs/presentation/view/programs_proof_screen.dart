import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';

/// Trial proof: calm pass celebration or factual not-passed + slipped date.
///
/// No shame copy — never "you failed", sad emoji, or red-shame language.
class ProgramsProofScreen extends StatefulWidget {
  const ProgramsProofScreen({
    super.key,
    required this.controller,
    required this.milestoneId,
    this.initialOutcome,
    this.initialJudgedDistanceM,
    this.previewResultOnly = false,
    this.previewSlippedDate,
  });

  final ProgramsController controller;
  final String milestoneId;

  /// When set (e.g. tests), applies outcome then shows the result.
  final ProofOutcome? initialOutcome;
  final int? initialJudgedDistanceM;

  /// When true with [initialOutcome], skip store IO and show result copy only.
  final bool previewResultOnly;
  final String? previewSlippedDate;

  @override
  State<ProgramsProofScreen> createState() => _ProgramsProofScreenState();
}

class _ProgramsProofScreenState extends State<ProgramsProofScreen> {
  final _distanceCtrl = TextEditingController();
  ProofOutcome? _outcome;
  int? _judgedM;
  String? _slippedDate;
  bool _busy = false;

  Milestone? get _milestone =>
      widget.controller.milestoneById(widget.milestoneId);

  @override
  void initState() {
    super.initState();
    if (widget.initialOutcome != null && widget.previewResultOnly) {
      _outcome = widget.initialOutcome;
      _judgedM = widget.initialJudgedDistanceM;
      _slippedDate = widget.previewSlippedDate ??
          widget.controller.milestoneById(widget.milestoneId)?.forecastDateIso;
    } else if (widget.initialOutcome != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _apply(widget.initialOutcome!, widget.initialJudgedDistanceM);
      });
    }
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply(ProofOutcome outcome, int? judged) async {
    setState(() => _busy = true);
    final before = widget.controller.milestoneById(widget.milestoneId);
    final program = await widget.controller.applyProof(
      milestoneId: widget.milestoneId,
      outcome: outcome,
      judgedDistanceM: judged,
    );
    if (!mounted) return;
    Milestone? after;
    if (program != null) {
      for (final m in program.milestones) {
        if (m.id == widget.milestoneId) {
          after = m;
          break;
        }
      }
    }
    setState(() {
      _busy = false;
      _outcome = outcome;
      _judgedM = judged;
      _slippedDate = after?.forecastDateIso ?? before?.forecastDateIso;
    });
  }

  Future<void> _submitPass() async {
    final m = _milestone;
    if (m == null) return;
    await _apply(ProofOutcome.pass, m.targetDistanceM);
  }

  Future<void> _submitNotPassed() async {
    final m = _milestone;
    if (m == null) return;
    final judged = int.tryParse(_distanceCtrl.text.trim());
    if (judged == null || judged < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the distance you swam (m).')),
      );
      return;
    }
    final near = judged >= (m.targetDistanceM * 0.9).round() &&
        judged < m.targetDistanceM;
    await _apply(
      near ? ProofOutcome.nearPass : ProofOutcome.fail,
      judged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final m = _milestone;

    if (_outcome != null) {
      return _ResultScaffold(
        colors: colors,
        outcome: _outcome!,
        targetM: m?.targetDistanceM ?? 0,
        judgedM: _judgedM,
        slippedDate: _slippedDate,
        trialName: m != null ? formatTrialName(m) : 'Trial',
        onDone: () => Navigator.of(context).pop(),
      );
    }

    if (m == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AgonAppHeader(
          title: 'Agon · Pool',
          subtitle: 'Trial',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: const Center(child: Text('Trial not found.')),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Agon · Pool',
        subtitle: formatTrialName(m),
        onBack: () => Navigator.of(context).pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          LayerTag('${formatTrialName(m)} · ${m.forecastDateIso}'),
          const SizedBox(height: 6),
          Text(
            '${formatMeters(m.targetDistanceM)} m non-stop',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Planned ${m.plannedDateIso} · forecast ${m.forecastDateIso}',
            style: TextStyle(fontSize: 14, color: colors.inkDim),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('programs-proof-pass'),
            onPressed: _busy ? null : _submitPass,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentInk,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Passed',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Distance swam (m)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.inkDim,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('programs-proof-distance'),
            controller: _distanceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.bgElev,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('programs-proof-not-passed'),
            onPressed: _busy ? null : _submitNotPassed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: colors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Not passed yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultScaffold extends StatelessWidget {
  const _ResultScaffold({
    required this.colors,
    required this.outcome,
    required this.targetM,
    required this.judgedM,
    required this.slippedDate,
    required this.trialName,
    required this.onDone,
  });

  final FathomColors colors;
  final ProofOutcome outcome;
  final int targetM;
  final int? judgedM;
  final String? slippedDate;
  final String trialName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final passed = outcome == ProofOutcome.pass;
    return Scaffold(
      key: Key(
        passed ? 'programs-proof-pass-result' : 'programs-proof-fail-result',
      ),
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Agon · Pool',
        subtitle: trialName,
        onBack: onDone,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!passed) ...[
              Text(
                'Not passed yet',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: colors.inkFaint,
                ),
              ),
              const SizedBox(height: 4),
              if (judgedM != null)
                Text.rich(
                  key: const Key('programs-proof-distance-fact'),
                  TextSpan(
                    text: formatMeters(judgedM!),
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2.4,
                      height: 1,
                      color: colors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    children: [
                      TextSpan(
                        text: ' m of ${formatMeters(targetM)} m',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: colors.inkDim,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  key: const Key('programs-proof-distance-fact'),
                  'Target ${formatMeters(targetM)} m',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
              if (slippedDate != null) ...[
                const SizedBox(height: 12),
                Text(
                  key: const Key('programs-proof-slipped-date'),
                  'Next attempt $slippedDate',
                  style: TextStyle(fontSize: 15, color: colors.inkDim),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Dates move. Areté and Streak stay as they are.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.inkDim,
                  height: 1.4,
                ),
              ),
            ] else ...[
              Text(
                'Trial cleared',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: Color.lerp(colors.accent, colors.ink, 0.3),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Milestone cleared.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                key: const Key('programs-proof-distance-fact'),
                judgedM != null
                    ? '${formatMeters(judgedM!)} m of ${formatMeters(targetM)} m'
                    : 'Target ${formatMeters(targetM)} m',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Steady work. The ladder moves forward.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.inkDim,
                  height: 1.4,
                ),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Back to Agon',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
