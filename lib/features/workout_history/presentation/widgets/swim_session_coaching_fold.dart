import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_invent_guard.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_insight.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/view/swim_chart_expanded_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_interval_sets.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

/// Coach-led athlete fold for pool / open-water swim detail.
class SwimSessionCoachingFold extends StatefulWidget {
  const SwimSessionCoachingFold({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedStreamPoints,
    this.digDeeperOverride,
    this.insightOverride,
    this.lapsOverride,
    this.hrPointsOverride,
    this.scrollController,
  });

  final WorkoutSummary workout;
  final RunSessionStore? runSessionStore;
  final List<RunStreamPoint>? preloadedStreamPoints;

  /// Test seam — when non-null, skips SharedPreferences dig-deeper read.
  final bool? digDeeperOverride;

  /// Test seam — skip repository load when set.
  final SwimSessionInsight? insightOverride;

  /// Test seam — invent-guarded laps for charts/intervals when set with insight.
  final List<SwimLapMetrics>? lapsOverride;

  /// Test seam — locked HR points when set with insightOverride.
  final List<RunStreamPoint>? hrPointsOverride;

  final ScrollController? scrollController;

  @override
  State<SwimSessionCoachingFold> createState() =>
      _SwimSessionCoachingFoldState();
}

class _SwimSessionCoachingFoldState extends State<SwimSessionCoachingFold> {
  final _chartsKey = GlobalKey();
  final _intervalsKey = GlobalKey();
  final _findingsKey = GlobalKey();

  Future<_FoldPayload>? _future;
  bool _findingsExpanded = false;
  bool _includeFiltered = false;
  SwimChartSeries _series = SwimChartSeries.pace;

  bool get _digDeeper {
    if (widget.digDeeperOverride != null) return widget.digDeeperOverride!;
    try {
      return sl<SharedPreferences>().getBool(GateAPrefs.swimDigDeeper) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.insightOverride != null) return;
    _future = _load();
  }

  Future<_FoldPayload> _load() async {
    final summary = widget.workout;
    final focus = CanonicalSwimSession.fromWorkoutSummary(summary);
    if (focus == null) {
      return _FoldPayload.partial(
        story: 'Session logged — swimming details unavailable.',
        kpis: SwimSessionKpis(
          distanceM: summary.distanceM,
          durationPrimaryLabel: summary.durationSec > 0
              ? _fmtDur(summary.durationSec)
              : null,
        ),
      );
    }

    WorkoutHistoryRepository? repo;
    try {
      repo = sl<WorkoutHistoryRepository>();
    } catch (_) {
      repo = null;
    }

    SwimDiagnosisReport? report;
    List<CanonicalSwimSession> history = const [];
    if (repo != null) {
      try {
        report = await repo.loadSwimDiagnosisReport(
          focusWorkoutNumber: summary.number,
        );
        history = await repo.loadAllCanonicalSwims();
      } catch (_) {
        report = null;
      }
    }

    final hrPoints = await _resolveHrPoints();
    final lockedHr = _kpisFromHrPoints(hrPoints);
    final inventGuarded = filterSwimLapsForAnalytics(
      focus.p0.laps,
      poolLengthM: focus.poolLengthM,
      includeFiltered: false,
    );

    final insight = buildSwimSessionInsight(
      focus: focus,
      inventGuardedLaps: inventGuarded,
      sessionDiagnoses: report?.sessionDiagnoses ?? const [],
      recentHistory: history,
      lockedHr: lockedHr,
    );

    return _FoldPayload(
      insight: insight,
      focus: focus,
      inventGuardedLaps: inventGuarded,
      allLaps: focus.p0.laps,
      hrPoints: hrPoints,
    );
  }

  Future<List<RunStreamPoint>> _resolveHrPoints() async {
    final preloaded = widget.preloadedStreamPoints;
    if (preloaded != null) {
      return [
        for (final p in preloaded)
          if (p.hrBpm != null) p,
      ];
    }

    RunSessionStore? store = widget.runSessionStore;
    if (store == null) {
      try {
        store = sl<RunSessionStore>();
      } catch (_) {
        return const [];
      }
    }
    try {
      final pages = await store.loadDataPages(widget.workout.number);
      return lockInSessionHrPoints(
        pages,
        workoutType: widget.workout.observedType ?? widget.workout.type,
        hrMin: widget.workout.hrMin,
        hrMax: widget.workout.hrMax,
      );
    } catch (_) {
      return const [];
    }
  }

