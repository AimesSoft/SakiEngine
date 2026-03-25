import 'dart:async';
import 'dart:io';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

/// 手机端专用快捷菜单
/// 特点：占据屏幕高度90%，图标更大，支持滚动
class MobileQuickMenu extends StatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback? onQuickSave; // 新增：快速存档回调
  final VoidCallback onReview;
  final VoidCallback onSettings;
  final VoidCallback onBack;
  final VoidCallback onPreviousDialogue;
  final VoidCallback? onSkipRead;
  final bool isFastForwarding;
  final VoidCallback? onAutoPlay;
  final bool isAutoPlaying;
  final VoidCallback? onThemeToggle;

  const MobileQuickMenu({
    super.key,
    required this.onSave,
    required this.onLoad,
    this.onQuickSave, // 新增：快速存档回调（可选）
    required this.onReview,
    required this.onSettings,
    required this.onBack,
    required this.onPreviousDialogue,
    this.onSkipRead,
    this.isFastForwarding = false,
    this.onAutoPlay,
    this.isAutoPlaying = false,
    this.onThemeToggle,
  });

  @override
  State<MobileQuickMenu> createState() => _MobileQuickMenuState();

  // 静态全局实例引用，用于外部调用
  static _MobileQuickMenuState? _globalInstance;

  /// 外部调用：显示快捷菜单（用于移动端触屏唤起）
  static void showMenu() {
    _globalInstance?._showMenu();
  }

  /// 外部调用：隐藏快捷菜单
  static void hideMenu() {
    _globalInstance?._hideMenu();
  }

  /// 外部调用：触发延迟隐藏（用于移动端触屏）
  static void scheduleHide() {
    _globalInstance?._scheduleHideMenu();
  }
}

class _MobileQuickMenuState extends State<MobileQuickMenu> with SingleTickerProviderStateMixin {
  final LocalizationManager _localization = LocalizationManager();
  bool _isDarkMode = false;

  // 自动隐藏相关
  bool _isAutoHideEnabled = false;
  bool _isMenuHidden = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _hideTimer;
  static const Duration _hideDelay = Duration(milliseconds: 300); // 300ms后自动隐藏

