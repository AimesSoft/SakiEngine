import 'dart:async';
import 'dart:html' as html;

class PlatformWindowManager {
  static final Map<WindowListener, StreamSubscription<html.Event>> _listeners =
      <WindowListener, StreamSubscription<html.Event>>{};

  static Future<void> ensureInitialized() async {}

  static Future<void> setPreventClose(bool prevent) async {}

  static Future<void> maximize() async {}

  static void addListener(WindowListener listener) {
    removeListener(listener);

    final subscription = html.window.onBeforeUnload.listen((_) {
      Future.microtask(() => listener.onWindowClose());
    });
    _listeners[listener] = subscription;
  }

  static void removeListener(WindowListener listener) {
    final subscription = _listeners.remove(listener);
    subscription?.cancel();
  }

  static Future<void> destroy() async {
    for (final subscription in _listeners.values) {
      subscription.cancel();
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
}

mixin WindowListener {
  Future<void> onWindowClose();
}
