import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/widgets/common/close_button.dart';
import 'package:sakiengine/src/widgets/quick_menu.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/svg_color_filter_utils.dart';

class OverlayScaffold extends StatefulWidget {
  final String title;
  final Widget content;
  final Widget? footer;
  final bool showHeader;
  final bool enableWindowDragInWindowedMode;
  final bool clearBackdropInWindowedMode;
  final bool disableWindowTintOverlay;
  final double windowedDragHandleHeight;
  final void Function(bool triggeredByOverscroll) onClose;

  const OverlayScaffold({
    super.key,
    required this.title,
    required this.content,
    this.footer,
    this.showHeader = true,
    this.enableWindowDragInWindowedMode = false,
    this.clearBackdropInWindowedMode = false,
    this.disableWindowTintOverlay = false,
    this.windowedDragHandleHeight = 56.0,
    required this.onClose,
  });

  @override
  OverlayScaffoldState createState() => OverlayScaffoldState();
}

class OverlayScaffoldState extends State<OverlayScaffold>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _backdropAnimation;
  bool _isClosing = false;

  String _menuDisplayMode = SettingsManager.defaultMenuDisplayMode;
  Offset _windowDragDelta = Offset.zero;
  Offset _dragStartGlobal = Offset.zero;
  Offset _dragStartDelta = Offset.zero;

  // ESC热键
  late HotKey _escHotKey;

  @override
  void initState() {
    super.initState();

    // 加载菜单显示模式设置
    _loadMenuDisplayMode();

    // 监听设置变化
    SettingsManager().addListener(_onSettingsChanged);

    // 当覆盖层打开时，自动隐藏快捷菜单
    // 使用 addPostFrameCallback 避免在build阶段调用setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      QuickMenu.hideOnOverlayOpen();
    });

    // 注册ESC热键
    _escHotKey = HotKey(
      key: PhysicalKeyboardKey.escape,
      scope: HotKeyScope.inapp,
    );
    HotKeyManager.instance.register(_escHotKey, keyDownHandler: (_) {
      close();
    });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));

    _backdropAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    // 移除设置监听器
    SettingsManager().removeListener(_onSettingsChanged);
    // 注销ESC热键
    HotKeyManager.instance.unregister(_escHotKey);
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadMenuDisplayMode() async {
    final mode = await SettingsManager().getMenuDisplayMode();
    if (mounted) {
      setState(() {
        _menuDisplayMode = mode;
      });
    }
  }

  void _onSettingsChanged() {
    _loadMenuDisplayMode();
  }

  Future<void> close({bool triggeredByOverscroll = false}) async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    await _animationController.reverse();
    if (mounted) {
      widget.onClose(triggeredByOverscroll);
    }
  }

  void _handleClose({bool triggeredByOverscroll = false}) {
    close(triggeredByOverscroll: triggeredByOverscroll);
  }

  Offset _clampWindowDragDelta(Offset delta, Size screenSize, Size windowSize) {
    final maxDx = math.max(0.0, (screenSize.width - windowSize.width) / 2);
    final maxDy = math.max(0.0, (screenSize.height - windowSize.height) / 2);
    return Offset(
      delta.dx.clamp(-maxDx, maxDx).toDouble(),
      delta.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _onWindowDragStart(DragStartDetails details) {
    _dragStartGlobal = details.globalPosition;
    _dragStartDelta = _windowDragDelta;
  }

  void _onWindowDragUpdate(
    DragUpdateDetails details, {
    required Size screenSize,
    required Size windowSize,
  }) {
    final delta = details.globalPosition - _dragStartGlobal;
    final next = _dragStartDelta + delta;
    setState(() {
      _windowDragDelta = _clampWindowDragDelta(next, screenSize, windowSize);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);
    final isFullscreen = _menuDisplayMode == 'fullscreen';
    final windowWidth =
        isFullscreen ? screenSize.width : screenSize.width * 0.85;
    final windowHeight =
        isFullscreen ? screenSize.height : screenSize.height * 0.8;
    final windowSize = Size(windowWidth, windowHeight);
    final clampedWindowDelta = isFullscreen
        ? Offset.zero
        : _clampWindowDragDelta(_windowDragDelta, screenSize, windowSize);
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final backdropColor =
            (widget.clearBackdropInWindowedMode && !isFullscreen)
                ? Colors.transparent
                : config.themeColors.primaryDark
                    .withOpacity(0.5 * _backdropAnimation.value);
        return GestureDetector(
          onTap: _handleClose,
          onSecondaryTap: _handleClose,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: backdropColor,
            ),
            child: GestureDetector(
              onTap: () {},
              onSecondaryTap: _handleClose,
              child: Center(
                // windowed 模式允许在页面内拖动菜单窗口
                child: Transform.translate(
                  offset: clampedWindowDelta,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Transform.scale(
                        scale: _scaleAnimation.value,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Container(
                            width: windowWidth,
                            height: windowHeight,
                            decoration: isFullscreen
                                ? null
                                : BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        config.baseWindowBorder),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(
                                            0.3 * _fadeAnimation.value),
                                        blurRadius: 20 * uiScale,
                                        offset: Offset(0, 8 * uiScale),
                                      ),
                                    ],
                                  ),
                            child: ClipRRect(
                              borderRadius: isFullscreen
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(
                                      config.baseWindowBorder),
                              child: Stack(
                                children: [
                                  // 底层：纯色背景
                                  Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    color: config.themeColors.background,
                                  ),
                                  // 中层：背景图片
                                  if (config.baseWindowBackground != null &&
                                      config.baseWindowBackground!.isNotEmpty)
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity:
                                            config.baseWindowBackgroundAlpha,
                                        child: ColorFiltered(
                                          colorFilter: SvgColorFilterUtils
                                              .getSvgColorTemperatureFilter(
                                                  config),
                                          child: Align(
                                            alignment: Alignment(
                                              (config.baseWindowXAlign - 0.5) *
                                                  2,
                                              (config.baseWindowYAlign - 0.5) *
                                                  2,
                                            ),
                                            child: Transform.scale(
                                              scale: config
                                                  .baseWindowBackgroundScale,
                                              child: SmartAssetImage(
                                                assetName: config
                                                    .baseWindowBackground!,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // 上层：可选半透明控件层
                                  Container(
                                    color: widget.disableWindowTintOverlay
                                        ? Colors.transparent
                                        : config.themeColors.background
                                            .withOpacity(
                                                config.baseWindowAlpha),
                                    child: Column(
                                      children: [
                                        if (widget.showHeader)
                                          _buildHeader(
                                              uiScale, textScale, config),
                                        Expanded(child: widget.content),
                                        if (widget.footer != null)
                                          widget.footer!,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.enableWindowDragInWindowedMode &&
                          !isFullscreen)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: widget.windowedDragHandleHeight * uiScale,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.move,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: _onWindowDragStart,
                              onPanUpdate: (details) {
                                _onWindowDragUpdate(
                                  details,
                                  screenSize: screenSize,
                                  windowSize: windowSize,
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      double uiScale, double textScale, SakiEngineConfig config) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 32 * uiScale,
        vertical: 20 * uiScale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.primary.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            widget.title,
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale,
              color: config.themeColors.primary,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          CommonCloseButton(
            scale: uiScale,
            onClose: _handleClose,
          ),
        ],
      ),
    );
  }
}
