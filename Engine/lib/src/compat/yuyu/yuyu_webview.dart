import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'yuyu_resource_server.dart';

typedef YuyuMessageHandler =
    Future<void> Function(Map<String, dynamic> message);

/// Keeps IPC ordering across initial page load. A disposed view cannot deliver
/// late callbacks into the next game's interaction.
class YuyuWebChannel {
  final _events = <Map<String, dynamic>>[];
  Future<void> Function(Map<String, dynamic>)? _sender;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _generation = 0;
  void Function(Object)? onError;

  Future<void> send(Map<String, dynamic> event) {
    if (_disposed) return Future.value();
    final sender = _sender;
    if (sender == null) {
      if (_events.length >= 1024) {
        onError?.call(StateError('Web UI is not consuming events'));
        return Future.value();
      }
      _events.add(Map.of(event));
      return Future.value();
    }
    final generation = _generation;
    final delivery = _tail.then((_) async {
      if (!_disposed && generation == _generation) await sender(event);
    });
    // Preserve the failure for the caller, but keep later deliveries usable.
    _tail = delivery.catchError((Object error) {
      if (!_disposed && generation == _generation) onError?.call(error);
    });
    return _tail;
  }

  Future<void> attach(
    Future<void> Function(Map<String, dynamic>) sender,
  ) async {
    if (_disposed) return;
    _sender = sender;
    final waiting = List<Map<String, dynamic>>.from(_events);
    _events.clear();
    for (final event in waiting) {
      await send(event);
    }
  }

  void detach() {
    _generation++;
    _sender = null;
  }

  void dispose() {
    _disposed = true;
    _sender = null;
    _events.clear();
    onError = null;
  }
}

/// A native WebView used exclusively by the compatibility module.
class YuyuWebView extends StatefulWidget {
  final YuyuResourceServer resources;
  final YuyuWebChannel channel;
  final YuyuMessageHandler onMessage;
  final VoidCallback? onReady;
  final VoidCallback? onUnavailable;
  const YuyuWebView({
    super.key,
    required this.resources,
    required this.channel,
    required this.onMessage,
    this.onReady,
    this.onUnavailable,
  });

  @override
  State<YuyuWebView> createState() => _YuyuWebViewState();
}

class _YuyuWebViewState extends State<YuyuWebView> {
  String? _error;
  int _generation = 0;

  void _fail(Object error) {
    widget.channel.detach();
    widget.onUnavailable?.call();
    if (mounted) setState(() => _error = error.toString());
  }

  @override
  void initState() {
    super.initState();
    widget.channel.onError = _fail;
  }

  @override
  void dispose() {
    _generation++;
    widget.channel.detach();
    widget.channel.onError = null;
    widget.onUnavailable?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isIOS)) {
      return const Center(child: Text('当前平台尚未提供 YuYuball WebView 宿主。'));
    }
    if (_error != null) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Text(
            'YuYuball Web UI 加载失败：$_error',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(widget.resources.entryUri.toString()),
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        supportZoom: false,
        isInspectable: false,
      ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: _ipcShim,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'yuyuIpc',
          callback: (arguments) async {
            try {
              if (!mounted || arguments.length != 1) return;
              final generation = _generation;
              final raw = arguments.single;
              if (raw is! String || raw.length > 1024 * 1024) {
                throw const FormatException('Invalid IPC payload');
              }
              final payload = jsonDecode(raw);
              if (payload is! Map<String, dynamic> ||
                  payload['type'] is! String) {
                throw const FormatException('Invalid IPC message');
              }
              if (generation == _generation && mounted) {
                await widget.onMessage(payload);
              }
            } catch (error) {
              _fail(error);
            }
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async =>
          widget.resources.permits(Uri.parse(action.request.url.toString()))
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      onLoadStart: (_, _) {
        _generation++;
        widget.channel.detach();
        widget.onUnavailable?.call();
      },
      onLoadStop: (controller, uri) async {
        final generation = _generation;
        try {
          final ready = await controller.callAsyncJavaScript(
            functionBody: '''
            if (document.fonts) await document.fonts.ready;
            return !!(window.yuyuballOverlay && typeof window.yuyuballOverlay.receive === 'function');
          ''',
          );
          if (!mounted || generation != _generation) return;
          if (ready?.value != true) {
            throw StateError('Original overlay receiver is missing');
          }
          await widget.channel.attach((event) async {
            if (!mounted || generation != _generation) return;
            await controller.evaluateJavascript(
              source: 'window.yuyuballOverlay.receive(${jsonEncode(event)});',
            );
          });
          widget.onReady?.call();
        } catch (error) {
          _fail(error);
        }
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true && mounted) {
          _fail(error.description);
        }
      },
    );
  }

  static const _ipcShim = r'''
    (() => {
      const waiting = [];
      let ready = false;
      const send = value => {
        const text = typeof value === 'string' ? value : JSON.stringify(value);
        if (!ready) { if (waiting.length >= 1024) throw Error('IPC queue full'); waiting.push(text); return; }
        return window.flutter_inappwebview.callHandler('yuyuIpc', text);
      };
      window.ipc = { postMessage: send };
      const flush = () => {
        if (ready) return;
        ready = true;
        while (waiting.length) send(waiting.shift());
      };
      window.addEventListener('flutterInAppWebViewPlatformReady', flush);
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) flush();
    })();
  ''';
}
