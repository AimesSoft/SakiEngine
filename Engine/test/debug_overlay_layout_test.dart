import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/widgets/expression_radial_wheel.dart';
import 'package:sakiengine/src/widgets/floating_script_editor_overlay.dart';

class _EditorGameManager implements GameManager {
  @override
  String get currentScriptFile => 'overlay_layout_test';

  @override
  String? get currentDialogueSourceScriptFile => null;

  @override
  int? get currentDialogueSourceLine => null;

  @override
  String get currentDialogueText => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory gameDirectory;
  setUp(() {
    gameDirectory = Directory.systemTemp.createTempSync('saki_overlay_layout_');
    Directory('${gameDirectory.path}/Assets').createSync();
    Directory(
      '${gameDirectory.path}/GameScript/labels',
    ).createSync(recursive: true);
    File(
      '${gameDirectory.path}/GameScript/labels/overlay_layout_test.sks',
    ).writeAsStringSync('label overlay_layout_test\n"Editor fixture."\n');
    configureRuntimeProject(gamePath: gameDirectory.path);
    GamePathResolver.clearCache();
  });
  tearDown(() {
    clearRuntimeProjectConfig();
    GamePathResolver.clearCache();
    gameDirectory.deleteSync(recursive: true);
  });

  testWidgets('Shift+A wheel lays out in the game Stack and handles Escape', (
    tester,
  ) async {
    var dismissed = false;
    String? highlighted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ExpressionRadialWheel(
                characterName: 'Character',
                currentExpression: 'happy',
                expressions: const ['happy', 'sad'],
                center: const Offset(400, 300),
                onHighlightedExpressionChanged: (id) => highlighted = id,
                onDismiss: () => dismissed = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LayoutBuilder)), const Size(800, 600));
    expect(find.text('Character'), findsOneWidget);
    expect(highlighted, 'happy');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, isTrue);
  });

  for (final size in [
    const Size(640, 360),
    const Size(800, 600),
    const Size(1280, 720),
  ]) {
    testWidgets('Shift+P editor loads and fits $size, and handles Escape', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingScriptEditorOverlay(
                  gameManager: _EditorGameManager(),
                  currentScript: 'overlay_layout_test',
                  onClose: () => closed = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }
      });
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      final title = find.text('脚本编辑浮窗 (Shift+P)');
      expect(tester.getSize(title).width, greaterThan(0));
      final panel = tester.getRect(find.byType(FloatingScriptEditorOverlay));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(size.width));
      expect(panel.bottom, lessThanOrEqualTo(size.height));
      final viewport = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      );
      expect(viewport.height, greaterThan(panel.height * 0.6));
      final openFolder = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '打开文件夹'),
      );
      expect(openFolder.onPressed, isNotNull);
      final editor = tester.widget<TextField>(find.byType(TextField));
      expect(editor.controller!.text, contains('Editor fixture.'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
