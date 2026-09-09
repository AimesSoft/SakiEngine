import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';
import 'package:sakiengine/src/widgets/common/virtual_game_canvas.dart';

void main() {
  tearDown(() {
    clearRuntimeProjectConfig();
    AnimationManager.clearCache();
  });

  testWidgets(
    'expression replacement inherits motion; same scene clears the tag and its ticker',
    (tester) async {
      configureRuntimeProject(
        projectName: 'org.yuyu.display',
        packageDigest: 'fixture',
      );
      final manager = GameManager(defaultSceneTransitionType: 'none');
      addTearDown(manager.dispose);
      manager.characterConfigs['e'] = CharacterConfig(
        id: 'e',
        name: '',
        resourceId: 'e',
        defaultPoseId: 'default',
      );
      manager.poseConfigs['default'] = PoseConfig(
        id: 'default',
        scale: 1,
        xcenter: .5,
        ycenter: .5,
        anchor: 'center',
      );
      manager.poseConfigs['left'] = PoseConfig(
        id: 'left',
        scale: 1,
        xcenter: .3,
        ycenter: .5,
        anchor: 'center',
      );
      AnimationManager.loadAnimationsFromStringForTesting('''motion
profile yuyuball-sequence-v1
xcenter+0
linear 1 xcenter+0.1
linear 1 xcenter+0
''');
      late BuildContext context;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      manager.setContext(context, const TestVSync());
      await manager.startTestScript(
        ScriptNode([
          BackgroundNode('bg'),
          ShowNode(
            'e',
            pose: 'normal',
            expression: '__none',
            position: 'left',
            animation: 'motion',
            repeatCount: 0,
          ),
          SayNode(dialogue: 'before'),
          ShowNode('e', pose: 'smile', expression: '__none'),
          SayNode(dialogue: 'inherit'),
          BackgroundNode('bg'),
          SayNode(dialogue: 'clear'),
          ShowNode('e', pose: 'normal', expression: '__none'),
          SayNode(dialogue: 'new'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final moving = manager.currentState.characters.values.single;
      expect(moving.animationProperties!['xcenter'], closeTo(.35, .001));
      manager.next();
      await tester.pump();
      expect(manager.currentState.dialogue, 'inherit');
      expect(manager.currentState.characters.values.single.positionId, 'left');
      expect(
        manager
            .currentState
            .characters
            .values
            .single
            .animationProperties!['xcenter'],
        closeTo(.35, .001),
      );
      manager.next();
      await tester.pump();
      expect(manager.currentState.dialogue, 'clear');
      expect(manager.currentState.characters, isEmpty);
      manager.next();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final fresh = manager.currentState.characters.values.single;
      expect(fresh.positionId, 'default');
      expect(fresh.animationProperties, isNull);
    },
  );

  testWidgets('package canvas letterboxes without cropping the source stage', (
    tester,
  ) async {
    final config = SakiEngineConfig();
    final oldSize = Size(config.logicalWidth, config.logicalHeight);
    config.logicalWidth = 1280;
    config.logicalHeight = 720;
    addTearDown(() {
      config.logicalWidth = oldSize.width;
      config.logicalHeight = oldSize.height;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: SakiVirtualGameCanvas(
          contain: true,
          child: ColoredBox(key: ValueKey('stage'), color: Colors.white),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('stage'))),
      const Rect.fromLTWH(0, 50, 1600, 900),
    );
  });
}
