part of 'game_play_screen.dart';

extension _GamePlayScreenInteractions on _GamePlayScreenState {
  Future<void> _loadMouseRollbackBehavior() async {
    try {
      await _settingsManager.init();
      final behavior = await _settingsManager.getMouseRollbackBehavior();
      final parallaxEnabled = await _settingsManager.getMouseParallaxEnabled();
      if (!mounted) {
        _mouseRollbackBehavior = behavior;
        _isParallaxEnabled = parallaxEnabled;
        return;
      }
      _setStateIfMounted(() {
        _mouseRollbackBehavior = behavior;
        _isParallaxEnabled = parallaxEnabled;
      });
    } catch (_) {
      // 使用默认设置
      _mouseRollbackBehavior = SettingsManager.defaultMouseRollbackBehavior;
      _isParallaxEnabled = SettingsManager.defaultMouseParallaxEnabled;
    }
  }

  void _handleSettingsChanged() {
    final behavior = _settingsManager.currentMouseRollbackBehavior;
    final parallaxEnabled = _settingsManager.currentMouseParallaxEnabled;
    if (_mouseRollbackBehavior == behavior &&
        _isParallaxEnabled == parallaxEnabled) {
      return;
    }
    if (!mounted) {
      _mouseRollbackBehavior = behavior;
      _isParallaxEnabled = parallaxEnabled;
      return;
    }
    _setStateIfMounted(() {
      _mouseRollbackBehavior = behavior;
      _isParallaxEnabled = parallaxEnabled;
    });
  }

