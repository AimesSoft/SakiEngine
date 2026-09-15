import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/game_file_logger.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/game_style_switch.dart';
import 'package:sakiengine/src/widgets/settings/developer_settings_tab.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';

import 'support/settings_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final captureKey = GlobalKey();

  setUpAll(() async {
    directory = await initializeSettingsTestEnvironment();
    final loader = FontLoader('SourceHanSansCN');
    loader.addFont(rootBundle.load('assets/fonts/SourceHanSansCN-Bold.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final config = SakiEngineConfig();
    config.dialogueTextStyle = config.dialogueTextStyle.copyWith(
      fontFamily: 'SourceHanSansCN',
    );
    config.reviewTitleTextStyle = config.reviewTitleTextStyle.copyWith(
      fontFamily: 'SourceHanSansCN',
    );
    await GameFileLogger().initialize();
  });

  tearDownAll(() async {
    await GameFileLogger().disposeForTesting();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final outputPath = Platform.environment['SAKI_SETTINGS_PREVIEW_DIR'];
    if (outputPath == null) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$outputPath/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'FPS moves to Developer and log switch creates a file and resets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() => SettingsManager().setShowFpsOverlay(true));
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: SettingsManager(),
            builder: (context, _) {
              SakiEngineConfig().updateThemeForDarkMode();
              return RepaintBoundary(
                key: captureKey,
                child: Scaffold(
                  backgroundColor: SakiEngineConfig().themeColors.background,
                  body: SettingsScreen(
                    onClose: () {},
                    useOverlayScaffold: false,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await settle(tester);
      expect(find.text('FPS 显示'), findsNothing);
      await tester.tap(find.text('开发者'));
      await settle(tester);
      expect(find.text('FPS 显示'), findsOneWidget);
      final fps = tester.widget<GameStyleSwitch>(
        find.byKey(const ValueKey('developer-fps-overlay')),
      );
      expect(fps.value, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('developer-file-logging')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
      expect(GameFileLogger().isWriting, isTrue);
      final file = File(GameFileLogger().currentLogFilePath!);
      expect(file.existsSync(), isTrue);
      expect(
        find.byKey(const ValueKey('developer-log-file-path')),
        findsOneWidget,
      );
      await capture(tester, 'developer-light');
      await tester.runAsync(() => SettingsManager().setDarkMode(true));
      await settle(tester);
      await capture(tester, 'developer-dark');
      tester.view.physicalSize = const Size(390, 700);
      await settle(tester);
      await capture(tester, 'developer-narrow');
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => SettingsManager().resetToDefault());
      await settle(tester);
      expect(GameFileLogger().isEnabled, isFalse);
      expect(GameFileLogger().isWriting, isFalse);
      expect(file.existsSync(), isTrue);
      expect(
        tester
            .widget<GameStyleSwitch>(
              find.byKey(const ValueKey('developer-fps-overlay')),
            )
            .value,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('developer-log-file-path')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('narrow layouts remain usable and show file creation errors', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final logger = GameFileLogger.forTesting(
      downloadsDirectory: directory,
      downloadsDirectoryResolver: () async => null,
    );
    addTearDown(() => tester.runAsync(logger.disposeForTesting));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: Scaffold(body: DeveloperSettingsTab(fileLogger: logger)),
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('developer-file-logging')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(logger.isWriting, isFalse);
    expect(
      find.byKey(const ValueKey('developer-log-file-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('developer-log-file-path')), findsNothing);
    await capture(tester, 'developer-narrow-error');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
