import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';

import 'support/settings_test_environment.dart';

/// 回归测试：项目可以在设置界面追加自己的页签（例如"关于"制作人员名单）。
///
/// 引擎必须保证：内建页签不受影响、追加页签排在其后、选中后才渲染内容，
/// 并且页签标题会跟随界面语言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await initializeSettingsTestEnvironment();
  });

  tearDownAll(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
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

  /// 语言切换会写入设置（真实的异步 I/O），因此用有界轮询等待界面重建，
  /// 避免用固定帧数的等待产生偶发失败。断言仍然由调用方负责。
  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    List<SettingsTabContribution> extraTabs,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: SakiEngineConfig().themeColors.background,
          body: SettingsScreen(
            onClose: () {},
            useOverlayScaffold: false,
            extraTabs: extraTabs,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  test('settings.tabs.about is defined for every supported language', () async {
    final localization = LocalizationManager();
    for (final language in SupportedLanguage.values) {
      await localization.switchLanguage(language);
      final title = localization.t('settings.tabs.about');
      expect(title, isNotEmpty, reason: '缺翻译: $language');
      // 找不到 key 时会原样返回 key 本身。
      expect(title, isNot('settings.tabs.about'), reason: '缺翻译: $language');
    }
    await localization.switchLanguage(SupportedLanguage.zhHans);
  });

  testWidgets('extra tabs append after the built-in tabs', (tester) async {
    await pumpSettings(tester, [
      SettingsTabContribution(
        title: () => '关于',
        builder: (context) => const Text('制作人员名单'),
      ),
    ]);

    // 内建页签保持原样。
    expect(find.text('画面设置'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    // 追加页签的标题出现，但内容只有在选中后才构建。
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('制作人员名单'), findsNothing);

    await tester.tap(find.text('关于'));
    await settle(tester);
    expect(find.text('制作人员名单'), findsOneWidget);

    // 切回内建页签仍然正常。
    await tester.tap(find.text('画面设置'));
    await settle(tester);
    expect(find.text('制作人员名单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extra tab titles follow the interface language', (
    tester,
  ) async {
    await pumpSettings(tester, [
      SettingsTabContribution(
        title: () => LocalizationManager().t('settings.tabs.about'),
        builder: (context) => const Text('制作人员名单'),
      ),
    ]);

    // zh-Hans 是测试环境默认语言。
    await waitForText(tester, '关于');
    expect(find.text('关于'), findsOneWidget);

    await tester.runAsync(
      () => LocalizationManager().switchLanguage(SupportedLanguage.en),
    );
    await waitForText(tester, 'About');
    expect(find.text('About'), findsOneWidget);

    await tester.tap(find.text('About'));
    await settle(tester);
    expect(find.text('制作人员名单'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(
      () => LocalizationManager().switchLanguage(SupportedLanguage.zhHans),
    );
    await waitForText(tester, '关于');
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('settings screen without extra tabs is unchanged', (
    tester,
  ) async {
    await pumpSettings(tester, const []);

    expect(find.text('画面设置'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text('关于'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
