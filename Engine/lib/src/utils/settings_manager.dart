import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'platform_window_manager_io.dart' if (dart.library.html) 'platform_window_manager_web.dart';

class SettingsManager extends ChangeNotifier with WindowListener {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  // 默认值
  static const double defaultDialogOpacity = 0.9;
  static const bool defaultIsFullscreen = false;
  static const bool defaultDarkMode = false;
  static const bool defaultMouseParallaxEnabled = true;
  static const bool defaultShowFpsOverlay = false;
  static const bool defaultMusicEnabled = true;
  static const bool defaultSoundEnabled = true;
  static const double defaultMusicVolume = 0.8;
  static const double defaultSoundVolume = 0.8;

  // 打字机默认值 - 每秒显示字数
  static const double defaultTypewriterCharsPerSecond = 50.0;
  static const bool defaultSkipPunctuationDelay = false;
  static const bool defaultSpeakerAnimation = true;
  static const bool defaultAutoHideQuickMenu = false;
  static const String defaultMenuDisplayMode = 'windowed'; // 'windowed' or 'fullscreen'
  static const String defaultFastForwardMode = 'read_only'; // 'read_only' or 'force'
  static const String defaultMouseRollbackBehavior = 'rewind'; // 'rewind' or 'history'
  static const String defaultDialogueFontFamily = 'SourceHanSansCN'; // 对话文字字体
  static const String _showFpsOverlayKey = 'sakiengine.showFpsOverlay';

  final _dataManager = UnifiedGameDataManager();
  String? _projectName;
  bool _isInitialized = false;
  bool _windowSyncInitialized = false;
  bool _isApplyingWindowFullscreenState = false;
  Timer? _windowFullscreenPollTimer;

  static const Duration _windowFullscreenPollInterval =
      Duration(milliseconds: 400);

  Future<void> init() async {
    if (_isInitialized) return;

    // 获取项目名称
    try {
      _projectName = await ProjectInfoManager().getAppName();
    } catch (e) {
      _projectName = 'SakiEngine';
    }

    // 初始化数据管理器
    await _dataManager.init(_projectName!);

    _isInitialized = true;
    await _ensureWindowFullscreenSync();
  }

  Future<void> _ensureWindowFullscreenSync() async {
    if (_windowSyncInitialized) {
      return;
    }
    if (!PlatformWindowManager.supportsWindowStateSync) {
      return;
    }
    _windowSyncInitialized = true;

    PlatformWindowManager.addListener(this);
    await _syncFullscreenFromWindow();

    _windowFullscreenPollTimer?.cancel();
    _windowFullscreenPollTimer = Timer.periodic(
      _windowFullscreenPollInterval,
      (_) {
        unawaited(_syncFullscreenFromWindow());
      },
    );
  }

  Future<void> _syncFullscreenFromWindow() async {
    if (!_isInitialized || _projectName == null) {
      return;
    }
    final fullScreen = await PlatformWindowManager.isFullScreen();
    if (fullScreen == null) {
      return;
    }
    await _applyFullscreenStateFromWindow(fullScreen);
  }

  Future<void> _applyFullscreenStateFromWindow(bool isFullscreen) async {
    if (!_isInitialized || _projectName == null) {
      return;
    }
    if (_dataManager.isFullscreen == isFullscreen) {
      return;
    }
    if (_isApplyingWindowFullscreenState) {
      return;
    }

    _isApplyingWindowFullscreenState = true;
    try {
      await _dataManager.setIsFullscreen(isFullscreen, _projectName!);
      notifyListeners();
    } finally {
      _isApplyingWindowFullscreenState = false;
    }
  }

  // 对话框不透明度
  Future<double> getDialogOpacity() async {
    await init();
    return _dataManager.dialogOpacity;
  }

  double get currentDialogOpacity => _dataManager.dialogOpacity;

  Future<void> setDialogOpacity(double opacity) async {
    await init();
    await _dataManager.setDialogOpacity(opacity, _projectName!);
    notifyListeners();
  }

  // 全屏状态
  Future<bool> getIsFullscreen() async {
    await init();
    return _dataManager.isFullscreen;
  }

  bool get currentIsFullscreen => _dataManager.isFullscreen;

