import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter_steamworks/flutter_steamworks.dart';

class SteamworksInitOptions {
  const SteamworksInitOptions({this.appId = SteamworksInitOptions.defaultAppId});

  static const int defaultAppId = 480;

  final int appId;
}

class SteamworksManager {
  SteamworksManager._();

  static final SteamworksManager instance = SteamworksManager._();

  final FlutterSteamworks _client = FlutterSteamworks();
  static const MethodChannel _channel = MethodChannel('flutter_steamworks');
  bool _initialized = false;
  SteamworksInitOptions? _options;

  bool get isInitialized => _initialized;

  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  SteamworksInitOptions? get options => _options;

  FlutterSteamworks get client {
    if (!_initialized) {
      throw StateError('Steamworks 尚未初始化，请先调用 initialize。');
    }

    return _client;
  }

  FlutterSteamworks? get clientOrNull => _initialized ? _client : null;

  Future<bool> initialize({SteamworksInitOptions options = const SteamworksInitOptions()}) async {
    if (_initialized) {
      return true;
    }

    if (!isSupportedPlatform) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks 当前平台不支持，跳过初始化。');
      }
      return false;
    }

    try {
      final ok = await _client.initSteam(options.appId);
      if (ok) {
        _initialized = true;
        _options = options;
      } else if (kEngineDebugMode) {
        debugPrint('Steamworks 初始化失败，请确认 Steam 客户端是否已启动。');
      }

      return ok;
    } catch (error, stackTrace) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks 初始化异常: $error');
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }

  Future<String?> getPlatformVersion() {
    return _client.getPlatformVersion();
  }

  Future<bool> requestCurrentStats() async {
    if (!_initialized) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('requestCurrentStats');
      return result ?? false;
    } catch (error, stackTrace) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks requestCurrentStats 异常: $error');
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }

  Future<bool> isAchievementUnlocked(String achievementId) async {
    if (!_initialized) {
      return false;
    }
    try {
      final statsOk = await requestCurrentStats();
      if (!statsOk) {
        return false;
      }
      final result = await _channel.invokeMethod<bool>(
        'getAchievement',
        <String, dynamic>{'achievementId': achievementId},
      );
      return result ?? false;
    } catch (error, stackTrace) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks isAchievementUnlocked 异常: $error');
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }

  Future<bool> unlockAchievement(String achievementId) async {
    if (!_initialized) {
      return false;
    }
    try {
      final statsOk = await requestCurrentStats();
      if (!statsOk) {
        return false;
      }
      final setOk = await _channel.invokeMethod<bool>(
            'setAchievement',
            <String, dynamic>{'achievementId': achievementId},
          ) ??
          false;
      if (!setOk) {
        return false;
      }
      final stored =
          await _channel.invokeMethod<bool>('storeStats') ?? false;
      return stored;
    } catch (error, stackTrace) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks unlockAchievement 异常: $error');
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }

  Future<bool> clearAchievement(String achievementId) async {
    if (!_initialized) {
      return false;
    }
    try {
      final statsOk = await requestCurrentStats();
      if (!statsOk) {
        return false;
      }
      final clearOk = await _channel.invokeMethod<bool>(
            'clearAchievement',
            <String, dynamic>{'achievementId': achievementId},
          ) ??
          false;
      if (!clearOk) {
        return false;
      }
      final stored =
          await _channel.invokeMethod<bool>('storeStats') ?? false;
      return stored;
    } catch (error, stackTrace) {
      if (kEngineDebugMode) {
        debugPrint('Steamworks clearAchievement 异常: $error');
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }
}
