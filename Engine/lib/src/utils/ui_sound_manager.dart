import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';

/// UI交互音效管理器
/// 专门管理UI界面的交互音效（按钮悬停、点击等）
/// 受音频设置的音效滑块控制
class UISoundManager {
  static final UISoundManager _instance = UISoundManager._internal();
  factory UISoundManager() => _instance;
  UISoundManager._internal();

  // 音效播放器池，支持多个音效同时播放
  final List<AudioPlayer> _players = [];
  int _playerIndex = 0;
  final _dataManager = UnifiedGameDataManager();
  String? _projectName;
  final _random = Random();

  // 音效文件配置（音效名称和路径前缀）
  static const String _soundPrefix = 'Assets/gui/';
  static const String _soundExtension = '.mp3';

  // 音效类型
  static const String buttonHover1 = 'button_1';
  static const String buttonHover2 = 'button_2';
  static const String buttonHover3 = 'button_3';
  static const String buttonClick = 'main_in';

  // 悬停音效列表
  static const List<String> _hoverSounds = [
    buttonHover1,
    buttonHover2,
    buttonHover3,
  ];

  bool get isSoundEnabled => _dataManager.isSoundEnabled;
  double get soundVolume => _dataManager.soundVolume;

  /// 初始化UI音效管理器
  Future<void> initialize() async {
    try {
      // 获取项目名称
      _projectName = await ProjectInfoManager().getAppName();
    } catch (e) {
      _projectName = 'SakiEngine';
    }

    // 初始化数据管理器
    await _dataManager.init(_projectName!);

    // 创建音效播放器池（支持最多3个UI音效同时播放）
    for (int i = 0; i < 3; i++) {
      final player = AudioPlayer();
      await player.setLoopMode(LoopMode.off);
      _players.add(player);
    }

    // 更新音量
    await _updateVolume();
  }

  /// 更新所有播放器的音量
  Future<void> _updateVolume() async {
    final actualVolume = isSoundEnabled ? soundVolume : 0.0;
    for (final player in _players) {
      await player.setVolume(actualVolume);
    }
  }

  /// 构建完整的音效资源路径
  String _buildSoundPath(String soundName) {
    return '$_soundPrefix$soundName$_soundExtension';
  }

  /// 播放按钮悬停音效（随机选择button_1、button_2或button_3）
  Future<void> playButtonHover() async {
    if (!isSoundEnabled) return;

    try {
      // 随机选择一个悬停音效
      final soundName = _hoverSounds[_random.nextInt(_hoverSounds.length)];
      await _playSound(soundName);
    } catch (e) {
      if (kEngineDebugMode) {
        print('[UISoundManager] 播放按钮悬停音效失败: $e');
      }
    }
  }

  /// 播放按钮点击音效（main_in）
  Future<void> playButtonClick() async {
    if (!isSoundEnabled) return;

    try {
      await _playSound(buttonClick);
    } catch (e) {
      if (kEngineDebugMode) {
        print('[UISoundManager] 播放按钮点击音效失败: $e');
      }
    }
  }

  /// 内部方法：播放指定音效
  Future<void> _playSound(String soundName) async {
    // 使用轮询方式选择播放器
    final player = _players[_playerIndex % _players.length];
    _playerIndex = (_playerIndex + 1) % _players.length;

    // 更新音量（确保使用最新设置）
    await player.setVolume(isSoundEnabled ? soundVolume : 0.0);

    // 构建完整路径并播放音效
    final assetPath = _buildSoundPath(soundName);
    await player.stop();
    await player.setLoopMode(LoopMode.off);
    await _setPlayerSource(player, assetPath);
    await player.play();
  }

  /// 停止所有UI音效
  Future<void> stopAll() async {
    for (final player in _players) {
      await player.stop();
    }
  }

  /// 释放资源
  void dispose() {
    for (final player in _players) {
      player.dispose();
    }
    _players.clear();
  }

  Future<void> _setPlayerSource(AudioPlayer player, String assetPath) async {
    final trimmed = assetPath.trim();
    final lower = trimmed.toLowerCase();
    final resolved = (lower.startsWith('assets/') ||
            lower.startsWith('packages/'))
        ? trimmed
        : 'Assets/$trimmed';
    await player.setAsset(resolved);
  }
}
