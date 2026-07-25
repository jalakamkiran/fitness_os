import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/presentation/view/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpState(WidgetTester tester, HomePrecedence p) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: HomeSnapshotView(snapshot: HomeSnapshot.forPrecedence(p)),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectForbiddenSectionsAbsent() {
    // Home never: graphs, vitals history lists, diagnosis lists, reasoner settings.
    expect(find.byKey(const Key('home-chart')), findsNothing);
    expect(find.textContaining('SWOLF'), findsNothing);
    expect(find.textContaining('Reasoner'), findsNothing);
    expect(find.textContaining('reasoner'), findsNothing);
    expect(find.textContaining('Diagnosis'), findsNothing);
    expect(find.textContaining('Coach settings'), findsNothing);
    expect(find.textContaining('Vitals history'), findsNothing);
    expect(find.text('GT5 pairing'), findsNothing);
    expect(find.byType(Table), findsNothing);
    expect(find.byType(DataTable), findsNothing);
  }

  testWidgets('01 not paired — pair CTA, no invented metrics', (tester) async {
    await pumpState(tester, HomePrecedence.notPaired);
    expect(find.byKey(const Key('home_state_notPaired')), findsOneWidget);
    expect(find.text('Pair watch'), findsOneWidget);
    expect(find.text('Pair a GT5 to begin'), findsOneWidget);
    expect(find.text('Calories'), findsNothing);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('02 paired never synced — Sync now, no fake zeros', (tester) async {
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

  testWidgets('03 sync in progress — calm progress, no charts', (tester) async {
    await pumpState(tester, HomePrecedence.syncInProgress);
    expect(
      find.byKey(const Key('home_state_syncInProgress')),
      findsOneWidget,
    );
    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('Pulling today’s data'), findsOneWidget);
    expect(find.textContaining('no charts while syncing'), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('04 sync failed — Retry sync + stale cue', (tester) async {
    await pumpState(tester, HomePrecedence.syncFailed);
    expect(find.byKey(const Key('home_state_syncFailed')), findsOneWidget);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('Last known'), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('05 data available — totals, vitals snapshot, one takeaway',
      (tester) async {
    await pumpState(tester, HomePrecedence.dataAvailable);
    expect(
      find.byKey(const Key('home_state_dataAvailable')),
      findsOneWidget,
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('1,842'), findsOneWidget);
    expect(find.text('Vitals · now'), findsOneWidget);
    expect(find.text('Efficient early, fatigue later'), findsOneWidget);
    expect(find.text('Open session'), findsOneWidget);
    expectForbiddenSectionsAbsent();
  });

  testWidgets('06 no swim data yet — totals + empty swim cue', (tester) async {
    await pumpState(tester, HomePrecedence.noSwimDataYet);
    expect(
      find.byKey(const Key('home_state_noSwimDataYet')),
      findsOneWidget,
    );
    expect(find.text('No swim yet today'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Vitals · now'), findsOneWidget);
    expect(find.text('Open session'), findsNothing);
    expectForbiddenSectionsAbsent();
  });
}
