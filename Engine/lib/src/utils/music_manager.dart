import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';

/// 音频轨道类型枚举
enum AudioTrackType {
  music, // 音乐轨道：循环播放，单轨道
  sound, // 音效轨道：单次播放，可重叠
}

/// 音频轨道配置
class AudioTrackConfig {
  final AudioTrackType type;
  final bool defaultLoop;
  final bool canOverlap;
  final String trackName;

  const AudioTrackConfig({
    required this.type,
    required this.defaultLoop,
    required this.canOverlap,
    required this.trackName,
  });

  static const music = AudioTrackConfig(
    type: AudioTrackType.music,
    defaultLoop: true,
    canOverlap: false,
    trackName: 'music',
  );

  static const sound = AudioTrackConfig(
    type: AudioTrackType.sound,
    defaultLoop: false,
    canOverlap: true,
    trackName: 'sound',
  );
}

class MusicManager extends ChangeNotifier {
  static final MusicManager _instance = MusicManager._internal();
  factory MusicManager() => _instance;
  MusicManager._internal();

  // 统一的音频轨道管理
  final Map<AudioTrackType, AudioPlayer> _trackPlayers = {
    AudioTrackType.music: AudioPlayer(),
    AudioTrackType.sound: AudioPlayer(),
  };

  // 音效可能需要多个播放器来支持重叠播放
  final List<AudioPlayer> _soundPlayers = [];
  int _soundPlayerIndex = 0;

  final _dataManager = UnifiedGameDataManager();
  String? _projectName;
  String? _currentBackgroundMusic;
  String? _currentSound;

  // 淡入淡出相关
  final Map<AudioTrackType, Timer?> _fadeTimers = {};
  final Map<AudioTrackType, bool> _isFading = {};
  final Map<AudioTrackType, double> _currentFadeVolume = {};

  bool get isMusicEnabled => _dataManager.isMusicEnabled;
  bool get isSoundEnabled => _dataManager.isSoundEnabled;
  double get musicVolume => _dataManager.musicVolume;
  double get soundVolume => _dataManager.soundVolume;
  String? get currentBackgroundMusic => _currentBackgroundMusic;
  String? get currentSound => _currentSound;

  Future<void> initialize() async {
    // 获取项目名称
    try {
      _projectName = await ProjectInfoManager().getAppName();
    } catch (e) {
      _projectName = 'SakiEngine';
    }

    // 初始化数据管理器
    await _dataManager.init(_projectName!);

    // 设置音乐轨道为循环播放
    await _trackPlayers[AudioTrackType.music]!.setLoopMode(LoopMode.one);

    // 设置音效轨道为单次播放
    await _trackPlayers[AudioTrackType.sound]!.setLoopMode(LoopMode.off);

    // 初始化多个音效播放器支持重叠播放
    for (int i = 0; i < 5; i++) {
      // 支持最多5个音效同时播放
      final player = AudioPlayer();
      await player.setLoopMode(LoopMode.off);
      _soundPlayers.add(player);
    }

    await _updateTrackVolume(AudioTrackType.music);
    await _updateTrackVolume(AudioTrackType.sound);
  }

  Future<void> setMusicEnabled(bool enabled) async {
    await _dataManager.setMusicEnabled(enabled, _projectName!);

    if (!enabled) {
      _cancelTrackFade(AudioTrackType.music);
      await _trackPlayers[AudioTrackType.music]!.pause();
    } else if (_currentBackgroundMusic != null) {
      await playAudio(
        _currentBackgroundMusic!,
        AudioTrackConfig.music,
        fadeTransition: true,
        fadeDuration: const Duration(milliseconds: 500),
      );
    }

    notifyListeners();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await _dataManager.setSoundEnabled(enabled, _projectName!);

    if (!enabled) {
      _cancelTrackFade(AudioTrackType.sound);
      await _trackPlayers[AudioTrackType.sound]!.pause();
      // 暂停所有音效播放器
      for (final player in _soundPlayers) {
        await player.pause();
      }
    }

    notifyListeners();
  }

