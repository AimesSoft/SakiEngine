import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

Future<Directory> initializeSettingsTestEnvironment() async {
  final directory = await Directory.systemTemp.createTemp(
    'saki-settings-test-',
  );
  final previous = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _SettingsPaths(directory.path);
  const channel = MethodChannel('window_manager');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
          return false;
        }
        return null;
      });
  configureRuntimeProject(
    projectName: 'Saki-Logger-Test',
    appName: 'Saki-Logger-Test',
    gamePath: directory.path,
  );
  final timers = <Timer>[];
  await runZoned(
    () => SettingsManager().init(),
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, period, callback) {
        final timer = parent.createPeriodicTimer(zone, period, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
  await LocalizationManager().init();
  await LocalizationManager().switchLanguage(SupportedLanguage.zhHans);
  addTearDown(() async {
    for (final timer in timers) {
      timer.cancel();
    }
    clearRuntimeProjectConfig();
    PathProviderPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  return directory;
}

class _SettingsPaths extends PathProviderPlatform {
  _SettingsPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getDownloadsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}
