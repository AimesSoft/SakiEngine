import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

export 'package:window_manager/window_manager.dart' show WindowListener;

class PlatformWindowManager {
  static bool get _isDesktop {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static Future<void> ensureInitialized() async {
    if (_isDesktop) {
      await windowManager.ensureInitialized();
    }
  }

  static Future<void> setPreventClose(bool prevent) async {
    if (_isDesktop) {
      await windowManager.setPreventClose(prevent);
    }
  }

  static Future<void> maximize() async {
    if (_isDesktop) {
      await windowManager.maximize();
    }
  }

  static void addListener(WindowListener listener) {
    if (_isDesktop) {
      windowManager.addListener(listener);
    }
  }

  static void removeListener(WindowListener listener) {
    if (_isDesktop) {
      windowManager.removeListener(listener);
    }
  }

  static Future<void> destroy() async {
    if (_isDesktop) {
      await windowManager.destroy();
    }
  }

  static Future<void> close() async {
    if (_isDesktop) {
      await windowManager.close();
    }
  }

  static Future<void> setTitle(String title) async {
    if (_isDesktop) {
      await windowManager.setTitle(title);
    }
  }

  static Future<void> setFullScreen(bool fullScreen) async {
    if (_isDesktop) {
      await windowManager.setFullScreen(fullScreen);
    }
  }
}