  Future<void> setMusicVolume(double volume) async {
    await _dataManager.setMusicVolume(volume, _projectName!);
    await _updateTrackVolume(AudioTrackType.music);
    notifyListeners();
  }

  Future<void> setSoundVolume(double volume) async {
    await _dataManager.setSoundVolume(volume, _projectName!);
    await _updateTrackVolume(AudioTrackType.sound);
    notifyListeners();
  }

  /// 统一的轨道音量更新方法
  Future<void> _updateTrackVolume(AudioTrackType trackType) async {
    late bool isEnabled;
    late double baseVolume;

    switch (trackType) {
      case AudioTrackType.music:
        isEnabled = _dataManager.isMusicEnabled;
        baseVolume = _dataManager.musicVolume;
        break;
      case AudioTrackType.sound:
        isEnabled = _dataManager.isSoundEnabled;
        baseVolume = _dataManager.soundVolume;
        break;
    }

    final actualVolume = isEnabled ? baseVolume : 0.0;
    final isFading = _isFading[trackType] ?? false;
    final fadeVolume = isFading
        ? (_currentFadeVolume[trackType] ?? actualVolume)
        : actualVolume;

    await _trackPlayers[trackType]!.setVolume(fadeVolume);

    // 同时更新音效播放器
    if (trackType == AudioTrackType.sound) {
      for (final player in _soundPlayers) {
        await player.setVolume(fadeVolume);
      }
    }
  }

  /// 统一的淡出方法
  Future<void> _fadeOut(
    AudioTrackType trackType, {
    Duration duration = const Duration(milliseconds: 1000),
    VoidCallback? onComplete,
  }) async {
    late bool isEnabled;
    late double baseVolume;
    late String? currentTrack;

    switch (trackType) {
      case AudioTrackType.music:
        isEnabled = _dataManager.isMusicEnabled;
        baseVolume = _dataManager.musicVolume;
        currentTrack = _currentBackgroundMusic;
        break;
      case AudioTrackType.sound:
        isEnabled = _dataManager.isSoundEnabled;
        baseVolume = _dataManager.soundVolume;
        currentTrack = _currentSound;
        break;
    }

    if (!isEnabled || currentTrack == null) {
      onComplete?.call();
      return;
    }

    _cancelTrackFade(trackType); // 取消之前的淡化效果
    _isFading[trackType] = true;
    _currentFadeVolume[trackType] = baseVolume;

    const steps = 20; // 分20步进行淡出
    final stepDuration =
        Duration(milliseconds: duration.inMilliseconds ~/ steps);
    final volumeStep = baseVolume / steps;

    int currentStep = 0;
    _fadeTimers[trackType] = Timer.periodic(stepDuration, (timer) async {
      currentStep++;
      final newVolume = baseVolume - (volumeStep * currentStep);
      _currentFadeVolume[trackType] = newVolume.clamp(0.0, 1.0);

      await _updateTrackVolume(trackType);

      if (currentStep >= steps || _currentFadeVolume[trackType]! <= 0.0) {
        timer.cancel();
        _isFading[trackType] = false;
        _currentFadeVolume[trackType] = 0.0;
        onComplete?.call();
      }
    });
  }

  /// 统一的淡入方法
  Future<void> _fadeIn(
    AudioTrackType trackType, {
    Duration duration = const Duration(milliseconds: 1000),
    VoidCallback? onComplete,
  }) async {
    late bool isEnabled;
    late double baseVolume;
    late String? currentTrack;

    switch (trackType) {
      case AudioTrackType.music:
        isEnabled = _dataManager.isMusicEnabled;
        baseVolume = _dataManager.musicVolume;
        currentTrack = _currentBackgroundMusic;
        break;
      case AudioTrackType.sound:
        isEnabled = _dataManager.isSoundEnabled;
        baseVolume = _dataManager.soundVolume;
        currentTrack = _currentSound;
        break;
    }

    if (!isEnabled || currentTrack == null) {
      onComplete?.call();
      return;
    }

    _cancelTrackFade(trackType); // 取消之前的淡化效果
    _isFading[trackType] = true;
    _currentFadeVolume[trackType] = 0.0;
    await _updateTrackVolume(trackType); // 先设置为0音量

    const steps = 20; // 分20步进行淡入
    final stepDuration =
        Duration(milliseconds: duration.inMilliseconds ~/ steps);
    final volumeStep = baseVolume / steps;

    int currentStep = 0;
    _fadeTimers[trackType] = Timer.periodic(stepDuration, (timer) async {
      currentStep++;
      final newVolume = volumeStep * currentStep;
      _currentFadeVolume[trackType] = newVolume.clamp(0.0, baseVolume);

      await _updateTrackVolume(trackType);

      if (currentStep >= steps ||
          _currentFadeVolume[trackType]! >= baseVolume) {
        timer.cancel();
        _isFading[trackType] = false;
        _currentFadeVolume[trackType] = baseVolume;
        await _updateTrackVolume(trackType);
        onComplete?.call();
      }
    });
  }

