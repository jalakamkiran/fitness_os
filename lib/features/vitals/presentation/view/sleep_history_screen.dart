import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_session_card.dart';

/// Month browser — pick a night (or nap) and open detail.
class SleepHistoryScreen extends StatefulWidget {
  const SleepHistoryScreen({
    super.key,
    this.repository,
    this.initialYear,
    this.initialMonth,
  });

  final VitalsRepository? repository;
  final int? initialYear;
  final int? initialMonth;

  @override
  State<SleepHistoryScreen> createState() => _SleepHistoryScreenState();
}

class _SleepHistoryScreenState extends State<SleepHistoryScreen> {
  late int _year;
  late int _month;
  bool _loading = true;
  List<SleepSessionSummary> _sessions = const [];
  Map<String, int> _scores = const {};
  Map<String, int> _awakeMinutes = const {};

  VitalsRepository get _repo => widget.repository ?? sl<VitalsRepository>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.initialYear ?? now.year;
    _month = widget.initialMonth ?? now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await _repo.loadSleepSessionsForMonth(
      year: _year,
      month: _month,
    );
    // Idempotent presentation coalesce for stale pre-Sync fragment prefs.
    final sessions = List<SleepSessionSummary>.from(
      SleepDay.coalesceNocturnalSessions(raw),
    )..sort((a, b) => b.endUnix.compareTo(a.endUnix));
    final scores = <String, int>{};
    final awakeByKey = <String, int>{};
    await Future.wait(sessions.map((s) async {
      final summary = await _repo.loadTruSleepSummary(s);
      var score = summary?.sleepScore;
      // Coalesced bounds may miss enrich until Sync; try overlapping raw keys.
      if (score == null || score <= 0) {
        for (final r in raw) {
          if (r.beginUnix >= s.endUnix || r.endUnix <= s.beginUnix) continue;
          final alt = await _repo.loadTruSleepSummary(r);
          final altScore = alt?.sleepScore;
          if (altScore != null && altScore > 0) {
            score = altScore;
            break;
          }
        }
      }
      if (score != null && score > 0) {
        scores[s.mergeKey] = score;
      }

      var stages = await _repo.loadSleepStages(s);
      if (stages.isEmpty) {
        for (final r in raw) {
          if (r.beginUnix >= s.endUnix || r.endUnix <= s.beginUnix) continue;
          final alt = await _repo.loadSleepStages(r);
          if (alt.isNotEmpty) {
            stages = alt;
            break;
          }
        }
      }
      final awake = stageMinutesOf(stages).awake;
      if (awake > 0) {
        awakeByKey[s.mergeKey] = awake;
      }
    }));
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _scores = scores;
      _awakeMinutes = awakeByKey;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final overnightCount = _sessions
        .where(
          (s) => sleepIsMainOvernight(
            s,
            scientificMain: (_scores[s.mergeKey] ?? 0) > 0,
          ),
        )
        .length;
    final napCount = _sessions
        .where(
          (s) => sleepIsIntentionalNap(
            s,
            scientificMain: (_scores[s.mergeKey] ?? 0) > 0,
          ),
        )
        .length;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sleep history',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            Text(
              'Browse by month · open any night',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    sleepMonthLabel(_year, _month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (!_loading && _sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '$overnightCount overnight'
                '${napCount > 0 ? ' · $napCount nap${napCount == 1 ? '' : 's'}' : ''}'
                ' · tap a row for TruSleep detail',
                textAlign: TextAlign.center,
                style: FathomTextStyles.mono(
                  fontSize: 11,
                  color: colors.inkFaint,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'No nights this month',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: colors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Wear overnight, Sync from Recovery · Sleep, '
                                    'then pick the day here.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.inkDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = _sessions[i];
                          return InkWell(
                            onTap: () => SleepDetailRoute.go(context, s),
                            borderRadius: BorderRadius.circular(18),
                            child: SleepSessionCard(
                              session: s,
                              compact: true,
                              sleepScore: _scores[s.mergeKey],
                              awakeMinutes: _awakeMinutes[s.mergeKey],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
