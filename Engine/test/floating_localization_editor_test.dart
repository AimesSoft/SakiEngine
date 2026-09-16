import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/widgets/floating_localization_editor.dart';
import 'package:sakiengine/src/widgets/floating_script_editor_overlay.dart';
import 'package:sakiengine/src/widgets/game_style_switch.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';

import 'support/settings_test_environment.dart';

class _GameManager implements GameManager {
  @override
  String get currentScriptFile => 'start';
  @override
  String? get currentDialogueSourceScriptFile => 'start';
  @override
  int? get currentDialogueSourceLine => 3;
  @override
  String get currentDialogueText => '晚上好。';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _finishIO(WidgetTester tester, {bool Function()? until}) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (until?.call() ??
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final directory = Platform.environment['SAKI_EDITOR_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const hotKeyEvents = MethodChannel(
      'dev.leanflutter.plugins/hotkey_manager_event',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hotKeyEvents, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hotKeyEvents, null);
    });
    await initializeSettingsTestEnvironment();
    await UnifiedGameDataManager().setSoundEnabled(false, 'Saki-Logger-Test');
    final font = FontLoader('SourceHanSansCN')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSansCN-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  late Directory game;
  late File story, names;
  setUp(() async {
    game = Directory.systemTemp.createTempSync('saki_localization_widget_');
    Directory('${game.path}/Assets').createSync();
    Directory('${game.path}/GameScript/labels').createSync(recursive: true);
    Directory('${game.path}/GameScript/configs').createSync(recursive: true);
    story = File('${game.path}/GameScript/labels/start.sks')
      ..writeAsStringSync(
        'label start\nscene room\naru pose happy "晚上好。/en Good evening./" auto // 演出\n'
        'aru sad "你今天过得怎么样？/en How was your day?/"\n'
        '"窗外的雨还没有停。/en The rain has not stopped./"\n'
        'menu\n"留下" stay\nendmenu\n',
      );
    names = File('${game.path}/GameScript/configs/characters.sks')
      ..writeAsStringSync('aru : "鸦露露/en Aru/" : aru at pose slot:aru\n');
    final configPath = Platform.environment['SAKI_EDITOR_CONFIG_PATH'];
    File('${game.path}/GameScript/configs/configs.sks').writeAsStringSync(
      configPath == null
          ? 'theme: color=rgb(255, 113, 220)\nbase_dialogue: size=28\n'
                'base_review_title: size=45\n'
          : File(configPath).readAsStringSync(),
    );
    configureRuntimeProject(gamePath: game.path);
    GamePathResolver.clearCache();
    await SettingsManager().setDarkMode(false);
    await SettingsManager().setMenuDisplayMode('fullscreen');
    await SakiEngineConfig().loadConfig();
    final config = SakiEngineConfig();
    config.reviewTitleTextStyle = config.reviewTitleTextStyle.copyWith(
      fontFamily: config.dialogueFontFamily,
    );
  });
  tearDown(() {
    clearRuntimeProjectConfig();
    GamePathResolver.clearCache();
    game.deleteSync(recursive: true);
  });

  for (final size in [
    const Size(640, 360),
    const Size(800, 600),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'localization editor fits $size and has editable speaker/text rows',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var closed = false;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: Stack(
                  children: [
                    FloatingLocalizationEditor(
                      gameManager: _GameManager(),
                      onClose: () => closed = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await _finishIO(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(OverlayScaffold), findsOneWidget);
        expect(find.byType(GameStyleSwitch), findsNWidgets(2));
        expect(find.text('晚上好。'), findsOneWidget);
        expect(find.text('Good evening.'), findsOneWidget);
        expect(find.text('Aru'), findsWidgets);
        expect(find.text('：'), findsWidgets);
        expect(find.text('留下'), findsNothing);
        expect(find.text('scene room'), findsNothing);
        // Optional screenshot output is a test artifact, never a game asset.
        await _capture(
          tester,
          boundaryKey,
          'localization-${size.width.toInt()}',
        );
        if (size.width == 1280) {
          await tester.runAsync(() => SettingsManager().setDarkMode(true));
          await _finishIO(tester);
          expect(tester.takeException(), isNull);
          await _capture(tester, boundaryKey, 'localization-dark');
          await tester.runAsync(() async {
            await SettingsManager().setDarkMode(false);
            await SettingsManager().setMenuDisplayMode('windowed');
          });
          await _finishIO(tester);
          expect(tester.takeException(), isNull);
          await _capture(tester, boundaryKey, 'localization-windowed');
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        if (size.width == 1280 &&
            Platform.environment['SAKI_EDITOR_SCREENSHOTS'] != null) {
          await tester.runAsync(
            () => SettingsManager().setMenuDisplayMode('fullscreen'),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: SettingsScreen(onClose: () {}),
                ),
              ),
            ),
          );
          await _finishIO(tester);
          await tester.tap(find.text('开发者'));
          await _finishIO(tester);
          await _capture(tester, boundaryKey, 'native-settings-reference');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  for (final saveBeforeClose in [true, false]) {
    testWidgets('dirty native window closes with save=$saveBeforeClose', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingLocalizationEditor(
                  gameManager: _GameManager(),
                  onClose: () => closed = true,
                ),
              ],
            ),
          ),
        ),
      );
      await _finishIO(tester);
      await tester.enterText(
        find.byKey(ValueKey('dialogue:${story.path}:2:en')),
        'Saved when closing.',
      );
      await tester.tap(find.byTooltip('关闭 (Esc)'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      await tester.tap(find.text(saveBeforeClose ? '保存并关闭' : '放弃修改'));
      await tester.pumpAndSettle();
      await _finishIO(tester, until: () => closed);
      expect(closed, isTrue);
      expect(
        story.readAsStringSync().contains('Saved when closing.'),
        saveBeforeClose,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'hide, add, edit, save and reopen preserve source and shared names',
    (tester) async {
      var reloads = 0;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingLocalizationEditor(
                  gameManager: _GameManager(),
                  onClose: () => closed = true,
                  onReload: () async {
                    reloads++;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await _finishIO(tester);
      final nameKey = ValueKey('name:${names.path}:0:en');
      final dialogueKey = ValueKey('dialogue:${story.path}:2:en');
      await tester.enterText(find.byKey(nameKey).first, 'Aruru');
      await tester.pump();
      expect(find.text('Aruru'), findsNWidgets(2));
      await tester.enterText(find.byKey(dialogueKey), 'Hello there.');
      await tester.tap(find.byKey(const ValueKey('localization-language-en')));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogueKey), findsNothing);
      await tester.tap(find.byKey(const ValueKey('localization-language-en')));
      await tester.pumpAndSettle();
      expect(find.text('Hello there.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('localization-add-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語').last);
      await tester.pumpAndSettle();
      final japaneseKey = ValueKey('dialogue:${story.path}:2:jp');
      expect(
        tester.widget<TextField>(find.byKey(japaneseKey)).controller!.text,
        '',
      );
      await tester.enterText(find.byKey(japaneseKey), 'こんばんは。');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(find.text('保存多语言修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('保存并重载 (⌘/Ctrl+S)'));
      await _finishIO(tester, until: () => reloads == 1);
      expect(reloads, 1);
      expect(
        story.readAsStringSync(),
        contains(
          'aru pose happy "晚上好。/en Hello there.//jp こんばんは。/" auto // 演出',
        ),
      );
      expect(
        names.readAsStringSync(),
        contains('"鸦露露/en Aruru//jp /" : aru at pose slot:aru'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingLocalizationEditor(
                  gameManager: _GameManager(),
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await _finishIO(tester);
      expect(find.text('こんばんは。'), findsOneWidget);
      expect(find.text('Hello there.'), findsOneWidget);
      expect(find.text('Aruru'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('保存多语言修改？'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'code editor switches language without exposing or deleting hidden versions',
    (tester) async {
      var reloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingScriptEditorOverlay(
                  gameManager: _GameManager(),
                  currentScript: 'start',
                  onClose: () {},
                  onReload: () async {
                    reloads++;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await _finishIO(tester);
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().controller!.text, contains('"晚上好。" auto'));
      expect(field().controller!.text, isNot(contains('/en')));
      await tester.tap(find.byKey(const ValueKey('script-editor-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(field().controller!.text, contains('"Good evening." auto'));
      await tester.enterText(
        find.byType(TextField),
        field().controller!.text.replaceFirst('Good evening.', 'Hello!'),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byKey(const ValueKey('script-editor-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語').last);
      await tester.pumpAndSettle();
      expect(field().controller!.text, contains('aru pose happy "" auto'));
      await tester.enterText(
        find.byType(TextField),
        field().controller!.text.replaceFirst(
          'aru pose happy ""',
          'aru pose happy "こんにちは。"',
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byTooltip('保存并重载 (⌘/Ctrl+S)'));
      await _finishIO(tester, until: () => reloads == 1);
      expect(reloads, 1);
      expect(
        story.readAsStringSync(),
        contains('"晚上好。/en Hello!//jp こんにちは。/" auto // 演出'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
