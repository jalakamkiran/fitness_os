import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_route.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_bloc.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_event.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_state.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/hr_sparkline.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';

/// Calm Home Today instrument. At most one tiny HR spark; no hypnogram,
/// workout charts, food, composites, or reasoner settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.bloc});

  /// Optional injected bloc for widget tests.
  final HomeBloc? bloc;

  @override
  Widget build(BuildContext context) {
    final provided = bloc;
    if (provided != null) {
      return BlocProvider<HomeBloc>.value(
        value: provided..add(const HomeStarted()),
        child: const _HomeView(),
      );
    }
    return BlocProvider(
      create: (_) => sl<HomeBloc>()..add(const HomeStarted()),
      child: const _HomeView(),
    );
  }
}

/// Renders a frozen [HomeSnapshot] without DI — used by state widget tests.
class HomeSnapshotView extends StatelessWidget {
  const HomeSnapshotView({super.key, required this.snapshot});

  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FathomColors.of(context).bg,
      body: SafeArea(
        child: _HomeBody(snapshot: snapshot),
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: BlocBuilder<HomeBloc, HomeState>(
          builder: (context, state) {
            if (state is HomeLoadInProgress || state is HomeInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is HomeFailure) {
              return Center(child: Text(state.message));
            }
            final ready = state as HomeReady;
            return _HomeBody(snapshot: ready.snapshot, message: ready.message);
          },
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.snapshot, this.message});

  final HomeSnapshot snapshot;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final p = snapshot.precedence;
    final muted = p == HomePrecedence.syncInProgress ||
        p == HomePrecedence.syncFailed;

    return CustomScrollView(
      key: Key('home_state_${p.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: _BrandHeader(snapshot: snapshot),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _TodayChip(colors: colors),
                const Spacer(),
                _SyncPill(label: snapshot.syncPillLabel, colors: colors),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SyncCard(snapshot: snapshot),
                if (message != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    message!,
                    style: TextStyle(color: colors.hot, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                ..._sectionsFor(
                  snapshot,
                  muted: muted,
                  staleColor: colors.amber,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sectionsFor(
    HomeSnapshot s, {
    required bool muted,
    required Color staleColor,
  }) {
    switch (s.precedence) {
      case HomePrecedence.notPaired:
        return [
          const _NoteCard(
            text:
                'Sleep, totals, body HR, and today’s sessions unlock after pairing — no invented metrics.',
          ),
        ];
      case HomePrecedence.pairedNeverSynced:
        return [
          const _NoteCard(
            text: 'Day picture appears after the first successful sync.',
          ),
        ];
      case HomePrecedence.syncInProgress:
      case HomePrecedence.syncFailed:
      case HomePrecedence.dataAvailable:
        return _todayStack(s, muted: muted, staleColor: staleColor);
    }
  }

  List<Widget> _todayStack(
    HomeSnapshot s, {
    required bool muted,
    required Color staleColor,
  }) {
    final out = <Widget>[];

    if (s.precedence == HomePrecedence.syncFailed &&
        s.lastSyncedLabel != null) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            key: const Key('home-stale-cue'),
            s.lastSyncedLabel!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: staleColor,
            ),
          ),
        ),
      );
    }

    if (s.sleepDurationLabel != null) {
      out.add(_SleepStrip(snapshot: s, muted: muted));
      out.add(const SizedBox(height: 12));
    }

    if (s.caloriesLabel != null ||
        s.stepsLabel != null ||
        s.workoutTimeLabel != null) {
      out.add(_TotalsSection(snapshot: s, muted: muted));
      out.add(const SizedBox(height: 12));
    } else if (s.precedence == HomePrecedence.syncInProgress &&
        !s.hasDayStackContent) {
      out.add(
        const _NoteCard(
          text:
              'Previous snapshot stays if present; otherwise placeholders — no charts while syncing.',
        ),
      );
      return out;
    }

    if (s.bodyHrLabel != null) {
      out.add(_BodyHrCard(snapshot: s, muted: muted));
      out.add(const SizedBox(height: 12));
    }

    out.add(_TodaySessionsSection(snapshot: s, muted: muted));
    return out;
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.snapshot});

  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.pool,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.poolLine),
          ),
          child: Text(
            'F',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: colors.accentInk,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fathom',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                      letterSpacing: -0.4,
                    ),
              ),
              Text(
                snapshot.brandSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.colors});

  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('home-period-today'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Text(
        'Today',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: colors.ink,
        ),
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.label, required this.colors});

  final String label;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final tone = switch (label) {
      'Unpaired' || 'Failed' => colors.hot,
      'Waiting' || 'Syncing' => colors.amber,
      _ => colors.accent,
    };

    return Semantics(
      label: 'Sync status $label',
      child: Container(
        key: ValueKey('sync-pill-$label'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.bgElev,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: colors.inkDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.snapshot});

  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final cta = _ctaFor(snapshot.precedence);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Watch',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.syncTitle,
            key: const Key('home-sync-title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.syncCaption,
            style: TextStyle(color: colors.inkDim, height: 1.4),
          ),
          if (cta != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              key: Key(cta.key),
              onPressed: () => cta.onPressed(context),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(cta.label),
            ),
          ],
        ],
      ),
    );
  }

  _Cta? _ctaFor(HomePrecedence p) => switch (p) {
        HomePrecedence.notPaired => _Cta(
            key: 'home-cta-pair',
            label: 'Pair watch',
            onPressed: (ctx) => DevicePairingRoute.go(ctx),
          ),
        HomePrecedence.pairedNeverSynced => const _Cta(
            key: 'home-cta-sync',
            label: 'Sync now',
            onPressed: _requestSync,
          ),
        HomePrecedence.syncFailed => const _Cta(
            key: 'home-cta-retry',
            label: 'Retry sync',
            onPressed: _requestSync,
          ),
        _ => null,
      };
}

