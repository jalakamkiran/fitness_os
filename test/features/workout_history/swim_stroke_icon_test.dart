import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_stroke_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders icons for known strokes without throwing', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwimStrokeIcon(style: 1),
            SwimStrokeIcon(style: 2),
            SwimStrokeIcon(style: 3),
            SwimStrokeIcon(style: 4),
            SwimStrokeIcon(style: 5),
            SwimStrokeIcon(style: null),
          ],
        ),
      ),
    );

    expect(find.byType(SwimStrokeIcon), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tooltip uses stroke label', (tester) async {
    await tester.pumpWidget(wrap(const SwimStrokeIcon(style: 4)));
    final icon = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(icon.message, 'Backstroke');
  });
}
