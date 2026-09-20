import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/effects/scene_filter.dart';
import 'package:sakiengine/src/screens/game_play_screen.dart';

void main() {
  testWidgets(
    'fade reaches its final frame once, including after a filter change',
    (tester) async {
      Future<void> show(AnimationType animation, double duration) =>
          tester.pumpWidget(
            MaterialApp(
              home: SceneFilteredBackground(
                filter: SceneFilter(
                  type: FilterType.snowMosaic,
                  animation: animation,
                  duration: duration,
                ),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          );
      AnimationController controller() =>
          tester
                  .widget<AnimatedBuilder>(
                    find
                        .descendant(
                          of: find.byType(SceneFilteredBackground),
                          matching: find.byType(AnimatedBuilder),
                        )
                        .first,
                  )
                  .animation
              as AnimationController;

      await show(AnimationType.fade, 1.8);
      await tester.pump(const Duration(milliseconds: 900));
      expect(controller().value, closeTo(0.5, 0.01));
      await tester.pump(const Duration(seconds: 1));
      expect(controller().value, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(controller().value, 1);
      expect(controller().isAnimating, isFalse);

      await show(AnimationType.wave, 0.3);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller().isAnimating, isTrue);
      await show(AnimationType.fade, 1);
      expect(controller().value, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(controller().value, 1);
      expect(controller().isAnimating, isFalse);
    },
  );
}