class _Cta {
  const _Cta({
    required this.key,
    required this.label,
    required this.onPressed,
  });

  final String key;
  final String label;
  final void Function(BuildContext) onPressed;
}

void _requestSync(BuildContext context) {
  try {
    context.read<HomeBloc>().add(const HomeSyncRequested());
  } catch (_) {
    // Snapshot-only previews (widget tests) have no HomeBloc.
  }
}

class _SleepStrip extends StatelessWidget {
  const _SleepStrip({required this.snapshot, this.muted = false});

  final HomeSnapshot snapshot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final ink = muted ? colors.inkFaint : colors.ink;
    return Opacity(
      opacity: muted ? 0.62 : 1,
      child: _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last night',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.inkFaint,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              snapshot.sleepDurationLabel!,
              key: const Key('home-sleep-duration'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.6,
              ),
            ),
            if (snapshot.sleepWindowLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                snapshot.sleepWindowLabel!,
                key: const Key('home-sleep-window'),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.inkDim,
                  fontFamily: 'IBMPlexMono',
                ),
              ),
            ],
            if (snapshot.sleepFeelCue != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('home-sleep-feel'),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.pool.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.line),
                ),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.inkDim,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: 'Feel on wake: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                        ),
                      ),
                      TextSpan(text: snapshot.sleepFeelCue),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.snapshot, this.muted = false});

  final HomeSnapshot snapshot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final valueColor = muted ? colors.inkFaint : colors.ink;

    return Opacity(
      opacity: muted ? 0.62 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  label: 'Calories',
                  value: snapshot.caloriesLabel ?? '—',
                  valueColor: valueColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Kpi(
                  label: 'Steps',
                  value: snapshot.stepsLabel ?? '—',
                  valueColor: valueColor,
                ),
              ),
            ],
          ),
          if (snapshot.workoutTimeLabel != null) ...[
            const SizedBox(height: 10),
            _Kpi(
              label: 'Workout time',
              value: snapshot.workoutTimeLabel!,
              valueColor: valueColor,
              wide: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.valueColor,
    this.wide = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            key: Key('home-kpi-$label'),
            style: TextStyle(
              fontSize: wide ? 22 : 28,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyHrCard extends StatelessWidget {
  const _BodyHrCard({required this.snapshot, this.muted = false});

  final HomeSnapshot snapshot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final ink = muted ? colors.inkFaint : colors.ink;
    final spark = snapshot.bodyHrSparkSamples.length >= 2;

    return Opacity(
      opacity: muted ? 0.62 : 1,
      child: _SurfaceCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Body · today',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snapshot.bodyHrLabel} bpm',
                    key: const Key('home-body-hr'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'min · avg · max',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (spark)
              SizedBox(
                key: const Key('home-hr-spark'),
                width: 88,
                child: HrSparkline(
                  samples: snapshot.bodyHrSparkSamples,
                  height: 28,
                  compact: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodaySessionsSection extends StatelessWidget {
  const _TodaySessionsSection({required this.snapshot, this.muted = false});

  final HomeSnapshot snapshot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final sessions = snapshot.todaySessions;

    if (sessions.isEmpty) {
      return Opacity(
        opacity: muted ? 0.62 : 1,
        child: _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sessions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No sessions yet today',
                key: const Key('home-sessions-empty'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: muted ? colors.inkFaint : colors.ink,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sleep and body stay useful on a rest day — no fake workout.',
                style: TextStyle(color: colors.inkDim, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return Opacity(
      opacity: muted ? 0.62 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'TODAY’S SESSIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.inkFaint,
                ),
              ),
              const Spacer(),
              Text(
                '${sessions.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < sessions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _SessionCard(card: sessions[i], index: i),
          ],
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.card, required this.index});

  final HomeTodaySessionCard card;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Material(
      color: colors.bgElev,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('home-session-$index'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => WorkoutDetailRoute.go(context, card.workout),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (card.whenLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            card.whenLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '›',
                    style: TextStyle(
                      fontSize: 18,
                      color: colors.inkFaint,
                    ),
                  ),
                ],
              ),
              if (card.meta.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.line),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < card.meta.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.meta[i].label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.inkFaint,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              card.meta[i].value,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: colors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return _SurfaceCard(
      child: Text(
        text,
        style: TextStyle(color: colors.inkDim, height: 1.45),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.line),
      ),
      child: child,
    );
  }
}
