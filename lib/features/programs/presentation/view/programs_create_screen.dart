import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';

/// Create Agon · Pool swim — distance, time, horizon, sessions/week + disclosure.
class ProgramsCreateScreen extends StatefulWidget {
  const ProgramsCreateScreen({super.key, required this.controller});

  final ProgramsController controller;

  @override
  State<ProgramsCreateScreen> createState() => _ProgramsCreateScreenState();
}

class _ProgramsCreateScreenState extends State<ProgramsCreateScreen> {
  static const _distChips = [800, 1000, 1200, 1500];
  static const _weekOpts = [2, 3, 4, 6, 8];
  static const _spwOpts = [2, 3, 4, 5];

  int _goalM = 1200;
  int? _targetSec = 24 * 60;
  bool _timeEnabled = true;
  int _weeks = 3;
  int _spw = 3;
  final _selfCapCtrl = TextEditingController(text: '1000');
  bool _poolOnly = false;
  bool _submitting = false;

  @override
  void dispose() {
    _selfCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_goalM < 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check goal distance.')),
      );
      return;
    }
    if (!_poolOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm pool-only before starting.')),
      );
      return;
    }

    final selfCap = int.tryParse(_selfCapCtrl.text.trim()) ?? 1000;

    setState(() => _submitting = true);
    final ok = await widget.controller.createAndActivate(
      intake: ProgramIntake(
        goalDistanceM: _goalM,
        targetTimeSec: _timeEnabled ? _targetSec : null,
        horizonWeeks: _weeks,
        sessionsPerWeek: _spw.clamp(2, 5),
        poolOnlyAcknowledged: true,
      ),
      selfReportCapacityM: selfCap,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final err = widget.controller.error ?? 'Couldn’t start Agon.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  String? get _paceHint {
    final t = _targetSec;
    if (!_timeEnabled || t == null || t <= 0 || _goalM < 50) return null;
    return formatPacePer100(_goalM, t);
  }

  Future<void> _pickTargetTime() async {
    var draft = Duration(seconds: (_targetSec ?? 24 * 60).clamp(60, 7200));
    final colors = FathomColors.of(context);
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: colors.bgElev,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Target time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scroll to set goal swim duration',
                  style: TextStyle(fontSize: 12.5, color: colors.inkDim),
                ),
                SizedBox(
                  height: 180,
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: Theme.of(ctx).brightness,
                      textTheme: CupertinoTextThemeData(
                        pickerTextStyle: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    child: CupertinoTimerPicker(
                      key: const Key('programs-target-time-picker'),
                      mode: CupertinoTimerPickerMode.hm,
                      initialTimerDuration: draft,
                      minuteInterval: 1,
                      onTimerDurationChanged: (d) => draft = d,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(draft),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.accentInk,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Use this time'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _timeEnabled = true;
      _targetSec = picked.inSeconds.clamp(60, 7200);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AgonAppHeader(
        title: 'Agon · Pool',
        subtitle: 'Create',
        onBack: Navigator.of(context).canPop()
            ? () => Navigator.of(context).pop()
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AgonStepBar(active: 1),
                  const SizedBox(height: 12),
                  _DiscloseCard(
                    poolOnly: _poolOnly,
                    onToggle: (v) => setState(() => _poolOnly = v),
                    colors: colors,
                  ),
                  const SizedBox(height: 12),
                  _StepperField(
                    label: 'Goal distance',
                    hint: 'non-stop · pool',
                    valueKey: const Key('programs-goal-distance'),
                    valueChild: Text.rich(
                      TextSpan(
                        text: formatMeters(_goalM),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          color: colors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        children: [
                          TextSpan(
                            text: ' m',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: colors.inkDim,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    onMinus: () => setState(
                      () => _goalM = (_goalM - 50).clamp(200, 10000),
                    ),
                    onPlus: () => setState(
                      () => _goalM = (_goalM + 50).clamp(200, 10000),
                    ),
                    colors: colors,
                    footer: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in _distChips)
                          _SegChip(
                            label: formatMeters(d),
                            selected: _goalM == d,
                            onTap: () => setState(() => _goalM = d),
                            colors: colors,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TargetTimeField(
                    enabled: _timeEnabled,
                    targetSec: _targetSec,
                    paceHint: _paceHint,
                    colors: colors,
                    onPick: _pickTargetTime,
                    onClearOrAdd: () => setState(() {
                      _timeEnabled = !_timeEnabled;
                      _targetSec ??= 24 * 60;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _SegmentedField(
                    label: 'Horizon',
                    hint: '$_weeks weeks',
                    colors: colors,
                    children: [
                      for (final w in _weekOpts)
                        _SegChip(
                          key: w == _weeks
                              ? const Key('programs-horizon-weeks')
                              : null,
                          label: '$w',
                          sub: 'wk',
                          selected: _weeks == w,
                          onTap: () => setState(() => _weeks = w),
                          colors: colors,
                          expanded: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SegmentedField(
                    label: 'Sessions per week',
                    hint: formatStreakFloorHint(_spw),
                    colors: colors,
                    children: [
                      for (final n in _spwOpts)
                        _SegChip(
                          key: n == _spw
                              ? const Key('programs-sessions-week')
                              : null,
                          label: '$n',
                          sub: '× / wk',
                          selected: _spw == n,
                          onTap: () => setState(() => _spw = n),
                          colors: colors,
                          expanded: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AgonCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Starting continuous distance',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.inkDim,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Sounding',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.inkFaint,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('programs-self-capacity'),
                          controller: _selfCapCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            suffixText: 'm',
                            filled: true,
                            fillColor: colors.bg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colors.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colors.line),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your best recent non-stop pool swim. Used when history is thin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.inkFaint,
                            height: 1.35,
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
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.amber,
                        height: 1.35,
                      ),
                    ),
                  ],
                  // Clear of sticky CTA + safe area so the last card isn’t clipped.
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: colors.bg,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.bg.withValues(alpha: 0),
                  colors.bg,
                  colors.bg,
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
            child: SafeArea(
              top: false,
              child: FilledButton(
                key: const Key('programs-create-submit'),
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accentInk,
                        ),
                      )
                    : const Text(
                        'Chart my Agon',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscloseCard extends StatelessWidget {
  const _DiscloseCard({
    required this.poolOnly,
    required this.onToggle,
    required this.colors,
  });

  final bool poolOnly;
  final ValueChanged<bool> onToggle;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('programs-pool-only-disclosure'),
      decoration: BoxDecoration(
        color: Color.lerp(colors.pool, colors.bgElev, 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color.lerp(colors.accent, colors.line, 0.62)!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 22,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.poolLine)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agon · Pool swim',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pool swims only',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This Agon plans pool sessions and nothing else. Open-water isn’t included yet.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.inkDim,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Divider(height: 1, color: colors.poolLine),
                const SizedBox(height: 10),
                _Bullet(
                  lead: 'Plans',
                  body: 'a warm-up, main set and cool-down for each pool day',
                  colors: colors,
                ),
                const SizedBox(height: 7),
                _Bullet(
                  lead: 'Reads',
                  body: 'badminton, strength and runs only to flag a heavy day',
                  colors: colors,
                ),
                const SizedBox(height: 7),
                _Bullet(
                  lead: 'Runs on your device',
                  body: 'from rules and templates. No Coach, no cloud',
                  colors: colors,
                ),
                const SizedBox(height: 10),
                InkWell(
                  key: const Key('programs-pool-only-checkbox'),
                  onTap: () => onToggle(!poolOnly),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Checkbox(
                        value: poolOnly,
                        onChanged: (v) => onToggle(v ?? false),
                        activeColor: colors.accent,
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
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.lead,
    required this.body,
    required this.colors,
  });

  final String lead;
  final String body;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: lead,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: ' $body',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.inkDim,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetTimeField extends StatelessWidget {
  const _TargetTimeField({
    required this.enabled,
    required this.targetSec,
    required this.paceHint,
    required this.colors,
    required this.onPick,
    required this.onClearOrAdd,
  });

  final bool enabled;
  final int? targetSec;
  final String? paceHint;
  final FathomColors colors;
  final VoidCallback onPick;
  final VoidCallback onClearOrAdd;

  @override
  Widget build(BuildContext context) {
    return AgonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Target time',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.inkDim,
                ),
              ),
              const Spacer(),
              Text(
                paceHint ?? (enabled ? 'optional' : 'off'),
                style: TextStyle(
                  fontSize: 11,
                  color: colors.inkFaint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: colors.bg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const Key('programs-target-time'),
              onTap: onPick,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.line),
                ),
                child: Column(
                  children: [
                    Text(
                      enabled && targetSec != null
                          ? formatMmSs(targetSec!)
                          : 'Tap to set',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: colors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scroll picker · easier than ±15s',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  enabled
                      ? 'Optional pace target for the goal swim'
                      : 'No time target — distance only',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.inkFaint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              TextButton(
                onPressed: onClearOrAdd,
                child: Text(
                  enabled ? 'Clear' : 'Add time',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.label,
    required this.hint,
    required this.valueChild,
    required this.onMinus,
    required this.onPlus,
    required this.colors,
    this.valueKey,
    this.footer,
  });

  final String label;
  final String hint;
  final Widget valueChild;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final FathomColors colors;
  final Key? valueKey;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AgonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.inkDim,
                ),
              ),
              const Spacer(),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.inkFaint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StepBtn(label: '−', onTap: onMinus, colors: colors),
              Expanded(
                child: KeyedSubtree(key: valueKey, child: valueChild),
              ),
              _StepBtn(label: '+', onTap: onPlus, colors: colors),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final VoidCallback? onTap;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: colors.line),
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: colors.ink,
          ),
        ),
      ),
    );
  }
}

class _SegmentedField extends StatelessWidget {
  const _SegmentedField({
    required this.label,
    required this.hint,
    required this.children,
    required this.colors,
  });

  final String label;
  final String hint;
  final List<Widget> children;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return AgonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.inkDim,
                ),
              ),
              const Spacer(),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.inkFaint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: children[i]),
            ],
          ]),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  const _SegChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    this.sub,
    this.expanded = false,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final FathomColors colors;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: selected ? colors.ink : colors.bg,
      borderRadius: BorderRadius.circular(expanded ? 12 : 999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(expanded ? 12 : 999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 6 : 12,
            vertical: expanded ? 11 : 7,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(expanded ? 12 : 999),
            border: Border.all(
              color: selected ? Colors.transparent : colors.line,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: expanded ? 14 : 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.bg : colors.inkDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: (selected ? colors.bg : colors.inkDim)
                        .withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return expanded ? child : child;
  }
}
