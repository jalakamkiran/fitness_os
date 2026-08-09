import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_session_card.dart';

/// Month history list (S2) — charts deferred; list first.
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
    final sessions = await _repo.loadSleepSessionsForMonth(
      year: _year,
      month: _month,
    );
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
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
              'Sleep · history',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'charts later · list first',
              textAlign: TextAlign.center,
              style: FathomTextStyles.mono(
                fontSize: 11,
                color: colors.inkFaint,
              ),
            ),
          ),
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
                              child: Text(
                                'No sleep sessions stored yet. Wear overnight '
                                '(prefer night 2 after pairing), then Sync.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.inkDim,
                                ),
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
