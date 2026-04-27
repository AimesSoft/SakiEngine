import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/config/saki_pack_store.dart';
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
  bool _uiSoundsResolved = false;
  final List<String> _hoverSounds = <String>[];
  String? _clickSound;

  static const String _uiSoundDirectory = 'Assets/gui';
  static const List<String> _supportedSoundExtensions = <String>[
    '.mp3',
    '.ogg',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
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

    await _resolveUiSounds();
    await _updateVolume();
    _initialized = true;
  }

  Future<void> _updateVolume() async {
    final double actualVolume = isSoundEnabled ? soundVolume : 0.0;
    for (final AudioPlayer player in _players) {
      await player.setVolume(actualVolume);
    }
  }

  Future<void> playButtonHover() async {
    if (!isSoundEnabled) return;

    try {
      await _ensureReady();
      if (_hoverSounds.isEmpty) {
        return;
      }

      final String assetPath = _hoverSounds[_random.nextInt(_hoverSounds.length)];
      await _playSound(assetPath);
    } catch (e) {
      if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
        print('[UISoundManager] playButtonHover failed: $e');
      }
    }
  }

  Future<void> playButtonClick() async {
    if (!isSoundEnabled) return;

    try {
      await _ensureReady();
      final clickSound = _clickSound;
      if (clickSound == null || clickSound.isEmpty) {
        return;
      }
      await _playSound(clickSound);
    } catch (e) {
      if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
        print('[UISoundManager] playButtonClick failed: $e');
      }
    }
  }

  Future<void> _playSound(String assetPath) async {
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
    _hoverSounds.clear();
    _clickSound = null;
    _uiSoundsResolved = false;
    _initialized = false;
  }

  Future<void> _ensureReady() async {
    if (_players.isEmpty || !_initialized) {
      await initialize();
      return;
    }
    await _resolveUiSounds();
  }

  Future<void> _resolveUiSounds() async {
    if (_uiSoundsResolved) {
      return;
    }
    _uiSoundsResolved = true;

    final Set<String> files = <String>{};
    for (final extension in _supportedSoundExtensions) {
      try {
        final entries = await AssetManager().listAssets(_uiSoundDirectory, extension);
        files.addAll(entries);
      } catch (e) {
        if (kEngineDebugMode) {
          print(
              '[UISoundManager] listAssets failed: dir=$_uiSoundDirectory ext=$extension error=$e');
        }
      }
    }

    final List<String> audioAssets = files.map(_buildUiSoundPath).toList()..sort();
    if (audioAssets.isEmpty) {
      return;
    }

    final hoverCandidates = _pickHoverCandidates(audioAssets);
    final clickCandidate = _pickClickCandidate(audioAssets, hoverCandidates);

    _hoverSounds
      ..clear()
      ..addAll(hoverCandidates);
    _clickSound = clickCandidate;
  }

  String _buildUiSoundPath(String fileName) {
    if (fileName.startsWith('Assets/') || fileName.startsWith('assets/')) {
      return fileName;
    }
    return '$_uiSoundDirectory/$fileName';
  }

  List<String> _pickHoverCandidates(List<String> audioAssets) {
    final List<String> hoverSounds = audioAssets.where((assetPath) {
      final stem = _soundStemLower(assetPath);
      return stem.contains('hover') ||
          stem.startsWith('button') ||
          stem.contains('rollover') ||
          stem.contains('cursor') ||
          stem.contains('focus');
    }).toList();

    if (hoverSounds.isNotEmpty) {
      return hoverSounds;
    }
    return List<String>.from(audioAssets);
  }

  String? _pickClickCandidate(
    List<String> audioAssets,
    List<String> hoverCandidates,
  ) {
    for (final assetPath in audioAssets) {
      final stem = _soundStemLower(assetPath);
      if (stem.contains('click') ||
          stem.contains('confirm') ||
          stem.contains('select') ||
          stem.contains('press') ||
          stem.contains('enter') ||
          stem.contains('ok') ||
          stem.contains('main')) {
        return assetPath;
      }
    }

    for (final assetPath in audioAssets) {
      if (!hoverCandidates.contains(assetPath)) {
        return assetPath;
      }
    }

    return audioAssets.first;
  }

  String _soundStemLower(String assetPath) {
    return p.basenameWithoutExtension(assetPath).toLowerCase();
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
    final String? packPlaybackPath =
        await SakiPackStore.instance.resolvePathForPlayback(resolved) ??
            await SakiPackStore.instance.resolvePathForPlayback(trimmed);
    if (packPlaybackPath != null) {
      try {
        await player.setFilePath(packPlaybackPath);
        return;
      } catch (e) {
        if (kEngineDebugMode && !_isExpectedInterruptionError(e)) {
          print(
              '[UISoundManager] setFilePath(sakipack) failed: $packPlaybackPath, error=$e');
        }
      }
    }

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