  SwimLockedHrKpis? _kpisFromHrPoints(List<RunStreamPoint> points) {
    final hrs = [
      for (final p in points)
        if (p.hrBpm != null) p.hrBpm!,
    ];
    if (hrs.length < 2) return null;
    final avg = (hrs.reduce((a, b) => a + b) / hrs.length).round();
    final max = hrs.reduce((a, b) => a > b ? a : b);
    return SwimLockedHrKpis(avgBpm: avg, maxBpm: max);
  }

  void _scrollTo(GlobalKey key, {bool expandFindings = false}) {
    if (expandFindings) {
      setState(() => _findingsExpanded = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final digDeeper = _digDeeper;

    if (widget.insightOverride != null) {
      final laps = widget.lapsOverride ?? const <SwimLapMetrics>[];
      return _buildReady(
        context,
        digDeeper: digDeeper,
        payload: _FoldPayload(
          insight: widget.insightOverride!,
          inventGuardedLaps: laps,
          allLaps: laps,
          hrPoints: widget.hrPointsOverride ?? const [],
        ),
      );
    }

    return FutureBuilder<_FoldPayload>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _LoadingFold(workout: widget.workout);
        }
        final payload = snap.data ??
            _FoldPayload.partial(
              story: 'Coaching unavailable for this session.',
              kpis: SwimSessionKpis(
                distanceM: widget.workout.distanceM,
                durationPrimaryLabel: widget.workout.durationSec > 0
                    ? _fmtDur(widget.workout.durationSec)
                    : null,
              ),
            );
        return _buildReady(context, digDeeper: digDeeper, payload: payload);
      },
    );
  }

  Widget _buildReady(
    BuildContext context, {
    required bool digDeeper,
    required _FoldPayload payload,
  }) {
    final insight = payload.insight;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final poolLength = payload.focus?.poolLengthM;
    final active = filterSwimLapsForAnalytics(
      payload.allLaps.isNotEmpty ? payload.allLaps : payload.inventGuardedLaps,
      poolLengthM: poolLength,
      includeFiltered: digDeeper && _includeFiltered,
    );
    final filteredCount = countInventGuardFilteredLaps(
      payload.allLaps.isNotEmpty ? payload.allLaps : payload.inventGuardedLaps,
      poolLengthM: poolLength,
    );
    final hrPoints = [
      for (final p in payload.hrPoints)
        if (p.hrBpm != null) p,
    ];
    final hasHr = hrPoints.length >= 2;
    final hasCharts = hasHr ||
        active.any(
          (l) =>
              (l.paceSecPer100m != null && l.paceSecPer100m! > 0) ||
              (l.swolf != null && l.swolf! > 0) ||
              (l.strokes != null && l.strokes! > 0),
        );
    final hasIntervals = active.isNotEmpty;
    final hasFindings = insight.secondaryFindings.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          workoutTypeLabel(widget.workout.type),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          key: const Key('swim-coach-story'),
          insight.story,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        if (insight.chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in insight.chips)
                _ComparisonChipView(chip: c),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (insight.primaryTip != null)
          _PrimaryTipCard(tip: insight.primaryTip!)
        else
          Text(
            key: const Key('swim-empty-tip'),
            'No coaching tip for this session — KPIs and charts still apply.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 14),
        _KpiStrip(kpis: insight.kpis),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (hasCharts)
              ActionChip(
                key: const Key('swim-jump-charts'),
                label: const Text('Charts'),
                onPressed: () => _scrollTo(_chartsKey),
              ),
            if (hasIntervals)
              ActionChip(
                key: const Key('swim-jump-intervals'),
                label: const Text('Intervals'),
                onPressed: () => _scrollTo(_intervalsKey),
              ),
            if (hasFindings)
              ActionChip(
                key: const Key('swim-jump-findings'),
                label: const Text('Findings'),
                onPressed: () =>
                    _scrollTo(_findingsKey, expandFindings: true),
              ),
          ],
        ),
        if (digDeeper && filteredCount > 0) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _includeFiltered,
            onChanged: (v) =>
                setState(() => _includeFiltered = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Include filtered laps'),
            subtitle: Text(
              _includeFiltered
                  ? 'Showing $filteredCount filtered laps'
                  : '$filteredCount hidden by invent-guard',
            ),
          ),
        ],
        if (hasCharts) ...[
          const SizedBox(height: 12),
          SwimSessionCharts(
            key: _chartsKey,
            laps: active,
            hrPoints: hrPoints,
            initialSeries: _series,
            onSeriesChanged: (s) => _series = s,
            onExpand: (current) => SwimChartExpandedRoute.open(
              context,
              laps: active,
              series: current,
              hrPoints: hrPoints,
            ),
          ),
        ],
        if (hasIntervals) ...[
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _intervalsKey,
            child: SwimIntervalSetsView(
              laps: active,
              poolLengthM: poolLength,
              showDevIndex: digDeeper,
            ),
          ),
        ],
        if (hasFindings) ...[
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _findingsKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  key: const Key('swim-more-findings'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'More findings',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    _findingsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  onTap: () => setState(
                    () => _findingsExpanded = !_findingsExpanded,
                  ),
                ),
                if (_findingsExpanded)
                  for (final f in insight.secondaryFindings)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.title),
                      subtitle: Text(f.body),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FoldPayload {
  _FoldPayload({
    required this.insight,
    this.focus,
    this.inventGuardedLaps = const [],
    this.allLaps = const [],
    this.hrPoints = const [],
  });

  factory _FoldPayload.partial({
    required String story,
    required SwimSessionKpis kpis,
  }) {
    return _FoldPayload(
      insight: SwimSessionInsight(
        story: story,
        chips: const [],
        kpis: kpis,
        secondaryFindings: const [],
      ),
    );
  }

  final SwimSessionInsight insight;
  final CanonicalSwimSession? focus;
  final List<SwimLapMetrics> inventGuardedLaps;
  final List<SwimLapMetrics> allLaps;
  final List<RunStreamPoint> hrPoints;
}

