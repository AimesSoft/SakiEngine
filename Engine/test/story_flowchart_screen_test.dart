import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/story_flowchart_manager.dart';
import 'package:sakiengine/src/screens/story_flowchart_screen.dart';

import 'story_flowchart_layout_test.dart' show node;
import 'support/settings_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeSettingsTestEnvironment();
    for (final channelName in [
      'dev.leanflutter.plugins/hotkey_manager',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      final channel = MethodChannel(channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    }
  });

  for (final size in [const Size(1280, 720), const Size(640, 360)]) {
    testWidgets('cyclic flowchart opens, recenters and reopens at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(
        () => StoryFlowchartManager().replaceGraph(
          [
            node('chapter', type: StoryNodeType.chapter, children: ['choice']),
            node('choice', children: ['retry', 'exit']),
            node('retry', parent: 'choice', option: true, children: ['merge']),
            node(
              'merge',
              type: StoryNodeType.merge,
              parents: ['retry'],
              children: ['choice'],
            ),
            node('exit', parent: 'choice', option: true, children: ['ending']),
            node('ending', type: StoryNodeType.ending, parent: 'exit'),
            // This disconnected parent cycle must remain hidden.
            node('hidden', type: StoryNodeType.merge, parents: ['hidden']),
          ],
          rootIds: ['chapter'],
        ),
      );

      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StoryFlowchartScreen(onClose: () {})),
          ),
        );
        await tester.pump();
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(tester.takeException(), isNull);
      }

      await open();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<FlowchartPainter>()
          .single;
      expect(painter.layoutInfo, hasLength(6));
      expect(painter.layoutInfo.containsKey('hidden'), isFalse);
      expect(painter.layoutInfo['chapter']!['depth'], 0);
      expect(find.text('retry'), findsOneWidget);
      expect(find.text('ending'), findsOneWidget);

      await tester.tap(find.text('重置视图'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