  Future<void> setIsFullscreen(bool isFullscreen) async {
    await init();
    await _dataManager.setIsFullscreen(isFullscreen, _projectName!);

    // 应用全屏设置（非Web平台）
    if (!kIsWeb) {
      if (isFullscreen) {
        await PlatformWindowManager.setFullScreen(true);
      } else {
        await PlatformWindowManager.setFullScreen(false);
      }
    }

    notifyListeners();
  }

  @override
  Future<void> onWindowClose() async {}

  @override
  void onWindowEnterFullScreen() {
    unawaited(_applyFullscreenStateFromWindow(true));
  }

  @override
  void onWindowLeaveFullScreen() {
    unawaited(_applyFullscreenStateFromWindow(false));
  }

  @override
  void onWindowResize() {
    unawaited(_syncFullscreenFromWindow());
  }

  @override
  void onWindowResized() {
    unawaited(_syncFullscreenFromWindow());
  }

  @override
  void onWindowMaximize() {
    unawaited(_syncFullscreenFromWindow());
  }

  @override
  void onWindowUnmaximize() {
    unawaited(_syncFullscreenFromWindow());
  }

  @override
  void onWindowRestore() {
    unawaited(_syncFullscreenFromWindow());
  }

  // 深色模式
  Future<bool> getDarkMode() async {
    await init();
    return _dataManager.darkMode;
  }

  bool get currentDarkMode => _dataManager.darkMode;

  Future<void> setDarkMode(bool isDarkMode) async {
    await init();
    await _dataManager.setDarkMode(isDarkMode, _projectName!);

    // 更新主题颜色
    SakiEngineConfig().updateThemeForDarkMode();

    notifyListeners();
  }

  // 打字机每秒字符数设置
  Future<double> getTypewriterCharsPerSecond() async {
    await init();
    return _dataManager.typewriterCharsPerSecond;
  }

  double get currentTypewriterCharsPerSecond => _dataManager.typewriterCharsPerSecond;

  Future<void> setTypewriterCharsPerSecond(double charsPerSecond) async {
    await init();
    await _dataManager.setTypewriterCharsPerSecond(charsPerSecond, _projectName!);
    notifyListeners();
  }

  // 跳过标点符号延迟设置
  Future<bool> getSkipPunctuationDelay() async {
    await init();
    return _dataManager.skipPunctuationDelay;
  }

  bool get currentSkipPunctuationDelay => _dataManager.skipPunctuationDelay;

  Future<void> setSkipPunctuationDelay(bool skip) async {
    await init();
    await _dataManager.setSkipPunctuationDelay(skip, _projectName!);
    notifyListeners();
  }

  // 说话人动画设置
  Future<bool> getSpeakerAnimation() async {
    await init();
    return _dataManager.speakerAnimation;
  }

  bool get currentSpeakerAnimation => _dataManager.speakerAnimation;

  Future<void> setSpeakerAnimation(bool enabled) async {
    await init();
    await _dataManager.setSpeakerAnimation(enabled, _projectName!);
    notifyListeners();
  }

  // 自动隐藏快捷菜单设置
  Future<bool> getAutoHideQuickMenu() async {
    await init();
    return _dataManager.autoHideQuickMenu;
  }

  bool get currentAutoHideQuickMenu => _dataManager.autoHideQuickMenu;

  Future<void> setAutoHideQuickMenu(bool enabled) async {
    await init();
    await _dataManager.setAutoHideQuickMenu(enabled, _projectName!);
    notifyListeners();
  }

  Future<bool> getMouseParallaxEnabled() async {
    await init();
    return _dataManager.mouseParallaxEnabled;
  }

  bool get currentMouseParallaxEnabled => _dataManager.mouseParallaxEnabled;

  Future<void> setMouseParallaxEnabled(bool enabled) async {
    await init();
    await _dataManager.setMouseParallaxEnabled(enabled, _projectName!);
    notifyListeners();
  }

  Future<bool> getShowFpsOverlay() async {
    await init();
    return _dataManager.getBoolVariable(
      _showFpsOverlayKey,
      defaultValue: defaultShowFpsOverlay,
    );
  }

  bool get currentShowFpsOverlay => _dataManager.getBoolVariable(
        _showFpsOverlayKey,
        defaultValue: defaultShowFpsOverlay,
      );

