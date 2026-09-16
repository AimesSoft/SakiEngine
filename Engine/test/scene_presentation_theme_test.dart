import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/effects/scene_presentation_theme.dart';
import 'package:sakiengine/src/effects/scene_transition_effects.dart';
import 'package:sakiengine/src/widgets/common/black_screen_transition.dart';
import 'package:sakiengine/src/widgets/common/virtual_game_canvas.dart';

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey key, {
  int y = 10,
}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + 100) * 4;
    final pixel = data!.buffer.asUint8List().sublist(offset, offset + 4);
    image.dispose();
    return pixel;
  }))!;
}

void main() {
  for (final customColor in [null, const Color(0xFF120040)]) {
    for (final effect in [
      'fade',
      'wipe',
      'blink',
      'slide',
      'global',
      'legacy-scene',
    ]) {
      testWidgets('$effect uses the requesting scene matte ($customColor)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(200, 120);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        late BuildContext requestContext;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              home: Theme(
                // This override is below the Navigator's Overlay. Reading the
                // overlay builder's theme would lose the project's matte color.
                data: ThemeData(
                  extensions: [
                    if (customColor != null)
                      ScenePresentationTheme(backdropColor: customColor),
                  ],
                ),
                child: Builder(
                  builder: (context) {
                    requestContext = context;
                    return const ColoredBox(color: Colors.white);
                  },
                ),
              ),
            ),
          ),
        );
        var commits = 0;
        final Future<void> transition;
        const duration = Duration(milliseconds: 400);
        if (effect == 'global') {
          transition = TransitionOverlayManager.instance.transition(
            context: requestContext,
            duration: duration,
            onMidTransition: () => commits++,
          );
        } else if (effect == 'legacy-scene') {
          transition = SceneTransitionManager.instance.transition(
            context: requestContext,
            duration: duration,
            onMidTransition: () => commits++,
          );
        } else {
          transition = SceneTransitionEffectManager.instance.transition(
            context: requestContext,
            duration: duration,
            transitionType: TransitionType.values.byName(effect),
            onMidTransition: () => commits++,
          );
        }
        await tester.pump();
        await tester.pump(Duration(milliseconds: effect == 'wipe' ? 400 : 200));
        final expected = customColor == null
            ? [0, 0, 0, 255]
            : [18, 0, 64, 255];
        expect(await _pixel(tester, key), expected);
        expect(commits, 1);
        if (effect == 'blink') {
          // The eyelid painter used after the midpoint must match the fade.
          await tester.pump(const Duration(milliseconds: 25));
          expect(await _pixel(tester, key, y: 2), expected);
        }
        await tester.pumpAndSettle();
        await transition;
        expect(commits, 1);
        expect(await _pixel(tester, key), [255, 255, 255, 255]);
      });
    }
  }

  testWidgets('letterbox edges use the same matte as scene transitions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(
            extensions: const [
              ScenePresentationTheme(backdropColor: Color(0xFF120040)),
            ],
          ),
          home: const SakiVirtualGameCanvas(
            contain: true,
            selectedAspectRatio: 16 / 9,
            child: ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    expect(await _pixel(tester, key, y: 0), [18, 0, 64, 255]);
    expect(await _pixel(tester, key, y: 60), [255, 255, 255, 255]);
  });
}