  @override
  void initState() {
    super.initState();

    // 注册全局实例
    MobileQuickMenu._globalInstance = this;

    // 初始化滑动动画控制器
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0), // 向左滑出更远
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0, // 完全透明
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _loadThemeSetting();
    _loadAutoHideSetting();
    SettingsManager().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    // 取消全局实例引用
    if (MobileQuickMenu._globalInstance == this) {
      MobileQuickMenu._globalInstance = null;
    }
    _hideTimer?.cancel();
    SettingsManager().removeListener(_onSettingsChanged);
    _slideController.dispose();
    super.dispose();
  }

  void _loadAutoHideSetting() async {
    final enabled = await SettingsManager().getAutoHideQuickMenu();
    //print('[MobileQuickMenu] Auto hide setting loaded: $enabled');
    if (mounted) {
      final wasEnabled = _isAutoHideEnabled;
      setState(() {
        _isAutoHideEnabled = enabled;
      });

      // 设置变化时的处理
      if (_isAutoHideEnabled && !wasEnabled) {
        // 刚开启自动隐藏
        //print('[MobileQuickMenu] Auto hide enabled, hiding menu');
        _hideMenu();
      } else if (!_isAutoHideEnabled && wasEnabled) {
        // 刚关闭自动隐藏
        if (_isMenuHidden) {
          //print('[MobileQuickMenu] Auto hide disabled, showing menu');
          _showMenu();
        }
      }
    }
  }

  void _loadThemeSetting() async {
    final darkMode = await SettingsManager().getDarkMode();
    if (mounted) {
      setState(() {
        _isDarkMode = darkMode;
      });
    }
  }

  void _onSettingsChanged() {
    _loadAutoHideSetting();
    _loadThemeSetting();
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

  /// 延迟隐藏菜单（用于点击其他区域后自动隐藏）
  void _scheduleHideMenu() {
    //print('[MobileQuickMenu] scheduleHide called, autoHideEnabled=$_isAutoHideEnabled, isHidden=$_isMenuHidden');

    // 如果自动隐藏未开启，不处理
    if (!_isAutoHideEnabled) {
      //print('[MobileQuickMenu] Auto hide is disabled, skipping');
      return;
    }

    // 取消之前的计时器
    _hideTimer?.cancel();

    //print('[MobileQuickMenu] Starting hide timer (300ms)');
    // 设置新的延迟隐藏计时器
    _hideTimer = Timer(_hideDelay, () {
      //print('[MobileQuickMenu] Hide timer triggered, mounted=$mounted, autoHideEnabled=$_isAutoHideEnabled, isHidden=$_isMenuHidden');
      if (mounted && _isAutoHideEnabled && !_isMenuHidden) {
        //print('[MobileQuickMenu] Hiding menu now');
        _hideMenu();
      }
    });
  }

  void _toggleTheme() async {
    if (widget.onThemeToggle != null) {
      await SettingsManager().setDarkMode(!_isDarkMode);
      widget.onThemeToggle!();
    }
  }

  void _toggleAutoHide() async {
    await SettingsManager().setAutoHideQuickMenu(!_isAutoHideEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.menu);
    final screenSize = MediaQuery.of(context).size;

    // 计算菜单高度：屏幕高度的90%
    final menuHeight = screenSize.height * 0.9;

    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          height: menuHeight,
          width: 90 * scale, // 加宽以容纳更大的图标
          decoration: BoxDecoration(
            color: config.themeColors.background.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(config.baseWindowBorder > 0
                ? config.baseWindowBorder * scale * 1.5
                : 12 * scale),
            border: Border.all(
              color: config.themeColors.primary.withValues(alpha: 0.4),
              width: 2 * scale,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12 * scale,
                offset: Offset(0, 6 * scale),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(config.baseWindowBorder > 0
                ? config.baseWindowBorder * scale * 1.5
                : 12 * scale),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: 8 * scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 快速存档按钮（放在最前面）
                  if (widget.onQuickSave != null) ...[
                    _MobileQuickMenuButton(
                      text: _localization.t('quickMenu.quickSave'),
                      icon: Icons.save_as_outlined,
                      onPressed: widget.onQuickSave!,
                      scale: scale,
                      config: config,
                    ),
                    _buildDivider(scale, config),
                  ],
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.save'),
                    icon: Icons.save_outlined,
                    onPressed: widget.onSave,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.load'),
                    icon: Icons.folder_open_outlined,
                    onPressed: widget.onLoad,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.review'),
                    icon: Icons.auto_stories_outlined,
                    onPressed: widget.onReview,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.rollback'),
                    icon: Icons.undo_outlined,
                    onPressed: widget.onPreviousDialogue,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  // 自动播放按钮
                  if (widget.onAutoPlay != null) ...[
                    _MobileQuickMenuButton(
                      text: _localization.t('quickMenu.auto'),
                      icon: Icons.play_arrow_outlined,
                      onPressed: widget.onAutoPlay!,
                      scale: scale,
                      config: config,
                      isPressed: widget.isAutoPlaying,
                    ),
                    _buildDivider(scale, config),
                  ],
                  // 快进按钮
                  if (widget.onSkipRead != null) ...[
                    _MobileQuickMenuButton(
                      text: _localization.t('quickMenu.skip'),
                      icon: Icons.fast_forward_outlined,
                      onPressed: widget.onSkipRead!,
                      scale: scale,
                      config: config,
                      isPressed: widget.isFastForwarding,
                    ),
                    _buildDivider(scale, config),
                  ],
                  // 主题切换按钮
                  if (widget.onThemeToggle != null) ...[
                    _MobileQuickMenuButton(
                      text: _isDarkMode ? _localization.t('quickMenu.theme.light') : _localization.t('quickMenu.theme.dark'),
                      icon: _isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      onPressed: _toggleTheme,
                      scale: scale,
                      config: config,
                    ),
                    _buildDivider(scale, config),
                  ],
                  // 自动隐藏切换按钮（固定/取消固定）
                  _MobileQuickMenuButton(
                    text: _isAutoHideEnabled ? _localization.t('quickMenu.autoHide.pin') : _localization.t('quickMenu.autoHide.hide'),
                    icon: _isAutoHideEnabled ? Icons.push_pin_outlined : Icons.push_pin_sharp,
                    onPressed: _toggleAutoHide,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.settings'),
                    icon: Icons.settings_outlined,
                    onPressed: widget.onSettings,
                    scale: scale,
                    config: config,
                  ),
                  _buildDivider(scale, config),
                  _MobileQuickMenuButton(
                    text: _localization.t('quickMenu.back'),
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.onBack,
                    scale: scale,
                    config: config,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(double scale, SakiEngineConfig config) {
    return Container(
      width: 60 * scale,
      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
      child: Divider(
        height: 0,
        thickness: 1.5 * scale,
        color: config.themeColors.primary.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 手机端快捷菜单按钮
/// 特点：更大的点击区域，更大的图标
class _MobileQuickMenuButton extends StatefulWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  final double scale;
  final SakiEngineConfig config;
  final bool isPressed;

  const _MobileQuickMenuButton({
    required this.text,
    required this.icon,
    required this.onPressed,
    required this.scale,
    required this.config,
    this.isPressed = false,
  });

  @override
  State<_MobileQuickMenuButton> createState() => _MobileQuickMenuButtonState();
}

class _MobileQuickMenuButtonState extends State<_MobileQuickMenuButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressedAnimationController;
  late Animation<double> _pressedIconAnimation;
  final _uiSoundManager = UISoundManager();

  @override
  void initState() {
    super.initState();

    _pressedAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pressedIconAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_pressedAnimationController);

    if (widget.isPressed) {
      _pressedAnimationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_MobileQuickMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);

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
    _pressedAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final config = widget.config;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _uiSoundManager.playButtonClick();
          widget.onPressed();
        },
        splashColor: config.themeColors.primary.withValues(alpha: 0.2),
        highlightColor: config.themeColors.primary.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 60 * scale, // 按钮区域比图标稍大
          height: 60 * scale,
          margin: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 8 * scale),
          decoration: BoxDecoration(
            color: widget.isPressed
                ? config.themeColors.primary.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          child: AnimatedBuilder(
            animation: _pressedAnimationController,
            builder: (context, child) {
              double iconScale = 1.0;

              if (widget.isPressed) {
                // 脉冲动画
                iconScale = 1.0 + 0.2 * (0.5 + 0.5 * _pressedIconAnimation.value);
              }

              return Center(
                child: Transform.scale(
                  scale: iconScale,
                  child: Icon(
                    widget.icon,
                    color: widget.isPressed
                        ? config.themeColors.primary.withValues(alpha: 0.9)
                        : config.themeColors.primary,
                    size: 48 * scale, // 图标48，按钮60，留12的边距
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
