import 'dart:async';
import 'dart:html' as html;

class PlatformWindowManager {
  static bool get isWindows => false;

  static bool get supportsWindowStateSync => true;

  static final Map<WindowListener, List<StreamSubscription<html.Event>>>
      _listeners = <WindowListener, List<StreamSubscription<html.Event>>>{};

  static Future<void> ensureInitialized() async {}

  static Future<void> setPreventClose(bool prevent) async {}

  static Future<void> maximize() async {}

  static Future<void> unmaximize() async {}

  static Future<bool?> isMaximized() async => false;

  static void addListener(WindowListener listener) {
    removeListener(listener);

    final subscriptions = <StreamSubscription<html.Event>>[];

    subscriptions.add(html.window.onBeforeUnload.listen((_) {
      Future.microtask(() => listener.onWindowClose());
    }));

    subscriptions.add(html.document.onFullscreenChange.listen((_) {
      final isFullscreen = html.document.fullscreenElement != null;
      if (isFullscreen) {
        listener.onWindowEnterFullScreen();
      } else {
        listener.onWindowLeaveFullScreen();
      }
    }));

    _listeners[listener] = subscriptions;
  }

  static void removeListener(WindowListener listener) {
    final subscriptions = _listeners.remove(listener);
    if (subscriptions == null) {
      return;
    }
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  }

  static Future<void> destroy() async {
    for (final subscriptions in _listeners.values) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    }
    _listeners.clear();

    try {
      html.window.close();
    } catch (_) {}
  }

  static Future<void> close() async {
    await destroy();
  }

  static Future<void> setTitle(String title) async {
    html.document.title = title;
  }

  static Future<void> prepareForWindowsFullscreenTransition() async {}

  static Future<void> setFullScreen(bool fullScreen) async {
    if (fullScreen) {
      try {
        final element = html.document.documentElement;
        if (element != null) {
          await element.requestFullscreen();
        }
      } catch (_) {}
      return;
    }

    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
    } catch (_) {}
  }

  static Future<bool?> isFullScreen() async {
    try {
      return html.document.fullscreenElement != null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setAspectRatio(double aspectRatio) async {}
}

mixin WindowListener {
  Future<void> onWindowClose();

  void onWindowEnterFullScreen() {}

  void onWindowLeaveFullScreen() {}

  void onWindowResize() {}

  void onWindowResized() {}

  void onWindowMaximize() {}

  void onWindowUnmaximize() {}

  void onWindowRestore() {}
}
