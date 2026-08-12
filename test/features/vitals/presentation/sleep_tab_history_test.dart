import 'dart:async';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_screen.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_tab_screen.dart';

class _FakeRepo implements VitalsRepository {
  _FakeRepo({
    this.sessions = const [],
    Map<String, MorningWellness>? wellnessAnswers,
    this.saveFails = false,
  }) : wellnessAnswers = wellnessAnswers ?? {};

  List<SleepSessionSummary> sessions;
  final Map<String, MorningWellness> wellnessAnswers;
  final bool saveFails;
  int saveWellnessCalls = 0;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get sessionReady => true;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => sessions;

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) async =>
      const [];

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => const [];

  @override
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey) async =>
      const [];

  @override
  Future<List<DailyHrSample>> loadSleepHrWindow({
    required int beginUnix,
    required int endUnix,
  }) async =>
      const [];

  @override
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session) async =>
      false;

  @override
  Future<MorningWellness?> loadMorningWellness(
    SleepSessionSummary session,
  ) async =>
      wellnessAnswers[session.mergeKey];

  @override
  Future<void> saveMorningWellness(
    SleepSessionSummary session,
    MorningWellness wellness,
  ) async {
    saveWellnessCalls++;
    if (saveFails) return;
    if (!wellness.isComplete) return;
    if (wellnessAnswers.containsKey(session.mergeKey)) return;
    wellnessAnswers[session.mergeKey] = wellness;
  }

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) async {
    return sessions.where((s) {
      final end = DateTime.fromMillisecondsSinceEpoch(s.endUnix * 1000);
      return end.year == year && end.month == month;
    }).toList();
  }

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async => const [];

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async =>
      null;

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async => null;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async =>
      Right(VitalsSnapshot(sleepSessions: sessions, dailyHr: const []));

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async =>
      const Right(
        AutoTrackingEnableResult(
          status: AutoTrackingEnableStatus.ok,
          overall: AutoTrackingOverall.noneArmed,
          features: [],
        ),
      );

  @override
  Future<void> clearLocal() async {}
}

/// Delegates to [_FakeRepo] but awaits [gate] before finishing sync.
class _HangingSyncRepo implements VitalsRepository {
  _HangingSyncRepo({required this.inner, required this.gate});

  final _FakeRepo inner;
  final Completer<void> gate;

  @override
  Future<bool> isGateAPassed() => inner.isGateAPassed();

  @override
  bool get isSyncOrMergeInFlight => inner.isSyncOrMergeInFlight;

  @override
  bool get sessionReady => inner.sessionReady;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() =>
      inner.loadSleepSessions();

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) =>
      inner.loadSleepStages(session);

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() => inner.loadDailyHr();

  @override
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey) =>
      inner.loadDailyHrSeries(dayKey);

  @override
  Future<List<DailyHrSample>> loadSleepHrWindow({
    required int beginUnix,
    required int endUnix,
  }) =>
      inner.loadSleepHrWindow(beginUnix: beginUnix, endUnix: endUnix);

  @override
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session) =>
      inner.isSleepEnrichPresent(session);

  @override
  Future<MorningWellness?> loadMorningWellness(SleepSessionSummary session) =>
      inner.loadMorningWellness(session);

  @override
  Future<void> saveMorningWellness(
    SleepSessionSummary session,
    MorningWellness wellness,
  ) =>
      inner.saveMorningWellness(session, wellness);

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) =>
      inner.loadSleepSessionsForMonth(year: year, month: month);

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() =>
      inner.loadFitnessTotals();

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) =>
      inner.loadFitnessTotalsForDay(dayKey);

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() =>
      inner.loadLastEnable();

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async {
    await gate.future;
    return inner.syncFromWatch();
  }

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() =>
      inner.enableAutoTracking();

  @override
  Future<void> clearLocal() => inner.clearLocal();
}

/// Overnight ending "today" in local time.
SleepSessionSummary _todayOvernight() {
  final now = DateTime.now();
  final endLocal = DateTime(now.year, now.month, now.day, 6, 30);
  final beginLocal = endLocal.subtract(const Duration(hours: 7, minutes: 12));
  return SleepSessionSummary(
    beginUnix: beginLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
    endUnix: endLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
  );
}

/// Nap ending today (does not cross midnight).
SleepSessionSummary _todayNap() {
  final now = DateTime.now();
  final beginLocal = DateTime(now.year, now.month, now.day, 13, 0);
  final endLocal = DateTime(now.year, now.month, now.day, 14, 0);
  return SleepSessionSummary(
    beginUnix: beginLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
    endUnix: endLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
  );
}

