import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/baseline_resolver.dart';
import 'package:fitness_os/features/programs/domain/chore_matcher.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/formulas.dart';
import 'package:fitness_os/features/programs/domain/scorecards.dart';
import 'package:fitness_os/features/programs/domain/soft_load_warn.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dogfood acceptance harness (plan §U8): domain + ProgramStore paths for
/// AE1 / AE4 / AE5 / AE6 spirit without full app / Coach DI.
void main() {
  late Directory tempRoot;
  late SharedPreferences prefs;
  late ProgramStore store;

  final resolver = BaselineResolver();
  final planner = ProgramPlanner();
  final matcher = ChoreMatcher();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempRoot = await Directory.systemTemp.createTemp('programs_acceptance_');
    store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
  });

  tearDown(() async {
    try {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  group('AE1 rich baseline → plan → activate → reload', () {
    test('fixture history → active program with milestone + WU/main/CD', () async {
      final fixture = await _loadRichHistoryFixture();
      final asOf = DateTime.parse(fixture['asOfIso'] as String).toUtc();
      final sessions = _sessionsFromFixture(fixture, asOf);

      final baseline = resolver.resolve(sessions: sessions, asOf: asOf);
      expect(baseline.guidedTestRequired, isFalse);
      expect(baseline.reason, BaselineReason.richHistory);
      expect(baseline.capacityDistanceM, 1000);
      expect(
        baseline.confidence,
        anyOf(BaselineConfidence.medium, BaselineConfidence.high),
      );

      final start = DateTime(2026, 10, 12); // Monday
      final program = planner.plan(
        intake: const ProgramIntake(
          goalDistanceM: 1200,
          targetTimeSec: 24 * 60,
          horizonWeeks: 3,
          sessionsPerWeek: 3,
          poolOnlyAcknowledged: true,
        ),
        baseline: baseline,
        startDate: start,
        id: 'ae1_dogfood',
      );

      expect(program.poolOnly, isTrue);
      expect(program.milestones, isNotEmpty);
      expect(program.milestones.first.targetDistanceM, 1200);
      expect(program.chores.where((c) => c.role != ChoreRole.proof), isNotEmpty);
      for (final c in program.chores) {
        expect(c.hasWuMainCd, isTrue, reason: '${c.id} missing WU/main/CD');
      }

      final withBaseline = program.copyWith(baseline: baseline);
      await store.activate(withBaseline);

      final reloaded = await store.loadActive();
      expect(reloaded, isNotNull);
      expect(reloaded!.id, 'ae1_dogfood');
      expect(reloaded.status, ProgramStatus.active);
      expect(reloaded.baseline?.capacityDistanceM, 1000);
      expect(reloaded.milestones.first.targetDistanceM, 1200);
      expect(reloaded.chores.first.hasWuMainCd, isTrue);
    });
  });

  group('AE5 proof fail → slip + attempt XP', () {
    test('ChoreMatcher fail → applyProofOutcome slips; ProgressEngine grants XP',
        () async {
      final start = DateTime(2026, 10, 12);
      final baseline = Baseline(
        capacityDistanceM: 1000,
        confidence: BaselineConfidence.medium,
        reason: BaselineReason.richHistory,
      );
      var program = planner.plan(
        intake: const ProgramIntake(
          goalDistanceM: 1200,
          horizonWeeks: 3,
          sessionsPerWeek: 3,
          poolOnlyAcknowledged: true,
        ),
        baseline: baseline,
        startDate: start,
        id: 'ae5_fail',
      );
      program = program.copyWith(baseline: baseline);
      await store.activate(program);

      final ms = program.milestones.first;
      final beforeForecast = DateTime.parse(ms.forecastDateIso);
      final proofDay = DateTime.parse(ms.forecastDateIso);

      // Short continuous-confirmed swim → fail vs 1200 m rung.
      final swim = PoolSwimCandidate(
        workoutNumber: 99,
        startTime: DateTime(proofDay.year, proofDay.month, proofDay.day, 8)
                .millisecondsSinceEpoch ~/
            1000,
        type: poolSwimWorkoutType,
        distanceM: 900,
        durationSec: 1800,
      );
      final proof = matcher.matchProof(
        milestone: ms,
        swim: swim,
        continuousConfirmed: true,
      );
      expect(proof.outcome, ProofOutcome.fail);
      expect(proof.judgedDistanceM, 900);

      final asOf = proofDay.add(const Duration(hours: 12));
      final slipped = planner.applyProofOutcome(
        program,
        milestoneId: ms.id,
        outcome: proof.outcome,
        asOf: asOf,
      );
      await store.save(slipped);

      final afterMs = slipped.milestones.first;
      final afterForecast = DateTime.parse(afterMs.forecastDateIso);
      expect(afterForecast.isAfter(beforeForecast), isTrue);
      expect(
        afterForecast.difference(beforeForecast).inDays,
        failSlipDays,
      );

      var ledger = await store.loadLedger();
      ledger = ProgressEngine.recordProofAttempt(
        ledger,
        passed: false,
        programId: program.id,
        milestoneId: ms.id,
        asOf: asOf,
      );
      await store.saveLedger(ledger);

      final reloadedLedger = await store.loadLedger();
      expect(
        reloadedLedger.xpEvents
            .where((e) => e.source == XpSource.proofAttempted),
        hasLength(1),
      );
      expect(
        reloadedLedger.xpEvents.where((e) => e.source == XpSource.proofPassed),
        isEmpty,
      );
      expect(reloadedLedger.totalXp, XpTable.proofAttempted);

      final reloadedProgram = await store.loadActive();
      expect(
        DateTime.parse(reloadedProgram!.milestones.first.forecastDateIso),
        afterForecast,
      );
    });
  });

  group('AE4 soft-warn + excused skip — no milestone slip', () {
    test('warn + skippedExcused leaves forecast dates unchanged', () async {
      final start = DateTime(2026, 10, 12);
      final program = planner.plan(
        intake: const ProgramIntake(
          goalDistanceM: 1200,
          horizonWeeks: 3,
          sessionsPerWeek: 3,
          poolOnlyAcknowledged: true,
        ),
        baseline: const Baseline(
          capacityDistanceM: 1000,
          confidence: BaselineConfidence.medium,
          reason: BaselineReason.richHistory,
        ),
        startDate: start,
        id: 'ae4_warn',
      );
      await store.activate(program);

      final choreDay = DateTime.parse(program.chores.first.dayIso);
      final warn = SoftLoadWarn.evaluate(
        recent: [
          OtherLoadSample(
            type: 140,
            typeLabel: 'Strength',
            startTimeMs: DateTime(
              choreDay.year,
              choreDay.month,
              choreDay.day,
              10,
            ).millisecondsSinceEpoch,
            durationSec: 52 * 60,
          ),
        ],
        day: choreDay,
      );
      expect(warn.warn, isTrue);
      expect(warn.copy.toLowerCase().contains('readiness'), isFalse);

      final forecastBefore =
          program.milestones.map((m) => m.forecastDateIso).toList();

      final excused = matcher.applyManual(
        chore: program.chores.first,
        action: ManualChoreAction.skippedExcused,
        skipReason: SkipReason.otherLoad,
        asOf: choreDay.add(const Duration(hours: 18)),
      );
      expect(excused.state, ChoreState.skippedExcused);

      final chores = List<ChoreSession>.from(program.chores)..[0] = excused;
      final next = program.copyWith(chores: chores);
      await store.save(next);

      var ledger = await store.loadLedger();
      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: excused,
        sessionsPerWeek: program.intake.sessionsPerWeek,
        asOf: choreDay,
      );
      await store.saveLedger(ledger);

      // Habit path only — do not call applyProofOutcome on skip.
      final reloaded = await store.loadActive();
      expect(
        reloaded!.milestones.map((m) => m.forecastDateIso).toList(),
        forecastBefore,
      );

      final cards = Scorecards.compute(
        program: reloaded,
        ledger: await store.loadLedger(),
      );
      expect(cards.habit.excused, greaterThanOrEqualTo(1));
      expect(cards.blockProof, isFalse);
    });
  });

  group('Edge: tippless / missing efficiency still updates volume', () {
    test('volume from KPI inputs; efficiency stays Collecting', () {
      final program = planner.plan(
        intake: const ProgramIntake(
          goalDistanceM: 1200,
          horizonWeeks: 3,
          sessionsPerWeek: 3,
          poolOnlyAcknowledged: true,
        ),
        baseline: const Baseline(
          capacityDistanceM: 1000,
          confidence: BaselineConfidence.medium,
          reason: BaselineReason.richHistory,
        ),
        startDate: DateTime(2026, 10, 12),
        id: 'tippless',
      );

      // Tippless insight path: no efficiency samples; volume still from
      // CanonicalSwimSession-style KPI inputs (longest continuous + weekly).
      final bundle = Scorecards.compute(
        program: program,
        ledger: const ProgressLedger(),
        longestContinuousM: 1000,
        weeklyDistanceM: 3200,
        efficiencySamples: const [],
      );

      expect(bundle.efficiency.status, EfficiencyStatus.collecting);
      expect(bundle.efficiency.medianDpsM, isNull);
      expect(bundle.volume.longestContinuousM, 1000);
      expect(bundle.volume.nextProofDistanceM, 1200);
      expect(bundle.volume.capacityGapM, 200);
      expect(bundle.volume.weeklyDistanceM, 3200);
      expect(bundle.blockProof, isFalse);
    });
  });

  group('AE6 no Coach imports in programs feature', () {
    test('lib/features/programs has no Coach package imports', () {
      final root = Directory('lib/features/programs');
      expect(root.existsSync(), isTrue);

      final coachImport = RegExp(
        r'''import\s+['"][^'"]*coach[^'"]*['"]''',
        caseSensitive: false,
      );

      final offenders = <String>[];
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        for (final line in const LineSplitter().convert(text)) {
          final trimmed = line.trimLeft();
          if (!trimmed.startsWith('import ')) continue;
          if (coachImport.hasMatch(trimmed) ||
              trimmed.toLowerCase().contains('local_ai_coach')) {
            offenders.add('${entity.path}: $trimmed');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}

Future<Map<String, dynamic>> _loadRichHistoryFixture() async {
  final file = File('test/fixtures/programs/rich_baseline_history.json');
  expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

List<CanonicalSwimSession> _sessionsFromFixture(
  Map<String, dynamic> fixture,
  DateTime asOf,
) {
  final raw = fixture['sessions'] as List<dynamic>;
  return raw.map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    final distanceM = (m['distanceM'] as num).toInt();
    final daysAgo = (m['daysAgo'] as num).toInt();
    final type = (m['type'] as num).toInt();
    final durationSec = distanceM * 2; // ~2:00/100 m
    final start = asOf.subtract(Duration(days: daysAgo));
    final startUnix = start.toUtc().millisecondsSinceEpoch ~/ 1000;
    final pace = distanceM > 0 ? (durationSec * 100) ~/ distanceM : null;
    return CanonicalSwimSession(
      workoutNumber: (m['workoutNumber'] as num).toInt(),
      startTime: startUnix,
      endTime: startUnix + durationSec,
      durationSec: durationSec,
      type: type,
      distanceM: distanceM,
      poolLengthM: type == poolSwimWorkoutType ? 25 : null,
      p0: SwimP0Metrics(
        hrCoverage: SwimHrCoverage.absent,
        avgPaceSecPer100m: pace,
        movingAvgPaceSecPer100m: pace,
      ),
    );
  }).toList();
}
