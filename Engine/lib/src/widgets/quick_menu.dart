import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/widgets/animated_tooltip.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class QuickMenu extends StatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback? onQuickSave; // 新增：快速存档回调
  final VoidCallback? onQuickLoad; // 新增：快速读档回调
  final VoidCallback onReview;
  final VoidCallback onSettings;
  final VoidCallback onBack;
  final VoidCallback onPreviousDialogue;
  final VoidCallback? onSkipRead; // 新增：跳过已读文本回调
  final bool isFastForwarding; // 新增：快进状态
  final VoidCallback? onAutoPlay; // 新增：自动播放回调
  final bool isAutoPlaying; // 新增：自动播放状态
  final VoidCallback? onThemeToggle; // 新增：主题切换回调
  final VoidCallback? onFlowchart; // 新增：流程图回调

  const QuickMenu({
    super.key,
    required this.onSave,
    required this.onLoad,
    this.onQuickSave, // 新增：快速存档回调（可选）
    this.onQuickLoad, // 新增：快速读档回调（可选）
    required this.onReview,
    required this.onSettings,
    required this.onBack,
    required this.onPreviousDialogue,
    this.onSkipRead, // 新增：跳过已读文本回调（可选）
    this.isFastForwarding = false, // 默认不快进
    this.onAutoPlay, // 新增：自动播放回调（可选）
    this.isAutoPlaying = false, // 新增：自动播放状态
    this.onThemeToggle, // 新增：主题切换回调（可选）
    this.onFlowchart, // 新增：流程图回调（可选）
  });

  @override
  State<QuickMenu> createState() => _QuickMenuState();

  /// 全局实例，用于从外部控制快捷菜单
  static _QuickMenuState? _globalInstance;

  /// 外部调用：其他菜单关闭后重新检查菜单状态
  static void recheckAfterMenuClose(GlobalKey<_QuickMenuState> key) {
    key.currentState?._recheckMousePosition();
  }

  /// 外部调用：覆盖层打开时自动隐藏快捷菜单
  static void hideOnOverlayOpen() {
    _globalInstance?._hideOnOverlayOpen();
  }

  /// 外部调用：显示快捷菜单（用于移动端触屏唤起）
  static void showMenu() {
    _globalInstance?._showMenu();
  }

  /// 外部调用：触发延迟隐藏（用于移动端触屏）
  static void scheduleHide() {
    _globalInstance?._scheduleHideMenu();
  }
}

