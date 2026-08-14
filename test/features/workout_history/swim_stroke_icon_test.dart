import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_stroke_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child, {required ThemeData theme}) => MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Center(child: child),
        ),
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
        theme: BpTheme.light(),
      ),
    );

    expect(find.byType(SwimStrokeIcon), findsNWidgets(6));
    expect(SwimStrokeIcon.assetFor(2), contains('stroke_freestyle'));
    expect(SwimStrokeIcon.assetFor(4), contains('stroke_backstroke'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tooltip uses stroke label', (tester) async {
    await tester.pumpWidget(
      wrap(const SwimStrokeIcon(style: 4), theme: BpTheme.light()),
    );
    final icon = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(icon.message, 'Backstroke');
  });

  testWidgets('light theme tints with Fathom inkDim', (tester) async {
    await tester.pumpWidget(
      wrap(const SwimStrokeIcon(style: 2), theme: BpTheme.light()),
    );
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      svg.colorFilter,
      ColorFilter.mode(FathomColors.light.inkDim, BlendMode.srcIn),
    );
  });

  testWidgets('dark theme tints with Fathom inkDim', (tester) async {
    await tester.pumpWidget(
      wrap(const SwimStrokeIcon(style: 4), theme: BpTheme.dark()),
    );
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      svg.colorFilter,
      ColorFilter.mode(FathomColors.dark.inkDim, BlendMode.srcIn),
    );
    expect(FathomColors.dark.inkDim, const Color(0xFFA7B2BD));
  });
}