Future<void> _pumpSleepTab(
  WidgetTester tester, {
  required _FakeRepo repo,
  required VitalsBloc bloc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BpTheme.light(),
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: SleepTabScreen(repository: repo),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _answerAllFour(WidgetTester tester) async {
  // Four dimension rows × scores 1–7; tap score "3" in each row in order.
  final threes = find.text('3');
  expect(threes, findsWidgets);
  for (var i = 0; i < 4; i++) {
    await tester.tap(threes.at(i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Hooper-4 shows then hides after four answers', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session]);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await _pumpSleepTab(tester, repo: repo, bloc: bloc);

    expect(find.text('How did last night land?'), findsOneWidget);
    expect(find.text('0/4 answered'), findsOneWidget);

    await _answerAllFour(tester);

    expect(repo.saveWellnessCalls, 1);
    expect(repo.wellnessAnswers[session.mergeKey], isNotNull);
    expect(find.text('How did last night land?'), findsNothing);

    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    expect(find.text('How did last night land?'), findsNothing);
    expect(repo.saveWellnessCalls, 1);
  });

  testWidgets('partial answers do not persist', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session]);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    await tester.tap(find.text('3').first);
    await tester.pump();
    expect(repo.saveWellnessCalls, 0);
    expect(find.text('1/4 answered'), findsOneWidget);

    // Rebuild — draft is ephemeral; survey returns without a prefs write.
    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    expect(find.text('How did last night land?'), findsOneWidget);
    expect(find.textContaining('/4 answered'), findsOneWidget);
    expect(repo.saveWellnessCalls, 0);
    expect(repo.wellnessAnswers, isEmpty);
  });

  testWidgets('nap-only day hides survey', (tester) async {
    final repo = _FakeRepo(sessions: [_todayNap()]);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    expect(find.text('How did last night land?'), findsNothing);
  });

  testWidgets('hides survey while syncing', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session]);
    // Hang sync so phase stays syncing while survey would otherwise show.
    late void Function() release;
    final gate = Completer<void>();
    release = () {
      if (!gate.isCompleted) gate.complete();
    };
    repo.sessions = [session];

    final hanging = _HangingSyncRepo(inner: repo, gate: gate);
    final bloc = VitalsBloc(repository: hanging)..add(const VitalsStarted());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: SleepTabScreen(repository: hanging),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('How did last night land?'), findsOneWidget);

    bloc.add(const VitalsSyncRequested());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('How did last night land?'), findsNothing);

    release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('complete wellness hides survey', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(
      sessions: [session],
      wellnessAnswers: {
        session.mergeKey: const MorningWellness(
          sleepQuality: 3,
          fatigue: 3,
          soreness: 3,
          stress: 3,
        ),
      },
    );
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    expect(find.text('How did last night land?'), findsNothing);
  });

  testWidgets('save failure keeps survey with draft', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session], saveFails: true);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    await _answerAllFour(tester);
    expect(repo.saveWellnessCalls, 1);
    expect(find.text('How did last night land?'), findsOneWidget);
    expect(find.text('4/4 answered'), findsOneWidget);
  });

  testWidgets('survey copy avoids coaching and watch-DOMS claims',
      (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session]);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await _pumpSleepTab(tester, repo: repo, bloc: bloc);
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) {
      final d = t.data;
      if (d != null) return d;
      return t.textSpan?.toPlainText() ?? '';
    }).join(' ');
    expect(texts.toLowerCase(), isNot(contains('hard day')));
    expect(texts.toLowerCase(), isNot(contains('easy day')));
    expect(texts.toLowerCase(), isNot(contains('watch measured')));
    expect(texts.toLowerCase(), isNot(contains('intensity')));
  });

  testWidgets('history month arrows change listed sessions', (tester) async {
    final aug = SleepSessionSummary(
      beginUnix: DateTime.utc(2026, 8, 8, 18).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime.utc(2026, 8, 9, 1).millisecondsSinceEpoch ~/ 1000,
    );
    final jul = SleepSessionSummary(
      beginUnix: DateTime.utc(2026, 7, 10, 18).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime.utc(2026, 7, 11, 1).millisecondsSinceEpoch ~/ 1000,
    );
    final repo = _FakeRepo(sessions: [aug, jul]);

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepHistoryScreen(
          repository: repo,
          initialYear: 2026,
          initialMonth: 8,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Aug 2026'), findsOneWidget);
    expect(find.text('charts later · list first'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Jul 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Jun 2026'), findsOneWidget);
    expect(
      find.textContaining('No sleep sessions stored yet'),
      findsOneWidget,
    );
  });

  testWidgets('sleep list empty honesty copy', (tester) async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await _pumpSleepTab(tester, repo: repo, bloc: bloc);

    expect(
      find.textContaining('No sleep sessions stored yet'),
      findsOneWidget,
    );
    expect(find.text('Advanced sleep metrics — unlock soon'), findsOneWidget);
    expect(
      find.text('no fake metrics · quality score deferred'),
      findsOneWidget,
    );
  });
}
