import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/utils/bundle_asset_path_probe.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

/// UI interaction sound manager (hover/click).
class UISoundManager {
  static final UISoundManager _instance = UISoundManager._internal();
  factory UISoundManager() => _instance;
  UISoundManager._internal();

  final List<AudioPlayer> _players = <AudioPlayer>[];
  int _playerIndex = 0;
  final UnifiedGameDataManager _dataManager = UnifiedGameDataManager();
  String? _projectName;
  final Random _random = Random();
  bool _initialized = false;

  static const String _soundPrefix = 'Assets/gui/';
  static const String _soundExtension = '.mp3';

  static const String buttonHover1 = 'button_1';
  static const String buttonHover2 = 'button_2';
  static const String buttonHover3 = 'button_3';
  static const String buttonClick = 'main_in';

  static const List<String> _hoverSounds = <String>[
    buttonHover1,
    buttonHover2,
    buttonHover3,
  ];

  bool get isSoundEnabled => _dataManager.isSoundEnabled;
  double get soundVolume => _dataManager.soundVolume;

  Future<void> initialize() async {
    if (_initialized) {
      await _updateVolume();
      return;
    }

    try {
      _projectName = await ProjectInfoManager().getAppName();
    } catch (_) {
      _projectName = 'SakiEngine';
    }

    await _dataManager.init(_projectName!);

    if (_players.isEmpty) {
      for (int i = 0; i < 3; i++) {
        final AudioPlayer player = AudioPlayer();
        await player.setLoopMode(LoopMode.off);
        _players.add(player);
      }
    }

    await _updateVolume();
    _initialized = true;
  }

  Future<void> _updateVolume() async {
    final double actualVolume = isSoundEnabled ? soundVolume : 0.0;
    for (final AudioPlayer player in _players) {
      await player.setVolume(actualVolume);
    }
  }

  String _buildSoundPath(String soundName) {
    return '$_soundPrefix$soundName$_soundExtension';
  }

  Future<void> playButtonHover() async {
    if (!isSoundEnabled) return;

    try {
      final String soundName = _hoverSounds[_random.nextInt(_hoverSounds.length)];
      await _playSound(soundName);
    } catch (e) {
      if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
        print('[UISoundManager] playButtonHover failed: $e');
      }
    }
  }

  Future<void> playButtonClick() async {
    if (!isSoundEnabled) return;

    try {
      await _playSound(buttonClick);
    } catch (e) {
      if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
        print('[UISoundManager] playButtonClick failed: $e');
      }
    }
  }

  Future<void> _playSound(String soundName) async {
    if (_players.isEmpty) {
      await initialize();
      if (_players.isEmpty) {
        if (kEngineDebugMode) {
          print('[UISoundManager] no available audio players');
        }
        return;
      }
    }

    final AudioPlayer player = _players[_playerIndex % _players.length];
    _playerIndex = (_playerIndex + 1) % _players.length;

    await player.setVolume(isSoundEnabled ? soundVolume : 0.0);

    final String assetPath = _buildSoundPath(soundName);
    await player.stop();
    await player.setLoopMode(LoopMode.off);
    await _setPlayerSource(player, assetPath);
    await player.play();
  }

  Future<void> stopAll() async {
    for (final AudioPlayer player in _players) {
      await player.stop();
    }
  }

  void dispose() {
    for (final AudioPlayer player in _players) {
      player.dispose();
    }
    _players.clear();
    _initialized = false;
  }

  Future<void> _setPlayerSource(AudioPlayer player, String assetPath) async {
    final String trimmed = assetPath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('assetPath must not be empty');
    }

    if (_isNetworkPath(trimmed)) {
      await player.setUrl(trimmed);
      return;
    }

    if (trimmed.startsWith('file://')) {
      await player.setFilePath(Uri.parse(trimmed).toFilePath());
      return;
    }

    if (p.isAbsolute(trimmed)) {
      await player.setFilePath(trimmed);
      return;
    }

    final String resolved = _normalizeBundleAssetPath(trimmed);
    final String? bundlePath = probeBundleAssetAbsolutePath(resolved);
    final bool? bundleExists = probeBundleAssetExists(resolved);

    if (bundlePath != null && bundleExists == true) {
      try {
        await player.setFilePath(bundlePath);
        return;
      } catch (e) {
        if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
          print('[UISoundManager] setFilePath(bundle) failed: $bundlePath, error=$e');
        }
      }
    }

    final String? gamePath = await _resolveGameAssetPath(resolved);
    if (gamePath != null) {
      try {
        await player.setFilePath(gamePath);
        return;
      } catch (e) {
        if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
          print('[UISoundManager] setFilePath(game) failed: $gamePath, error=$e');
        }
      }
    }

    await player.setAsset(resolved);
  }

  String _normalizeBundleAssetPath(String path) {
    final String normalized =
        path.startsWith('asset:///') ? path.replaceFirst('asset:///', '') : path;
    final String lower = normalized.toLowerCase();
    if (lower.startsWith('assets/') || lower.startsWith('packages/')) {
      return normalized;
    }
    return 'Assets/$normalized';
  }

  Future<String?> _resolveGameAssetPath(String resolvedAssetPath) async {
    if (!GamePathResolver.shouldUseFileSystemAssets) {
      return null;
    }

    final String? gamePath = await GamePathResolver.resolveGamePath();
    if (gamePath == null || gamePath.isEmpty) {
      return null;
    }

    return p.normalize(p.join(gamePath, resolvedAssetPath));
  }

  bool _isNetworkPath(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('rtsp://') ||
        path.startsWith('rtmp://');
  }

  bool _isExpectedInterruptionError(Object error) {
    final String message = error.toString().toLowerCase();
    return message.contains('loading interrupted') ||
        message.contains('player interrupted');
  }
}