  /// 取消指定轨道的淡化效果
  void _cancelTrackFade(AudioTrackType trackType) {
    _fadeTimers[trackType]?.cancel();
    _fadeTimers[trackType] = null;
    _isFading[trackType] = false;
  }

  /// 取消所有轨道的淡化效果
  void _cancelAllFades() {
    for (final trackType in AudioTrackType.values) {
      _cancelTrackFade(trackType);
    }
  }

  /// 统一的音频播放方法
  Future<void> playAudio(
    String assetPath,
    AudioTrackConfig config, {
    bool fadeTransition = true,
    Duration fadeDuration = const Duration(milliseconds: 1000),
    bool loop = false, // 允许覆盖默认循环设置
  }) async {
    try {
      // 根据轨道类型选择处理逻辑
      if (config.type == AudioTrackType.music) {
        // await
        _playMusic(
          assetPath,
          config,
          fadeTransition: fadeTransition,
          fadeDuration: fadeDuration,
          loop: loop || config.defaultLoop,
        );
      } else if (config.type == AudioTrackType.sound) {
        // await
        _playSound(
          assetPath,
          config,
          fadeTransition: fadeTransition,
          fadeDuration: fadeDuration,
          loop: loop,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error playing ${config.trackName}: $e');
      }
    }
  }

  /// 播放音乐（向后兼容的方法）
  Future<void> playBackgroundMusic(
    String assetPath, {
    bool fadeTransition = true,
    Duration fadeDuration = const Duration(milliseconds: 1000),
  }) async {
    await playAudio(
      assetPath,
      AudioTrackConfig.music,
      fadeTransition: fadeTransition,
      fadeDuration: fadeDuration,
    );
  }

  /// 播放音乐的具体实现
  Future<void> _playMusic(
    String assetPath,
    AudioTrackConfig config, {
    required bool fadeTransition,
    required Duration fadeDuration,
    required bool loop,
  }) async {
    final musicPlayer = _trackPlayers[AudioTrackType.music]!;
    if (_currentBackgroundMusic == assetPath && musicPlayer.playing) {
      return;
    }

    if (!_dataManager.isMusicEnabled) {
      _currentBackgroundMusic = assetPath;
      return;
    }

    final oldMusicPath = _currentBackgroundMusic;
    _currentBackgroundMusic = assetPath;

    Future<void> startNewMusic() async {
      await musicPlayer.stop();
      await musicPlayer.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await _setPlayerSource(musicPlayer, assetPath);
      await musicPlayer.play();
    }

    if (oldMusicPath != null && fadeTransition) {
      // 先淡出旧音乐
      await _fadeOut(
        AudioTrackType.music,
        duration: Duration(milliseconds: fadeDuration.inMilliseconds ~/ 2),
        onComplete: () async {
          await startNewMusic();
          await _fadeIn(
            AudioTrackType.music,
            duration: Duration(milliseconds: fadeDuration.inMilliseconds ~/ 2),
          );
        },
      );
    } else {
      // 没有旧音乐或不需要过渡，直接播放
      await startNewMusic();

      if (fadeTransition) {
        // 淡入新音乐
        await _fadeIn(AudioTrackType.music, duration: fadeDuration);
      } else {
        // 直接设置音量
        await _updateTrackVolume(AudioTrackType.music);
      }
    }
  }

  /// 播放音效的具体实现
  Future<void> _playSound(
    String assetPath,
    AudioTrackConfig config, {
    required bool fadeTransition,
    required Duration fadeDuration,
    required bool loop,
  }) async {
    if (!_dataManager.isSoundEnabled) {
      _currentSound = assetPath;
      return;
    }

    _currentSound = assetPath;

    // 对于音效，如果允许重叠，使用额外的播放器
    AudioPlayer player;
    if (config.canOverlap && _soundPlayers.isNotEmpty) {
      // 使用轮询的方式选择音效播放器
      player = _soundPlayers[_soundPlayerIndex % _soundPlayers.length];
      _soundPlayerIndex = (_soundPlayerIndex + 1) % _soundPlayers.length;
    } else {
      // 使用主音效播放器
      player = _trackPlayers[AudioTrackType.sound]!;
    }

    await player.stop();
    await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
    await _setPlayerSource(player, assetPath);
    await player.play();

    if (fadeTransition) {
      // 音效淡入（通常时间较短）
      await _fadeIn(
        AudioTrackType.sound,
        duration: Duration(milliseconds: fadeDuration.inMilliseconds ~/ 2),
      );
    } else {
      // 直接设置音量
      await _updateTrackVolume(AudioTrackType.sound);
    }
  }

  Future<void> _setPlayerSource(AudioPlayer player, String assetPath) async {
    final trimmed = assetPath.trim();
    if (_isNetworkPath(trimmed)) {
      await player.setUrl(trimmed);
      return;
    }
    if (trimmed.startsWith('file://')) {
      await player.setFilePath(Uri.parse(trimmed).toFilePath());
      return;
    }
    if (trimmed.startsWith('/')) {
      await player.setFilePath(trimmed);
      return;
    }
    if (trimmed.startsWith('asset:///')) {
      final normalized = trimmed.replaceFirst('asset:///', '');
      final resolved =
          normalized.startsWith('assets/') ? normalized : 'assets/$normalized';
      await player.setAsset(resolved);
      return;
    }

    final resolved =
        trimmed.startsWith('assets/') ? trimmed : 'assets/$trimmed';
    await player.setAsset(resolved);
  }

  bool _isNetworkPath(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('rtsp://') ||
        path.startsWith('rtmp://');
  }

  /// 统一的音频停止方法
  Future<void> stopAudio(
    AudioTrackConfig config, {
    bool fadeOut = true,
    Duration fadeDuration = const Duration(milliseconds: 800),
  }) async {
    if (config.type == AudioTrackType.music) {
      await stopBackgroundMusic(fadeOut: fadeOut, fadeDuration: fadeDuration);
    } else if (config.type == AudioTrackType.sound) {
      await _stopSound(fadeOut: fadeOut, fadeDuration: fadeDuration);
    }
  }

  /// 停止音效的具体实现
  Future<void> _stopSound({
    bool fadeOut = true,
    Duration fadeDuration = const Duration(milliseconds: 400),
  }) async {
    try {
      if (_currentSound == null) return;

      if (fadeOut && _dataManager.isSoundEnabled) {
        if (kDebugMode) {
          //print('[AudioManager] 淡出停止音效: $_currentSound');
        }

        await _fadeOut(
          AudioTrackType.sound,
          duration: fadeDuration,
          onComplete: () async {
            await _trackPlayers[AudioTrackType.sound]!.stop();
            // 停止所有音效播放器
            for (final player in _soundPlayers) {
              await player.stop();
            }
            _currentSound = null;
          },
        );
      } else {
        await _trackPlayers[AudioTrackType.sound]!.stop();
        for (final player in _soundPlayers) {
          await player.stop();
        }
        _currentSound = null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping sound effect: $e');
      }
    }
  }

  Future<void> stopBackgroundMusic({
    bool fadeOut = true,
    Duration fadeDuration = const Duration(milliseconds: 800),
  }) async {
    try {
      if (_currentBackgroundMusic == null) return;

      if (fadeOut && _dataManager.isMusicEnabled) {
        if (kDebugMode) {
          //print('[AudioManager] 淡出停止音乐: $_currentBackgroundMusic');
        }

        await _fadeOut(
          AudioTrackType.music,
          duration: fadeDuration,
          onComplete: () async {
            await _trackPlayers[AudioTrackType.music]!.stop();
            _currentBackgroundMusic = null;
          },
        );
      } else {
        await _trackPlayers[AudioTrackType.music]!.stop();
        _currentBackgroundMusic = null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping background music: $e');
      }
    }
  }

  Future<void> clearBackgroundMusic({
    bool fadeOut = true,
    Duration fadeDuration = const Duration(milliseconds: 800),
  }) async {
    try {
      if (_currentBackgroundMusic == null) return;

      if (fadeOut && _dataManager.isMusicEnabled) {
        if (kDebugMode) {
          //print('[AudioManager] 淡出清除音乐: $_currentBackgroundMusic');
        }

        await _fadeOut(
          AudioTrackType.music,
          duration: fadeDuration,
          onComplete: () async {
            await _trackPlayers[AudioTrackType.music]!.stop();
            _currentBackgroundMusic = null;
          },
        );
      } else {
        _cancelTrackFade(AudioTrackType.music); // 取消任何正在进行的淡化
        await _trackPlayers[AudioTrackType.music]!.stop();
        _currentBackgroundMusic = null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing background music: $e');
      }
    }
  }

  /// 检查指定音乐是否正在播放
  bool isPlayingMusic(String assetPath) {
    return _currentBackgroundMusic == assetPath &&
        _trackPlayers[AudioTrackType.music]!.playing;
  }

  /// 强制停止背景音乐（用于音乐区间系统）
  Future<void> forceStopBackgroundMusic({
    bool fadeOut = true,
    Duration fadeDuration = const Duration(milliseconds: 600),
  }) async {
    try {
      if (_currentBackgroundMusic == null) return;

      if (fadeOut && _dataManager.isMusicEnabled) {
        if (kDebugMode) {
          //print('[AudioManager] 淡出强制停止音乐: $_currentBackgroundMusic');
        }

        await _fadeOut(
          AudioTrackType.music,
          duration: fadeDuration,
          onComplete: () async {
            await _trackPlayers[AudioTrackType.music]!.stop();
            _currentBackgroundMusic = null;
          },
        );
      } else {
        _cancelTrackFade(AudioTrackType.music); // 取消任何正在进行的淡化
        await _trackPlayers[AudioTrackType.music]!.stop();
        _currentBackgroundMusic = null;
        if (kDebugMode) {
          //print('[AudioManager] 强制停止背景音乐');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error force stopping background music: $e');
      }
    }
  }

  Future<void> pauseBackgroundMusic() async {
    try {
      await _trackPlayers[AudioTrackType.music]!.pause();
    } catch (e) {
      if (kDebugMode) {
        print('Error pausing background music: $e');
      }
    }
  }

  Future<void> resumeBackgroundMusic() async {
    try {
      if (_dataManager.isMusicEnabled && _currentBackgroundMusic != null) {
        await _trackPlayers[AudioTrackType.music]!.play();
        // 恢复播放时淡入
        await _fadeIn(AudioTrackType.music,
            duration: const Duration(milliseconds: 500));
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error resuming background music: $e');
      }
    }
  }

  /// 播放音效（向后兼容的方法，现在支持淡入淡出）
  Future<void> playSoundEffect(String assetPath, {bool loop = false}) async {
    await playAudio(
      assetPath,
      AudioTrackConfig.sound,
      fadeTransition: true,
      fadeDuration: const Duration(milliseconds: 200),
      loop: loop,
    );
  }

  @override
  void dispose() {
    _cancelAllFades(); // 取消任何正在进行的淡化

    // 释放主轨道播放器
    for (final player in _trackPlayers.values) {
      player.dispose();
    }

    // 释放音效播放器
    for (final player in _soundPlayers) {
      player.dispose();
    }

    super.dispose();
  }
}
