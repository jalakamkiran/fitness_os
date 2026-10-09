import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/presentation/view/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSnapshot(WidgetTester tester, HomeSnapshot snapshot) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: HomeSnapshotView(snapshot: snapshot),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpState(WidgetTester tester, HomePrecedence p,
      {bool restDay = false}) async {
    await pumpSnapshot(
      tester,
      HomeSnapshot.forPrecedence(p, restDay: restDay),
    );
  }

  void expectForbiddenSectionsAbsent() {
    expect(find.byKey(const Key('home-chart')), findsNothing);
    expect(find.textContaining('SWOLF'), findsNothing);
    expect(find.textContaining('Reasoner'), findsNothing);
    expect(find.textContaining('reasoner'), findsNothing);
    expect(find.textContaining('Diagnosis'), findsNothing);
    expect(find.textContaining('Coach settings'), findsNothing);
    expect(find.textContaining('Vitals history'), findsNothing);
    expect(find.textContaining('readiness'), findsNothing);
    expect(find.textContaining('hypnogram'), findsNothing);
    expect(find.text('GT5 pairing'), findsNothing);
    expect(find.byType(Table), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(find.byKey(const Key('home-swim-takeaway')), findsNothing);
  }

  testWidgets('01 not paired — pair CTA, no invented metrics', (tester) async {
    await pumpState(tester, HomePrecedence.notPaired);
    expect(find.byKey(const Key('home_state_notPaired')), findsOneWidget);
    expect(find.text('Pair watch'), findsOneWidget);
    expect(find.text('Pair a GT5 to begin'), findsOneWidget);
    expect(find.text('Calories'), findsNothing);
    expect(find.byKey(const Key('home-sleep-duration')), findsNothing);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('02 paired never synced — Sync now, no fake zeros',
      (tester) async {
    await pumpState(tester, HomePrecedence.pairedNeverSynced);
    expect(
      find.byKey(const Key('home_state_pairedNeverSynced')),
      findsOneWidget,
    );
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Calories'), findsNothing);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('03 sync in progress — muted prior stack, no charts',
      (tester) async {
    await pumpState(tester, HomePrecedence.syncInProgress);
    expect(
      find.byKey(const Key('home_state_syncInProgress')),
      findsOneWidget,
    );
    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('Pulling today’s data'), findsOneWidget);
    expect(find.byKey(const Key('home-sleep-duration')), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('04 sync failed — Retry sync + stale cue', (tester) async {
    await pumpState(tester, HomePrecedence.syncFailed);
    expect(find.byKey(const Key('home_state_syncFailed')), findsOneWidget);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byKey(const Key('home-stale-cue')), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('05 trusted day — Today stack with multi-sport sessions',
      (tester) async {
    await pumpState(tester, HomePrecedence.dataAvailable);
    expect(
      find.byKey(const Key('home_state_dataAvailable')),
      findsOneWidget,
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('1,842'), findsOneWidget);
    expect(find.byKey(const Key('home-sleep-duration')), findsOneWidget);
    expect(find.byKey(const Key('home-sleep-feel')), findsOneWidget);
    expect(find.byKey(const Key('home-body-hr')), findsOneWidget);
    expect(find.byKey(const Key('home-hr-spark')), findsOneWidget);
    expect(find.text('Pool swim · #11'), findsOneWidget);
    expect(find.text('Strength · #24'), findsOneWidget);
    expect(find.text('Load'), findsWidgets);
    expect(find.text('TE'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byKey(const Key('home-session-0')), findsOneWidget);
    expect(find.byKey(const Key('home-session-1')), findsOneWidget);
    expect(find.byKey(const Key('home-programs-cta')), findsOneWidget);
    expect(find.text('Swim'), findsOneWidget);
    expect(find.textContaining('AGONS'), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('06 rest day — empty sessions cue, upper blocks remain',
      (tester) async {
    await pumpState(tester, HomePrecedence.dataAvailable, restDay: true);
    expect(
      find.byKey(const Key('home_state_dataAvailable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-sessions-empty')), findsOneWidget);
    expect(find.text('No sessions yet today'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.byKey(const Key('home-body-hr')), findsOneWidget);
    expect(find.byKey(const Key('home-session-0')), findsNothing);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('feel absent — no survey CTA on Home', (tester) async {
    final base = HomeSnapshot.forPrecedence(HomePrecedence.dataAvailable);
    await pumpSnapshot(
      tester,
      HomeSnapshot(
        precedence: base.precedence,
        deviceLabel: base.deviceLabel,
        brandSubtitle: base.brandSubtitle,
        syncPillLabel: base.syncPillLabel,
        syncTitle: base.syncTitle,
        syncCaption: base.syncCaption,
        sleepDurationLabel: base.sleepDurationLabel,
        sleepWindowLabel: base.sleepWindowLabel,
        caloriesLabel: base.caloriesLabel,
        stepsLabel: base.stepsLabel,
        workoutTimeLabel: base.workoutTimeLabel,
        bodyHrLabel: base.bodyHrLabel,
        todaySessions: base.todaySessions,
      ),
    );
    expect(find.byKey(const Key('home-sleep-feel')), findsNothing);
    expect(find.textContaining('survey'), findsNothing);
    expectForbiddenSectionsAbsent();
  });
}