class _LoadingFold extends StatelessWidget {
  const _LoadingFold({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          workoutTypeLabel(workout.type),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Reading session…',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _KpiStrip(
          kpis: SwimSessionKpis(
            distanceM: workout.distanceM,
            durationPrimaryLabel:
                workout.durationSec > 0 ? _fmtDur(workout.durationSec) : null,
          ),
        ),
      ],
    );
  }
}

class _ComparisonChipView extends StatelessWidget {
  const _ComparisonChipView({required this.chip});

  final SwimComparisonChip chip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = switch (chip.direction) {
      SwimChipDirection.up => scheme.primary,
      SwimChipDirection.down => scheme.error,
      SwimChipDirection.flat => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '${chip.label} ${chip.deltaLabel}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _PrimaryTipCard extends StatelessWidget {
  const _PrimaryTipCard({required this.tip});

  final SwimPrimaryTip tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('swim-primary-tip'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tip.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tip.why,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.kpis});

  final SwimSessionKpis kpis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = <Widget>[];
    if (kpis.distanceM != null) {
      primary.add(_KpiPrimary(
        label: 'Distance',
        value: '${kpis.distanceM} m',
      ));
    }
    if (kpis.durationPrimaryLabel != null) {
      primary.add(_KpiPrimary(
        label: 'Duration',
        value: kpis.durationPrimaryLabel!,
        hint: kpis.durationHint,
      ));
    }

    final secondary = <String>[];
    if (kpis.avgPaceSecPer100m != null) {
      secondary.add('${kpis.avgPaceSecPer100m}s/100m');
    }
    if (kpis.avgSwolf != null) {
      secondary.add('SWOLF ${kpis.avgSwolf}');
    }
    if (kpis.avgHr != null) {
      secondary.add('HR ${kpis.avgHr}');
      if (kpis.maxHr != null) secondary.add('max ${kpis.maxHr}');
    }

    return Column(
      key: const Key('swim-kpi-strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary.isNotEmpty)
          Row(
            children: [
              for (var i = 0; i < primary.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: primary[i]),
              ],
            ],
          ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            secondary.join('  ·  '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _KpiPrimary extends StatelessWidget {
  const _KpiPrimary({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

String _fmtDur(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
