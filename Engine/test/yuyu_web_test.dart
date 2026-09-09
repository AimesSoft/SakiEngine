import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_package.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_resource_server.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_story_bridge.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_webview.dart';
import 'package:sakiengine/src/effects/mouse_parallax.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';

class _CountingManager extends GameManager {
  int advances = 0;
  @override
  void next() {
    advances++;
  }
}

class _LoopbackHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'menu accepts pointer notifications and dispatches start only once',
    () async {
      final channel = YuyuWebChannel();
      final events = <Map<String, dynamic>>[];
      await channel.attach((event) async {
        events.add(event);
      });
      var starts = 0;
      final menu = YuyuMainMenuBridge(
        channel: channel,
        onStart: () {
          starts++;
        },
      );
      await menu.handle({
        'type': 'game:pointer',
        'action': 'move',
        'x': 10,
        'y': 20,
      });
      await menu.handle({'type': 'game:getContext'});
      expect(events.single['context'], 'main_menu');
      await menu.handle({'type': 'game:start'});
      await menu.handle({'type': 'game:start'});
      expect(starts, 1);
      await expectLater(
        menu.handle({'type': 'unmapped'}),
        throwsUnsupportedError,
      );
      channel.dispose();
    },
  );

  test(
    'Web resource service preserves relative roots, MIME, HEAD and media Range',
    () async {
      final package = await YuyuPackage.open(
        'test/fixtures/yuyu/sequence.yuyu',
      );
      final server = await YuyuResourceServer.start(package);
      final client = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _LoopbackHttp(),
      );
      try {
        final html = await (await client.getUrl(server.entryUri)).close();
        expect(html.statusCode, 200);
        expect(html.headers.contentType!.mimeType, 'text/html');
        await html.drain<void>();
        final imageUri = server.gameAssetUri('sprite.png');
        final range = await client.getUrl(imageUri);
        range.headers.set('Range', 'bytes=0-7');
        final response = await range.close();
        expect(response.statusCode, 206);
        expect(
          await response.fold<List<int>>(
            [],
            (all, bytes) => all..addAll(bytes),
          ),
          [137, 80, 78, 71, 13, 10, 26, 10],
        );
        final head = await (await client.openUrl('HEAD', imageUri)).close();
        expect(head.statusCode, 200);
        expect(
          head.contentLength,
          await package.entryFile('game/sprite.png')!.length(),
        );
        expect(
          await head.fold<int>(0, (count, bytes) => count + bytes.length),
          0,
        );
        final outside = await (await client.getUrl(
          server.origin.replace(path: '/game/sprite.png'),
        )).close();
        expect(outside.statusCode, 404);
        await outside.drain<void>();
        final invalid = await client.getUrl(imageUri);
        invalid.headers.set('Range', 'bytes=999999999-');
        final invalidResponse = await invalid.close();
        expect(invalidResponse.statusCode, 416);
        await invalidResponse.drain<void>();
      } finally {
        client.close(force: true);
        await server.close();
        await package.close();
      }
    },
  );

  test(
    'bridge checks dialogue/choice identity and ignores late callbacks after disposal',
    () async {
      final events = <Map<String, dynamic>>[];
      final manager = _CountingManager();
      final bridge = YuyuStoryBridge();
      final progression = DialogueProgressionManager(gameManager: manager);
      bridge.presentDialogue(
        text: '一句台词',
        speaker: '测试',
        scriptIndex: 1,
        progressionManager: progression,
      );
      expect(progression.canProgressDirectly, isFalse);
      await bridge.channel.attach((event) async {
        events.add(event);
      });
      await bridge.pageReady();
      final id =
          (events.lastWhere((v) => v['type'] == 'game:dialogue')['dialogue']
              as Map)['id'];
      await bridge.handle({
        'type': 'web:typewriterState',
        'dialogueId': 'old',
        'complete': true,
      });
      expect(progression.canProgressDirectly, isFalse);
      await bridge.handle({
        'type': 'web:typewriterState',
        'dialogueId': id,
        'complete': true,
      });
      expect(progression.canProgressDirectly, isTrue);
      await bridge.handle({'type': 'game:advance', 'dialogueId': 'old'});
      expect(manager.advances, 0);
      await bridge.handle({'type': 'game:advance', 'dialogueId': id});
      expect(manager.advances, 1);
      await bridge.handle({'type': 'game:advance', 'dialogueId': id});
      expect(manager.advances, 1);
      String? selected;
      bridge.presentChoices(MenuNode([ChoiceOptionNode('继续', 'ending')]), (
        value,
      ) {
        selected = value;
      });
      await bridge.pageReady();
      final choiceId =
          (events.lastWhere((v) => v['type'] == 'game:choice')['choice']
              as Map)['id'];
      await bridge.handle({
        'type': 'web:choiceSelect',
        'id': 'old',
        'choice': '0',
      });
      expect(selected, isNull);
      await bridge.handle({
        'type': 'web:choiceSelect',
        'id': choiceId,
        'choice': '0',
      });
      expect(selected, 'ending');
      events.clear();
      await bridge.pageReady();
      expect(events.where((event) => event['type'] == 'game:choice'), isEmpty);
      await expectLater(
        bridge.handle({'type': 'unknown:message'}),
        throwsUnsupportedError,
      );
      bridge.dispose();
      await bridge.handle({'type': 'game:advance', 'dialogueId': id});
      expect(manager.advances, 1);
      manager.dispose();
    },
  );

  test(
    'IPC failure is reported and does not poison subsequent page delivery',
    () async {
      final channel = YuyuWebChannel();
      final errors = <Object>[];
      channel.onError = errors.add;
      await channel.attach((event) async {
        throw StateError('page unavailable');
      });
      await channel.send({'type': 'first'});
      expect(errors, hasLength(1));
      channel.detach();
      final delivered = <String>[];
      await channel.send({'type': 'queued'});
      await channel.attach((event) async {
        delivered.add(event['type']);
      });
      await channel.send({'type': 'last'});
      expect(delivered, ['queued', 'last']);
      channel.dispose();
      await channel.send({'type': 'late'});
      expect(delivered, hasLength(2));
    },
  );

  testWidgets('Web pointer drives the existing parallax state', (tester) async {
    final pointer = ValueNotifier<Offset?>(null);
    Offset? offset;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MouseParallax(
          externalPointer: pointer,
          resetOnPointerUp: false,
          child: Builder(
            builder: (context) => ValueListenableBuilder<Offset>(
              valueListenable: MouseParallaxScope.of(context).offsetListenable,
              builder: (_, value, _) {
                offset = value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    pointer.value = const Offset(.5, -.25);
    await tester.pump();
    expect(offset, const Offset(.5, -.25));
    pointer.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(offset, Offset.zero);
    await tester.pumpWidget(const SizedBox());
    pointer.dispose();
  });
}