class _QuickMenuState extends State<QuickMenu>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _hoveredButtonText;
  int? _hoveredButtonIndex;
  int _lastValidButtonIndex = 0; // 保存最后一个有效的按钮索引
  String _lastValidButtonText = ''; // 保存最后一个有效的按钮文本
  final GlobalKey _menuKey = GlobalKey();
  final LocalizationManager _localization = LocalizationManager();
  
  // 自动隐藏相关状态
  bool _isAutoHideEnabled = false;
  bool _isMenuHidden = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  Timer? _hideTimer; // 新增：延迟隐藏的计时器
  
  // 主题相关状态
  bool _isDarkMode = false; // 新增：当前主题状态
  
  // 常量
  static const Duration _animationDuration = Duration(milliseconds: 200);
  static const Duration _hideDelay = Duration(milliseconds: 500); // 新增：隐藏延迟

  @override
  void initState() {
    super.initState();

    // 注册全局实例
    QuickMenu._globalInstance = this;

    // 添加应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // 检查是否为移动端
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    // 初始化滑动动画
    _slideController = AnimationController(
      duration: _animationDuration,
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(isMobile ? -5.0 : -0.8, 0), // 移动端滑出更多以完全隐藏
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    // 加载设置并监听变化
    _loadAutoHideSetting(isMobile: isMobile);
    _loadThemeSetting(); // 新增：加载主题设置
    SettingsManager().addListener(_onSettingsChanged);

    // 初始状态：如果开启自动隐藏，则隐藏菜单
    if (_isAutoHideEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hideMenu();
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel(); // 新增：取消计时器
    
    // 清除全局实例
    if (QuickMenu._globalInstance == this) {
      QuickMenu._globalInstance = null;
    }
    
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期监听
    _slideController.dispose();
    SettingsManager().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _loadAutoHideSetting({bool isMobile = false}) async {
    final enabled = await SettingsManager().getAutoHideQuickMenu();
    if (mounted) {
      final wasEnabled = _isAutoHideEnabled;
      setState(() {
        _isAutoHideEnabled = enabled;
      });

      // 设置变化时的处理
      if (_isAutoHideEnabled && !wasEnabled) {
        // 刚开启自动隐藏
        _hideMenu();
      } else if (!_isAutoHideEnabled && wasEnabled) {
        // 刚关闭自动隐藏
        if (_isMenuHidden) {
          _showMenu();
        }
      }
    }
  }

  void _onSettingsChanged() {
    _loadAutoHideSetting();
    _loadThemeSetting(); // 新增：监听主题变化
  }

  void _loadThemeSetting() async {
    final darkMode = await SettingsManager().getDarkMode();
    if (mounted) {
      setState(() {
        _isDarkMode = darkMode;
      });
    }
  }

  void _toggleTheme() async {
    if (widget.onThemeToggle != null) {
      await SettingsManager().setDarkMode(!_isDarkMode);
      widget.onThemeToggle!();
    }
  }

  void _toggleAutoHide() async {
    await SettingsManager().setAutoHideQuickMenu(!_isAutoHideEnabled);
    _onSettingsChanged(); // 手动触发设置变化回调
  }

  void _hideMenu() {
    if (!_isAutoHideEnabled || _isMenuHidden) return;
    
    setState(() {
      _isMenuHidden = true;
    });
    _slideController.forward();
  }

  void _showMenu() {
    // 取消待进行的隐藏计时器
    _hideTimer?.cancel();
    
    if (!_isMenuHidden) return;
    
    setState(() {
      _isMenuHidden = false;
    });
    _slideController.reverse();
  }

  void _scheduleHideMenu() {
    // 取消之前的计时器
    _hideTimer?.cancel();
    
    // 设置新的延迟隐藏计时器
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && _isAutoHideEnabled && !_isMenuHidden) {
        _hideMenu();
      }
    });
  }

  void _onTriggerAreaEnter() {
    if (_isAutoHideEnabled && _isMenuHidden) {
      _showMenu();
    }
  }

  void _onTriggerAreaExit() {
    if (_isAutoHideEnabled && !_isMenuHidden) {
      _scheduleHideMenu(); // 使用延迟隐藏而不是立即隐藏
    }
  }

  /// 重新检查鼠标位置，在其他菜单关闭后调用
  void _recheckMousePosition() {
    if (!_isAutoHideEnabled || _isMenuHidden) return;
    
    // 延迟一帧后检查，确保UI状态已更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // 如果当前没有悬浮在快捷菜单区域，则隐藏菜单
      _scheduleHideMenu();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用重新获得焦点时，重新检查菜单状态
    if (state == AppLifecycleState.resumed) {
      // 延迟一点再检查，确保其他菜单已经关闭
      Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          _recheckMousePosition();
        }
      });
    }
  }

  /// 覆盖层打开时自动隐藏快捷菜单
  void _hideOnOverlayOpen() {
    if (_isAutoHideEnabled && !_isMenuHidden) {
      _hideTimer?.cancel(); // 取消延迟隐藏计时器
      _hideMenu(); // 立即隐藏
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.menu);
    final screenSize = MediaQuery.of(context).size;
    final mediaPadding = MediaQuery.of(context).padding;

    // 移动端（iOS/Android）需要额外的左边距以避开刘海/灵动岛
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    final extraLeftPadding = isMobile ? mediaPadding.left : 0.0;

    return Stack(
      children: [
        // 触发区域 - 窗口高度的一半，放在最底层
        Positioned(
          left: extraLeftPadding,
          top: 0,
          child: MouseRegion(
            onEnter: (_) => _onTriggerAreaEnter(),
            onExit: (_) => _onTriggerAreaExit(),
            child: Container(
              // 快捷菜单是竖排，所以触发区域是窗口高度的一半
              width: 100 * scale, // 左边缘触发区域
              height: screenSize.height * 0.5, // 窗口高度的一半
              color: Colors.transparent,
            ),
          ),
        ),

        // 实际的快捷菜单 - 放在触发区域之上，但确保不完全遮挡触发区域
        Positioned(
          left: 20 * scale + extraLeftPadding,
          top: 20 * scale,
          child: MouseRegion(
            onEnter: (_) {
              // 鼠标进入菜单时，取消任何待进行的隐藏
              _hideTimer?.cancel();
              _onTriggerAreaEnter();
            },
            onExit: (_) {
              // 菜单本身的退出不触发隐藏，因为可能只是在按钮间移动
              // 只有外层的触发区域退出才真正触发隐藏
            },
            child: AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(
                    _slideAnimation.value.dx * 120 * scale, // 根据缩放调整偏移
                    _slideAnimation.value.dy,
                  ),
                  child: Container(
                    key: _menuKey,
                    decoration: BoxDecoration(
                      color: config.themeColors.background.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(config.baseWindowBorder > 0 
                          ? config.baseWindowBorder * scale 
                          : 0 * scale),
                      border: Border.all(
                        color: config.themeColors.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8 * scale,
                          offset: Offset(0, 4 * scale),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 快速存档按钮（放在最前面）
                        if (widget.onQuickSave != null) ...[
                          _QuickMenuButton(
                            text: _localization.t('quickMenu.quickSave'),
                            icon: Icons.save_as_outlined, // 简单的保存图标用于快速存档
                            onPressed: widget.onQuickSave!,
                            scale: scale,
                            config: config,
                            onHover: (hovering, text) => setState(() {
                              _hoveredButtonText = hovering ? text : null;
                              _hoveredButtonIndex = hovering ? 0 : null;
                              if (hovering) {
                                _lastValidButtonIndex = 0;
                                _lastValidButtonText = text;
                              }
                            }),
                          ),
                          _buildDivider(scale, config),
                        ],
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.save'),
                          icon: Icons.save_outlined, // 有箭头的保存图标用于普通存档
                          onPressed: widget.onSave,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            _hoveredButtonIndex = hovering ? (widget.onQuickSave != null ? 1 : 0) : null;
                            if (hovering) {
                              _lastValidButtonIndex = widget.onQuickSave != null ? 1 : 0;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.load'),
                          icon: Icons.folder_open_outlined,
                          onPressed: widget.onLoad,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            _hoveredButtonIndex = hovering ? (widget.onQuickSave != null ? 2 : 1) : null;
                            if (hovering) {
                              _lastValidButtonIndex = widget.onQuickSave != null ? 2 : 1;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.review'),
                          icon: Icons.auto_stories_outlined,
                          onPressed: widget.onReview,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            _hoveredButtonIndex = hovering ? (widget.onQuickSave != null ? 3 : 2) : null;
                            if (hovering) {
                              _lastValidButtonIndex = widget.onQuickSave != null ? 3 : 2;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.rollback'),
                          icon: Icons.undo_outlined,
                          onPressed: widget.onPreviousDialogue,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            _hoveredButtonIndex = hovering ? (widget.onQuickSave != null ? 4 : 3) : null;
                            if (hovering) {
                              _lastValidButtonIndex = widget.onQuickSave != null ? 4 : 3;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        // 新增：自动播放按钮
                        if (widget.onAutoPlay != null) ...[
                          _QuickMenuButton(
                            text: _localization.t('quickMenu.auto'),
                            icon: Icons.play_arrow_outlined,
                            onPressed: widget.onAutoPlay!,
                            scale: scale,
                            config: config,
                            isPressed: widget.isAutoPlaying, // 传递自动播放状态
                            onHover: (hovering, text) => setState(() {
                              _hoveredButtonText = hovering ? text : null;
                              final index = widget.onQuickSave != null ? 5 : 4;
                              _hoveredButtonIndex = hovering ? index : null;
                              if (hovering) {
                                _lastValidButtonIndex = index;
                                _lastValidButtonText = text;
                              }
                            }),
                          ),
                          _buildDivider(scale, config),
                        ],
                        // 新增：快进按钮（跳过已读文本）
                        if (widget.onSkipRead != null) ...[
                          _QuickMenuButton(
                            text: _localization.t('quickMenu.skip'),
                            icon: Icons.fast_forward_outlined,
                            onPressed: widget.onSkipRead!,
                            scale: scale,
                            config: config,
                            isPressed: widget.isFastForwarding, // 传递快进状态
                            onHover: (hovering, text) => setState(() {
                              _hoveredButtonText = hovering ? text : null;
                              final baseIndex = widget.onQuickSave != null ? 5 : 4;
                              final index = widget.onAutoPlay != null ? baseIndex + 1 : baseIndex;
                              _hoveredButtonIndex = hovering ? index : null;
                              if (hovering) {
                                _lastValidButtonIndex = index;
                                _lastValidButtonText = text;
                              }
                            }),
                          ),
                          _buildDivider(scale, config),
                        ],
                        // 新增：主题切换按钮
                        if (widget.onThemeToggle != null) ...[
                          _QuickMenuButton(
                            text: _isDarkMode ? _localization.t('quickMenu.theme.light') : _localization.t('quickMenu.theme.dark'),
                            icon: _isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            onPressed: _toggleTheme,
                            scale: scale,
                            config: config,
                            onHover: (hovering, text) => setState(() {
                              _hoveredButtonText = hovering ? text : null;
                              final baseIndex = widget.onQuickSave != null ? 5 : 4;
                              final autoIndex = widget.onAutoPlay != null ? 1 : 0;
                              final skipIndex = widget.onSkipRead != null ? 1 : 0;
                              final index = baseIndex + autoIndex + skipIndex;
                              _hoveredButtonIndex = hovering ? index : null;
                              if (hovering) {
                                _lastValidButtonIndex = index;
                                _lastValidButtonText = text;
                              }
                            }),
                          ),
                          _buildDivider(scale, config),
                        ],
                        // 新增：自动隐藏切换按钮
                        _QuickMenuButton(
                          text: _isAutoHideEnabled ? _localization.t('quickMenu.autoHide.pin') : _localization.t('quickMenu.autoHide.hide'),
                          icon: _isAutoHideEnabled ? Icons.push_pin_outlined : Icons.push_pin_sharp,
                          onPressed: _toggleAutoHide,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            final baseIndex = widget.onQuickSave != null ? 5 : 4;
                            final autoIndex = widget.onAutoPlay != null ? 1 : 0;
                            final skipIndex = widget.onSkipRead != null ? 1 : 0;
                            final themeIndex = widget.onThemeToggle != null ? 1 : 0;
                            final index = baseIndex + autoIndex + skipIndex + themeIndex;
                            _hoveredButtonIndex = hovering ? index : null;
                            if (hovering) {
                              _lastValidButtonIndex = index;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        // 新增：流程图按钮
                        if (widget.onFlowchart != null) ...[
                          _QuickMenuButton(
                            text: _localization.t('quickMenu.flowchart'),
                            icon: Icons.account_tree_outlined,
                            onPressed: widget.onFlowchart!,
                            scale: scale,
                            config: config,
                            onHover: (hovering, text) => setState(() {
                              _hoveredButtonText = hovering ? text : null;
                              final baseIndex = widget.onQuickSave != null ? 5 : 4;
                              final autoIndex = widget.onAutoPlay != null ? 1 : 0;
                              final skipIndex = widget.onSkipRead != null ? 1 : 0;
                              final themeIndex = widget.onThemeToggle != null ? 1 : 0;
                              final index = baseIndex + autoIndex + skipIndex + themeIndex + 1;
                              _hoveredButtonIndex = hovering ? index : null;
                              if (hovering) {
                                _lastValidButtonIndex = index;
                                _lastValidButtonText = text;
                              }
                            }),
                          ),
                          _buildDivider(scale, config),
                        ],
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.settings'),
                          icon: Icons.settings_outlined,
                          onPressed: widget.onSettings,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            final baseIndex = widget.onQuickSave != null ? 5 : 4;
                            final autoIndex = widget.onAutoPlay != null ? 1 : 0;
                            final skipIndex = widget.onSkipRead != null ? 1 : 0;
                            final themeIndex = widget.onThemeToggle != null ? 1 : 0;
                            final index = baseIndex + autoIndex + skipIndex + themeIndex + 1;
                            _hoveredButtonIndex = hovering ? index : null;
                            if (hovering) {
                              _lastValidButtonIndex = index;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                        _buildDivider(scale, config),
                        _QuickMenuButton(
                          text: _localization.t('quickMenu.back'),
                          icon: Icons.arrow_back_rounded,
                          onPressed: widget.onBack,
                          scale: scale,
                          config: config,
                          onHover: (hovering, text) => setState(() {
                            _hoveredButtonText = hovering ? text : null;
                            final baseIndex = widget.onQuickSave != null ? 5 : 4;
                            final autoIndex = widget.onAutoPlay != null ? 1 : 0;
                            final skipIndex = widget.onSkipRead != null ? 1 : 0;
                            final themeIndex = widget.onThemeToggle != null ? 1 : 0;
                            final index = baseIndex + autoIndex + skipIndex + themeIndex + 2;
                            _hoveredButtonIndex = hovering ? index : null;
                            if (hovering) {
                              _lastValidButtonIndex = index;
                              _lastValidButtonText = text;
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        AnimatedTooltip(
          text: _hoveredButtonText ?? _lastValidButtonText,
          scale: scale,
          config: config,
          menuKey: _menuKey,
          buttonIndex: _hoveredButtonIndex ?? _lastValidButtonIndex,
          isVisible: _hoveredButtonText != null && _hoveredButtonIndex != null,
        ),
      ],
    );
  }

  Widget _buildDivider(double scale, SakiEngineConfig config) {
    return Container(
      width: 40 * scale,
      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: Divider(
        height: 0,
        thickness: 1.5 * scale,
        color: config.themeColors.primary.withValues(alpha: 0.6),
      ),
    );
  }
}

class _QuickMenuButton extends StatefulWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  final double scale;
  final SakiEngineConfig config;
  final Function(bool, String) onHover;
  final bool isPressed; // 新增：按钮是否处于按下状态

  const _QuickMenuButton({
    required this.text,
    required this.icon,
    required this.onPressed,
    required this.scale,
    required this.config,
    required this.onHover,
    this.isPressed = false, // 默认不按下
  });

  @override
  State<_QuickMenuButton> createState() => _QuickMenuButtonState();
}

class _QuickMenuButtonState extends State<_QuickMenuButton> with TickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  final _uiSoundManager = UISoundManager();

  // 新增：按下状态的动画控制器
  late AnimationController _pressedAnimationController;
  late Animation<double> _pressedIconAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // 按下状态动画
    _pressedAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _pressedIconAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_pressedAnimationController);
    
    // 如果初始就是按下状态，启动动画
    if (widget.isPressed) {
      _pressedAnimationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_QuickMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 监听按下状态变化
    if (widget.isPressed != oldWidget.isPressed) {
      if (widget.isPressed) {
        _pressedAnimationController.repeat();
      } else {
        _pressedAnimationController.stop();
        _pressedAnimationController.reset();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pressedAnimationController.dispose(); // 清理新的动画控制器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final config = widget.config;
    
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 48 * scale,
        height: 48 * scale,
        margin: EdgeInsets.symmetric(horizontal: 2 * scale, vertical: 4 * scale),
        child: InkWell(
          onTap: () {
            _uiSoundManager.playButtonClick();
            widget.onPressed();
          },
          onHover: (hovering) {
            setState(() => _isHovered = hovering);
            widget.onHover(hovering, widget.text);

            if (hovering) {
              _uiSoundManager.playButtonHover();
              _animationController.forward();
            } else {
              _animationController.reverse();
            }
          },
          hoverColor: config.themeColors.primary.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48 * scale,
            height: 48 * scale,
            decoration: BoxDecoration(
              color: widget.isPressed
                  ? config.themeColors.primary.withValues(alpha: 0.3) // 加深按下状态的背景色
                  : _isHovered 
                      ? config.themeColors.primary.withValues(alpha: 0.05)
                      : Colors.transparent,
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge([_animationController, _pressedAnimationController]),
              builder: (context, child) {
                // 按下状态时的图标动画效果
                double iconScale = _scaleAnimation.value;
                double iconRotation = _rotationAnimation.value;
                
                if (widget.isPressed) {
                  // 按下状态时播放脉冲动画 - 使用正弦波实现真正的往复
                  final pulseScale = 1.0 + 0.3 * sin(_pressedIconAnimation.value * pi);
                  iconScale = iconScale * pulseScale;
                  
                  // 自动播放图标特有的动画：循环脉冲 - 使用正弦波
                  if (widget.text == '自动') {
                    iconRotation += 0.1 * sin(_pressedIconAnimation.value * pi * 2); // 轻微摆动
                  }
                }
                
                return Center(
                  child: Transform.scale(
                    scale: iconScale,
                    child: Transform.rotate(
                      angle: iconRotation,
                      child: Icon(
                        widget.icon,
                        color: widget.isPressed 
                            ? config.themeColors.primary.withValues(alpha: 0.9) // 按下时图标颜色更鲜艳
                            : config.themeColors.primary,
                        size: config.quickMenuTextStyle.fontSize! * scale * 1.3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

