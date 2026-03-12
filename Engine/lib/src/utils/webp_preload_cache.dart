import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/engine_asset_loader.dart';

/// WebP动图预加载缓存
class WebPPreloadCache {
  static final WebPPreloadCache _instance = WebPPreloadCache._internal();
  factory WebPPreloadCache() => _instance;
  WebPPreloadCache._internal();

  final Map<String, List<ui.Image>> _frameCache = {};
  final Map<String, Duration> _durationCache = {};
  final Map<String, Completer<void>> _loadingCompleters = {};

  Future<void> preloadWebP(String assetName) async {
    if (_frameCache.containsKey(assetName) ||
        _loadingCompleters.containsKey(assetName)) {
      return;
    }

    final completer = Completer<void>();
    _loadingCompleters[assetName] = completer;

    try {
      final assetPath = await AssetManager().findAsset(assetName);
      if (assetPath == null) {
        if (kDebugMode) {
          print('[WebPPreloadCache] 资源不存在: $assetName');
        }
        completer.complete();
        _loadingCompleters.remove(assetName);
        return;
      }

      final bytes = await _loadWebPBytes(assetPath);
      if (bytes == null) {
        if (kDebugMode) {
          print('[WebPPreloadCache] 加载字节失败: $assetName');
        }
        completer.complete();
        _loadingCompleters.remove(assetName);
        return;
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frameCount = codec.frameCount;

      if (frameCount > 1) {
        final frames = <ui.Image>[];
        Duration totalDuration = Duration.zero;

        for (int i = 0; i < frameCount; i++) {
          final frame = await codec.getNextFrame();
          frames.add(frame.image);
          totalDuration += frame.duration;
        }

        _frameCache[assetName] = frames;
        _durationCache[assetName] = totalDuration;
      } else {
        final frame = await codec.getNextFrame();
        _frameCache[assetName] = [frame.image];
        _durationCache[assetName] = const Duration(milliseconds: 100);
      }

      completer.complete();
    } catch (e) {
      if (kDebugMode) {
        print('[WebPPreloadCache] 预加载失败 $assetName: $e');
      }
      completer.completeError(e);
    } finally {
      _loadingCompleters.remove(assetName);
    }
  }

  List<ui.Image>? getCachedFrames(String assetName) {
    return _frameCache[assetName];
  }

  Duration? getCachedDuration(String assetName) {
    return _durationCache[assetName];
  }

  bool isCached(String assetName) {
    return _frameCache.containsKey(assetName);
  }

  bool isLoading(String assetName) {
    return _loadingCompleters.containsKey(assetName);
  }

  Future<void> waitForLoad(String assetName) async {
    final completer = _loadingCompleters[assetName];
    if (completer != null) {
      await completer.future;
    }
  }

  void clearCache([String? assetName]) {
    if (assetName != null) {
      final frames = _frameCache.remove(assetName);
      if (frames != null) {
        for (final frame in frames) {
          frame.dispose();
        }
      }
      _durationCache.remove(assetName);
    } else {
      for (final frames in _frameCache.values) {
        for (final frame in frames) {
          frame.dispose();
        }
      }
      _frameCache.clear();
      _durationCache.clear();
    }
  }

  String get _debugRoot {
    const fromDefine =
        String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = Platform.environment['SAKI_GAME_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    return '';
  }

  Future<String> _getGamePath() async {
    if (_debugRoot.isNotEmpty) {
      return _debugRoot;
    }

    try {
      final assetContent =
          await EngineAssetLoader.loadString('assets/default_game.txt');
      final defaultGame = assetContent.trim();

      if (defaultGame.isEmpty) {
        throw Exception('default_game.txt is empty');
      }

      final gamePath = p.join(Directory.current.path, 'Game', defaultGame);
      return gamePath;
    } catch (e) {
      return '';
    }
  }

  Future<Uint8List?> _loadWebPBytes(String assetPath) async {
    try {
      if (kDebugMode) {
        final gamePath = await _getGamePath();
        if (gamePath.isNotEmpty) {
          final relativePath = assetPath.startsWith('assets/')
              ? assetPath.substring('assets/'.length)
              : assetPath;
          final fileSystemPath = p.normalize(p.join(gamePath, relativePath));
          final file = File(fileSystemPath);

          if (await file.exists()) {
            return await file.readAsBytes();
          }
        }
      }

      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }
}