  Future<void> setShowFpsOverlay(bool enabled) async {
    await init();
    await _dataManager.setBoolVariable(
      _showFpsOverlayKey,
      enabled,
      _projectName!,
    );
    notifyListeners();
  }

  // 菜单页面显示模式设置
  Future<String> getMenuDisplayMode() async {
    await init();
    return _dataManager.menuDisplayMode;
  }

  String get currentMenuDisplayMode => _dataManager.menuDisplayMode;

  Future<void> setMenuDisplayMode(String mode) async {
    await init();
    await _dataManager.setMenuDisplayMode(mode, _projectName!);
    notifyListeners();
  }

  // 快进模式设置
  Future<String> getFastForwardMode() async {
    await init();
    return _dataManager.fastForwardMode;
  }

  String get currentFastForwardMode => _dataManager.fastForwardMode;

  Future<void> setFastForwardMode(String mode) async {
    await init();
    await _dataManager.setFastForwardMode(mode, _projectName!);
    notifyListeners();
  }

  // 鼠标回退行为设置
  Future<String> getMouseRollbackBehavior() async {
    await init();
    return _dataManager.mouseRollbackBehavior;
  }

  String get currentMouseRollbackBehavior => _dataManager.mouseRollbackBehavior;

  Future<void> setMouseRollbackBehavior(String behavior) async {
    await init();
    await _dataManager.setMouseRollbackBehavior(behavior, _projectName!);
    notifyListeners();
  }

  // 对话文字字体设置
  Future<String> getDialogueFontFamily() async {
    await init();
    return _dataManager.dialogueFontFamily;
  }

  String get currentDialogueFontFamily => _dataManager.dialogueFontFamily;

  Future<void> setDialogueFontFamily(String fontFamily) async {
    await init();
    await _dataManager.setDialogueFontFamily(fontFamily, _projectName!);
    notifyListeners();
  }

  // 恢复默认设置
  Future<void> resetToDefault() async {
    await init();

    final projectDefaultMenuDisplayMode =
        SakiEngineConfig().defaultMenuDisplayMode;

    await _dataManager.setDialogOpacity(defaultDialogOpacity, _projectName!);
    await _dataManager.setIsFullscreen(defaultIsFullscreen, _projectName!);
    await _dataManager.setDarkMode(defaultDarkMode, _projectName!);
    await _dataManager.setTypewriterCharsPerSecond(defaultTypewriterCharsPerSecond, _projectName!);
    await _dataManager.setSkipPunctuationDelay(defaultSkipPunctuationDelay, _projectName!);
    await _dataManager.setSpeakerAnimation(defaultSpeakerAnimation, _projectName!);
    await _dataManager.setAutoHideQuickMenu(defaultAutoHideQuickMenu, _projectName!);
    await _dataManager.setMouseParallaxEnabled(defaultMouseParallaxEnabled, _projectName!);
    await _dataManager.setBoolVariable(_showFpsOverlayKey, defaultShowFpsOverlay, _projectName!);
    await _dataManager.setMenuDisplayMode(projectDefaultMenuDisplayMode, _projectName!);
    await _dataManager.setFastForwardMode(defaultFastForwardMode, _projectName!);
    await _dataManager.setMouseRollbackBehavior(defaultMouseRollbackBehavior, _projectName!);
    await _dataManager.setDialogueFontFamily(defaultDialogueFontFamily, _projectName!);
    await _dataManager.setMusicEnabled(defaultMusicEnabled, _projectName!);
    await _dataManager.setSoundEnabled(defaultSoundEnabled, _projectName!);
    await _dataManager.setMusicVolume(defaultMusicVolume, _projectName!);
    await _dataManager.setSoundVolume(defaultSoundVolume, _projectName!);

    // 应用默认全屏设置（非Web平台）
    if (!kIsWeb) {
      await PlatformWindowManager.setFullScreen(defaultIsFullscreen);
    }

    notifyListeners();
  }

  // 获取所有设置
  Future<Map<String, dynamic>> getAllSettings() async {
    return {
      'dialogOpacity': await getDialogOpacity(),
      'isFullscreen': await getIsFullscreen(),
      'typewriterCharsPerSecond': await getTypewriterCharsPerSecond(),
      'skipPunctuationDelay': await getSkipPunctuationDelay(),
      'showFpsOverlay': await getShowFpsOverlay(),
    };
  }
}