  void _returnToMainMenu() {
    // 停止所有音效，保留音乐
    _gameManager.stopAllSounds();

    if (mounted && widget.onReturnToMenu != null) {
      widget.onReturnToMenu!();
    } else if (mounted) {
      // 兼容性后退方案：使用传统的页面导航
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainMenuScreen(
            onNewGame: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    GamePlayScreen(gameModule: widget.gameModule),
              ),
            ),
            onLoadGame: () => _setStateIfMounted(() => _showLoadOverlay = true),
          ),
        ),
        (Route<dynamic> route) => false,
      );
    }
  }

  Widget _createDialogueBox({
    Key? key,
    String? speaker,
    String? speakerAlias, // 新增：角色简写参数
    required String dialogue,
    required bool isFastForwarding, // 新增快进状态参数
    required int scriptIndex, // 新增脚本索引参数
  }) {
    // 不在这里标记为已读！应该在用户推进对话时才标记
    final module = widget.gameModule ?? DefaultGameModule();
    return module.createDialogueBox(
      key: key,
      speaker: speaker,
      speakerAlias: speakerAlias,
      dialogue: dialogue,
      progressionManager: _dialogueProgressionManager,
      isFastForwarding: isFastForwarding,
      scriptIndex: scriptIndex,
    );
  }

  void _handleQuickMenuBack() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmDialog(
          title: '返回主菜单',
          content: '确定要返回主菜单吗？未保存的游戏进度将会丢失。',
          onConfirm: _returnToMainMenu,
        );
      },
    );
  }

  void _handleMouseRollbackAction() {
    if (_mouseRollbackBehavior == 'history') {
      if (mounted && !_showReviewOverlay) {
        final now = DateTime.now();
        if (_reviewReopenSuppressedUntil != null &&
            now.isBefore(_reviewReopenSuppressedUntil!)) {
          return;
        }
        _setStateIfMounted(() {
          _reviewOpenedByMouseRollback = true;
          _showReviewOverlay = true;
        });
      }
      return;
    }

    _handlePreviousDialogue();
  }

  void _toggleReviewOverlay(bool triggeredByOverscroll) {
    _setStateIfMounted(() {
      final newValue = !_showReviewOverlay;
      _showReviewOverlay = newValue;
      if (newValue) {
        if (!triggeredByOverscroll) {
          _reviewOpenedByMouseRollback = false;
        }
      } else {
        _reviewOpenedByMouseRollback = false;
      }
    });

    if (triggeredByOverscroll) {
      _reviewReopenSuppressedUntil = DateTime.now().add(
        const Duration(milliseconds: 250),
      );
    } else {
      _reviewReopenSuppressedUntil = null;
    }
  }

  void _handlePreviousDialogue() {
    final history = _gameManager.getDialogueHistory();

    // 如果当前显示选项，回到最后一句对话（选项出现前的对话）
    if (_isShowingMenu) {
      if (history.isNotEmpty) {
        final lastEntry = history.last;
        _jumpToHistoryEntryQuiet(lastEntry);
      }
    }
    // 如果没有选项，正常回到上一句
    else if (history.length >= 2) {
      final previousEntry = history[history.length - 2];
      _jumpToHistoryEntryQuiet(previousEntry);
    }
  }

  // 检查是否为桌面平台
  bool _isDesktopPlatform() {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // 设置系统级热键
  Future<void> _setupHotkey() async {
    // hotkey_manager 只在桌面平台可用
    if (!_isDesktopPlatform()) {
      print('跳过热键注册：当前平台不支持 hotkey_manager');
      return;
    }
    _reloadHotKey = HotKey(
      key: PhysicalKeyboardKey.keyR,
      modifiers: [HotKeyModifier.shift],
      scope: HotKeyScope.inapp, // 先使用应用内热键，避免权限问题
    );

    try {
      await hotKeyManager.register(
        _reloadHotKey!,
        keyDownHandler: (hotKey) {
          print('热键触发: ${hotKey.toJson()}');
          if (mounted) {
            _handleHotReload();
          }
        },
      );
      print('快捷键 Shift+R 注册成功');
    } catch (e) {
      print('快捷键注册失败: $e');
      // 如果系统级热键失败，尝试应用内热键
      _reloadHotKey = HotKey(
        key: PhysicalKeyboardKey.keyR,
        modifiers: [HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      );
      try {
        await hotKeyManager.register(
          _reloadHotKey!,
          keyDownHandler: (hotKey) {
            print('应用内热键触发: ${hotKey.toJson()}');
            if (mounted) {
              _handleHotReload();
            }
          },
        );
        print('应用内快捷键 Shift+R 注册成功');
      } catch (e2) {
        print('应用内快捷键注册也失败: $e2');
      }
    }

    // 注册开发者面板快捷键 Shift+D (仅在Debug模式下)
    if (kEngineDebugMode) {
      _developerPanelHotKey = HotKey(
        key: PhysicalKeyboardKey.keyD,
        modifiers: [HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      );

      try {
        await hotKeyManager.register(
          _developerPanelHotKey!,
          keyDownHandler: (hotKey) {
            print('开发者面板热键触发: ${hotKey.toJson()}');
            _setStateIfMounted(() {
              _showDeveloperPanel = !_showDeveloperPanel;
            });
          },
        );
        print('快捷键 Shift+D 注册成功 (开发者面板)');
      } catch (e) {
        print('开发者面板快捷键注册失败: $e');
      }
    }

    // 添加箭头键支持（替代滚轮）
    try {
      final nextHotKey = HotKey(
        key: PhysicalKeyboardKey.arrowDown,
        scope: HotKeyScope.inapp,
      );

      final prevHotKey = HotKey(
        key: PhysicalKeyboardKey.arrowUp,
        scope: HotKeyScope.inapp,
      );

      await hotKeyManager.register(
        nextHotKey,
        keyDownHandler: (hotKey) {
          //print('🎮 下箭头键 - 前进剧情');
          if (mounted &&
              !_isShowingMenu &&
              _gameManager.currentState.movieFile == null) {
            _dialogueProgressionManager.progressDialogue();
          }
        },
      );

      await hotKeyManager.register(
        prevHotKey,
        keyDownHandler: (hotKey) {
          //print('🎮 上箭头键 - 回滚剧情');
          if (mounted && _gameManager.currentState.movieFile == null) {
            _handlePreviousDialogue();
          }
        },
      );

      print('箭头键快捷键注册成功');
    } catch (e) {
      print('箭头键快捷键注册失败: $e');
    }
  }

  // 设置表情选择器管理器（Debug模式下的表情选择功能）
  void _setupExpressionSelectorManager() {
    _expressionSelectorManager = ExpressionSelectorManager(
      gameManager: _gameManager,
      showNotificationCallback: _showNotificationMessage,
      triggerReloadCallback: _handleHotReload,
      getCurrentGameState: () {
        // 获取当前游戏状态
        return _gameManager.currentState;
      },
      setExpressionSelectorVisibility: (show) {
        if (mounted) {
          // 检查是否可以显示表情选择器
          final canShow = show &&
              _expressionSelectorManager!.canShowExpressionSelector(
                showSaveOverlay: _showSaveOverlay,
                showLoadOverlay: _showLoadOverlay,
                showReviewOverlay: _showReviewOverlay,
                showSettings: _showSettings,
                showDeveloperPanel: _showDeveloperPanel,
                showDebugPanel: _showDebugPanel,
                isShowingMenu: _isShowingMenu,
              );

          _setStateIfMounted(() {
            _showExpressionSelector = canShow;
          });

          _expressionSelectorManager!.setExpressionSelectorVisible(canShow);
        }
      },
    );

    _expressionSelectorManager!.initialize();
  }

  // 设置console按键序列检测器（发行版也可用，方便玩家复制日志）
  void _setupConsoleSequenceDetector() {
    // 定义 c-o-n-s-o-l-e 按键序列
    final consoleSequence = [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyE,
    ];

    _consoleSequenceDetector = KeySequenceDetector(
      sequence: consoleSequence,
      onSequenceComplete: () {
        _setStateIfMounted(() {
          _showDebugPanel = !_showDebugPanel;
        });
        if (mounted) {
          _showNotificationMessage('调试面板 ${_showDebugPanel ? '开启' : '关闭'}');
        }
      },
      sequenceTimeout: const Duration(seconds: 3),
    );

    _consoleSequenceDetector!.startListening();

    print('Console按键序列检测器已启动 (c-o-n-s-o-l-e)');
    print('发行版用户可通过连续按下 c-o-n-s-o-l-e 来打开日志面板复制日志');
  }

  // 设置快进管理器
  void _setupFastForwardManager() {
    _fastForwardManager = FastForwardManager(
      dialogueProgressionManager: _dialogueProgressionManager,
      onFastForwardStateChanged: (isFastForwarding) {
        // 使用post frame callback延迟处理，避免在build期间调用setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _setStateIfMounted(() {
            _isFastForwarding = isFastForwarding;
          });
        });
      },
      canFastForward: () {
        // 检查是否有弹窗或菜单显示，如果有则不能快进
        final hasOverlayOpen = _isShowingMenu ||
            _showSaveOverlay ||
            _showLoadOverlay ||
            _showReviewOverlay ||
            _showSettings ||
            _showDeveloperPanel ||
            _showDebugPanel ||
            _showExpressionSelector;
        // 禁用在视频播放时的快进功能
        final isPlayingMovie = _gameManager.currentState.movieFile != null;
        return !hasOverlayOpen && !isPlayingMovie;
      },
      setGameManagerFastForward: (isFastForwarding) {
        // 通知GameManager快进状态变化
        _gameManager.setFastForwardMode(isFastForwarding);
      },
    );

    _fastForwardManager!.startListening();
    print('快进管理器已初始化 - 按住Ctrl键可快进对话');
  }

  // 设置已读文本跟踪
  void _setupReadTextTracking() async {
    // 初始化已读文本跟踪器
    await ReadTextTracker.instance.initialize();

    // 初始化已读文本快进管理器
    _readTextSkipManager = ReadTextSkipManager(
      gameManager: _gameManager,
      dialogueProgressionManager: _dialogueProgressionManager,
      readTextTracker: ReadTextTracker.instance,
      onSkipStateChanged: (isSkipping) {
        // 更新UI状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _setStateIfMounted(() {
            _isFastForwarding = isSkipping; // 同步快进状态到UI
          });
        });
      },
      canSkip: () {
        // 检查是否有弹窗或菜单显示，如果有则不能快进
        final hasOverlayOpen = _isShowingMenu ||
            _showSaveOverlay ||
            _showLoadOverlay ||
            _showReviewOverlay ||
            _showSettings ||
            _showDeveloperPanel ||
            _showDebugPanel ||
            _showExpressionSelector;
        // 禁用在视频播放时的快进功能
        final isPlayingMovie = _gameManager.currentState.movieFile != null;
        return !hasOverlayOpen && !isPlayingMovie;
      },
    );

    print('已读文本跟踪器已初始化 - 快捷菜单中的快进按钮只会跳过已读文本');
  }

  // 设置鼠标滚轮处理器
  void _setupMouseWheelHandler() {
    _mouseWheelHandler = MouseWheelHandler(
      onScrollForward: () {
        // 向前滚动: 推进对话
        _dialogueProgressionManager.progressDialogue();
        _autoPlayManager?.onManualProgress();
      },
      onScrollBackward: () {
        // 向后滚动: 根据设置执行行为
        _handleMouseRollbackAction();
      },
      shouldHandleScroll: () {
        // 检查是否有弹窗或菜单显示
        final hasOverlayOpen = _isShowingMenu ||
            _showSaveOverlay ||
            _showLoadOverlay ||
            _showReviewOverlay ||
            _showSettings ||
            _showDeveloperPanel ||
            _showDebugPanel ||
            _showExpressionSelector;

        // 检查是否正在播放视频
        final isPlayingMovie = _gameManager.currentState.movieFile != null;

        // 只有在没有弹窗且没有播放视频时才处理滚轮事件
        return !hasOverlayOpen && !isPlayingMovie;
      },
    );
  }

  // 设置自动播放管理器
  void _setupAutoPlayManager() {
    _autoPlayManager = AutoPlayManager(
      dialogueProgressionManager: _dialogueProgressionManager,
      onAutoPlayStateChanged: () {
        // 使用post frame callback延迟处理，避免在build期间调用setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _setStateIfMounted(() {
            _isAutoPlaying = _autoPlayManager!.isAutoPlaying;
            // 同步到GameManager
            _gameManager.setAutoPlayMode(_isAutoPlaying);
          });
        });
      },
      canAutoPlay: () {
        // 检查是否有弹窗或菜单显示，如果有则不能自动播放
        final hasOverlayOpen = _isShowingMenu ||
            _showSaveOverlay ||
            _showLoadOverlay ||
            _showReviewOverlay ||
            _showSettings ||
            _showDeveloperPanel ||
            _showDebugPanel ||
            _showExpressionSelector ||
            _isFastForwarding; // 快进时不能自动播放
        // 禁用在视频播放时的自动播放功能
        final isPlayingMovie = _gameManager.currentState.movieFile != null;
        return !hasOverlayOpen && !isPlayingMovie;
      },
    );

    print('自动播放管理器已初始化');
  }

  // 处理跳过已读文本
  void _handleSkipReadText() async {
    print('🎯 快进按钮被点击');

    // 获取快进模式设置
    final fastForwardMode = await SettingsManager().getFastForwardMode();
    print('🎯 当前快进模式: $fastForwardMode');

    if (fastForwardMode == 'force') {
      // 强制快进模式：使用FastForwardManager
      print(
        '🎯 使用强制快进模式 - _fastForwardManager: ${_fastForwardManager?.hashCode}',
      );
      _fastForwardManager?.toggleFastForward();
    } else {
      // 快进已读模式：使用ReadTextSkipManager
      print(
        '🎯 使用快进已读模式 - _readTextSkipManager: ${_readTextSkipManager?.hashCode}',
      );
      _readTextSkipManager?.toggleSkipping();
    }
  }

  // 获取当前有效的快进状态
  bool _getCurrentFastForwardState() {
    // 返回任意一个快进管理器的活动状态
    return (_fastForwardManager?.isFastForwarding ?? false) ||
        (_readTextSkipManager?.isSkipping ?? false);
  }

  // 处理自动播放
  void _handleAutoPlay() {
    print('🎯 自动播放按钮被点击 - _autoPlayManager: ${_autoPlayManager?.hashCode}');
    _autoPlayManager?.toggleAutoPlay();
  }

  // 新增：处理快速存档
  Future<void> _handleQuickSave() async {
    try {
      final saveLoadManager = SaveLoadManager();
      final snapshot = _gameManager.saveStateSnapshot();
      final poseConfigs = _gameManager.poseConfigs;

      await saveLoadManager.quickSave(_currentScript, snapshot, poseConfigs);
      _showNotificationMessage('快速存档成功');
    } catch (e) {
      _showNotificationMessage('快速存档失败: $e');
    }
  }

  // 显示通知消息
  void _showNotificationMessage(String message) {
    // 调用GameUILayer的showNotification方法
    _gameUILayerKey.currentState?.showNotification(message);
  }

  Future<void> _handleHotReload() async {
    await _gameManager.hotReload(_currentScript);
    _showNotificationMessage('重载完成');
  }

  Future<void> _jumpToHistoryEntry(DialogueHistoryEntry entry) async {
    _setStateIfMounted(() => _showReviewOverlay = false);
    await _gameManager.jumpToHistoryEntry(entry, _currentScript);
    _showNotificationMessage('跳转成功');
  }

  Future<void> _jumpToHistoryEntryQuiet(DialogueHistoryEntry entry) async {
    await _gameManager.jumpToHistoryEntry(entry, _currentScript);
  }

  Future<bool> _onWillPop() async {
    return await ExitConfirmationDialog.showExitConfirmation(
      context,
      hasProgress: true,
    );
  }
}
