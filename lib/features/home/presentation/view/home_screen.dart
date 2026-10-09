import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_route.dart';
import 'package:fitness_os/features/diagnostics/presentation/view/advanced_tools_route.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_bloc.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_event.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_state.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_route.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';
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
        // Agon dock sits under period chrome (matches home-prototype HTML).
        if (snapshot.precedence == HomePrecedence.dataAvailable ||
            snapshot.precedence == HomePrecedence.syncInProgress ||
            snapshot.precedence == HomePrecedence.syncFailed)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _HomeAgonDock(),
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
                if (snapshot.precedence == HomePrecedence.dataAvailable ||
                    snapshot.precedence == HomePrecedence.syncInProgress ||
                    snapshot.precedence == HomePrecedence.syncFailed) ...[
                  const SizedBox(height: 12),
                  const _HomeOdysseyStrip(),
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

/// Horizontal Agon sport dock — Swim live / Chart, Strength+Run soon.
class _HomeAgonDock extends StatefulWidget {
  const _HomeAgonDock();

  @override
  State<_HomeAgonDock> createState() => _HomeAgonDockState();
}

class _HomeAgonDockState extends State<_HomeAgonDock> {
  ProgramsController? _controller;

  @override
  void initState() {
    super.initState();
    if (GetIt.I.isRegistered<ProgramsController>()) {
      _controller = GetIt.I<ProgramsController>();
      _controller!.addListener(_onChanged);
      // Controller defaults to loading=true before any load() — do not wait for
      // sync/invalidation. Populate Agon from the store as soon as Home mounts.
      if (_controller!.active == null) {
        // ignore: discarded_futures
        _controller!.load();
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // ProgramsEntry.load() notifies during route mount; never setState mid-build.
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final c = _controller;
    final active = c?.hasActive == true;
    final cap = active && c!.active != null
        ? formatWeekChip(c.active!, DateTime.now()).replaceFirst('Week ', 'Wk ')
        : (active ? 'Live' : 'Chart');

    return Column(
      key: const Key('home-programs-cta'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AGONS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: colors.inkFaint,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DockBtn(
                name: 'Swim',
                cap: active ? '$cap · live' : 'Tap to start',
                active: active,
                dashed: !active,
                icon: Icons.waves_rounded,
                onTap: () => ProgramsRoute.go(context),
                colors: colors,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DockBtn(
                name: 'Strength',
                cap: 'Soon',
                active: false,
                ghost: true,
                icon: Icons.fitness_center_rounded,
                colors: colors,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DockBtn(
                name: 'Run',
                cap: 'Soon',
                active: false,
                ghost: true,
                icon: Icons.directions_run_rounded,
                colors: colors,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DockBtn extends StatelessWidget {
  const _DockBtn({
    required this.name,
    required this.cap,
    required this.active,
    required this.icon,
    required this.colors,
    this.onTap,
    this.ghost = false,
    this.dashed = false,
  });

  final String name;
  final String cap;
  final bool active;
  final bool ghost;
  final bool dashed;
  final IconData icon;
  final VoidCallback? onTap;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final border = active
        ? Color.lerp(colors.accent, colors.line, 0.45)!
        : dashed
            ? Color.lerp(colors.accent, colors.line, 0.5)!
            : colors.line;
    final bg = active
        ? Color.lerp(colors.accent, colors.bgElev, 0.9)!
        : colors.bgElev;
    final icoBg = active
        ? colors.accent
        : dashed
            ? colors.bg
            : colors.bg;
    final icoColor = active
        ? colors.accentInk
        : ghost
            ? colors.inkFaint
            : colors.inkDim;

    final child = Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: border,
          style: dashed || ghost ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Opacity(
        opacity: ghost ? 0.55 : 1,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: icoBg,
                    borderRadius: BorderRadius.circular(11),
                    border: dashed
                        ? Border.all(
                            color: Color.lerp(colors.accent, colors.line, 0.45)!,
                          )
                        : ghost
                            ? Border.all(color: colors.line)
                            : null,
                  ),
                  child: Icon(icon, size: 20, color: icoColor),
                ),
                if (active)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors.up,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.bgElev, width: 2),
                      ),
                    ),
                  ),
                if (dashed)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '+',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: colors.accentInk,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: colors.ink,
                    ),
                  ),
                  Text(
                    cap,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? Color.lerp(colors.accent, colors.ink, 0.35)!
                          : colors.inkFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

/// Compact Odyssey strip when an Agon is live (hidden if game layer off / none).
class _HomeOdysseyStrip extends StatefulWidget {
  const _HomeOdysseyStrip();

  @override
  State<_HomeOdysseyStrip> createState() => _HomeOdysseyStripState();
}

class _HomeOdysseyStripState extends State<_HomeOdysseyStrip> {
  ProgramsController? _controller;

  @override
  void initState() {
    super.initState();
    if (GetIt.I.isRegistered<ProgramsController>()) {
      _controller = GetIt.I<ProgramsController>();
      _controller!.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.hasActive || c.hideGameLayer) {
      return const SizedBox.shrink();
    }
    final colors = FathomColors.of(context);
    final bronze = agonBronzeOf(context);
    final ledger = c.ledger;
    final line = Color.lerp(bronze, colors.line, 0.68)!;

    return Material(
      color: Color.lerp(bronze, colors.bgElev, 0.87)!,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('home-odyssey-strip'),
        onTap: () => ProgramsRoute.go(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(bronze, colors.bgElev, 0.87)!,
                colors.bgElev,
              ],
            ),
          ),
          child: Row(
            children: [
              Text(
                'YOUR\nODYSSEY',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.7,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color: bronze,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              _HomeOdStat(
                value: '${ledger.currentStreakWeeks}',
                unit: ' wk',
                label: 'Streak',
                colors: colors,
                line: line,
              ),
              _HomeOdStat(
                value: formatMeters(ledger.totalXp),
                label: 'Areté',
                colors: colors,
                line: line,
              ),
              _HomeOdStat(
                value: '${ledger.level}',
                label: 'Depth',
                colors: colors,
                line: line,
              ),
              Icon(Icons.chevron_right, size: 18, color: colors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeOdStat extends StatelessWidget {
  const _HomeOdStat({
    required this.value,
    required this.label,
    required this.colors,
    required this.line,
    this.unit,
  });

  final String value;
  final String? unit;
  final String label;
  final FathomColors colors;
  final Color line;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: colors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                children: unit == null
                    ? null
                    : [
                        TextSpan(
                          text: unit,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.inkDim,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
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
        IconButton(
          key: const Key('home-advanced-tools'),
          tooltip: 'Advanced',
          icon: Icon(Icons.tune, color: colors.inkDim),
          onPressed: () => AdvancedToolsRoute.go(context),
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
