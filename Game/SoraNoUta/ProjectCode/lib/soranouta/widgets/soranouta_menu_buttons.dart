import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/widgets/common/configurable_menu_button.dart';
import 'soranouta_text_button.dart';
import 'animated_roller_blind.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'dart:ui' as ui;

class SoranoutaMenuButtons {
  static const double buttonSpacing = 10;

  /// 判断是否应该显示退出按钮
  /// Web端和移动端不显示退出按钮
  static bool _shouldShowExitButton() {
    if (kIsWeb) return false; // Web端不显示
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) return false; // 移动端不显示
    return true; // 桌面端显示
  }

  static Widget createButtonsWidget({
    required VoidCallback onNewGame,
    VoidCallback? onContinueGame, // 新增：继续游戏回调（可选）
    required VoidCallback onLoadGame,
    required VoidCallback onSettings,
    required VoidCallback onExit,
    required SakiEngineConfig config,
    required double scale,
    required Size screenSize,
    bool startAnimation = true, // 控制动画开始
  }) {
    final isDarkMode = SettingsManager().currentDarkMode;
    final lineColor = isDarkMode ? Colors.black : Colors.white;
    final localization = LocalizationManager();

    final List<Widget> buttons = [];

    // 如果有快速存档，添加"继续游戏"按钮
    if (onContinueGame != null) {
      buttons.add(
        SoranoutaTextButton(
          text: localization.t('menu.continue'),
          onPressed: onContinueGame,
          scale: scale,
        ),
      );
    }

    buttons.addAll([
      SoranoutaTextButton(
        text: localization.t('menu.newGame'),
        onPressed: onNewGame,
        scale: scale,
      ),
      SoranoutaTextButton(
        text: localization.t('menu.loadGame'),
        onPressed: onLoadGame,
        scale: scale,
      ),
      SoranoutaTextButton(
        text: localization.t('menu.settings'),
        onPressed: onSettings,
        scale: scale,
      ),
    ]);

    if (_shouldShowExitButton()) {
      buttons.add(
        SoranoutaTextButton(
          text: localization.t('menu.exit'),
          onPressed: onExit,
          scale: scale,
        ),
      );
    }

    final List<Widget> widgetsWithSeparators = [];
    for (int i = 0; i < buttons.length; i++) {
      // 为每个按钮包装动画，使用索引错开时机
      widgetsWithSeparators.add(
        AnimatedRollerBlind(
          startAnimation: startAnimation,
          index: i, // 传入索引，用于错开动画
          child: buttons[i],
        ),
      );
      if (i < buttons.length - 1) {
        // 分割线也添加动画，与对应按钮同步
        widgetsWithSeparators.add(
          AnimatedRollerBlind(
            startAnimation: startAnimation,
            index: i, // 与按钮使用相同索引
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 200 * scale,
                height: 2 * scale,
                color: lineColor,
                margin: EdgeInsets.only(right: 0),
              ),
            ),
          ),
        );
      }
    }

    return Positioned(
      top: screenSize.height * 0.08,
      right: screenSize.width * 0.04,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: widgetsWithSeparators,
          ),
          // 竖线也添加动画（直接在这里放置，不用Positioned）
          Positioned(
            top: 20 * scale,
            right: 0,
            child: AnimatedRollerBlind(
              startAnimation: startAnimation,
              index: 0, // 竖线最先出现
              child: Container(
                width: 3 * scale,
                height: (buttons.length * 80 + (buttons.length - 1) * 20) * scale,
                color: lineColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget createShadowWidget({
    required SakiEngineConfig config,
    required double scale,
    required Size screenSize,
    VoidCallback? onContinueGame, // 新增：继续游戏回调（可选）
    bool startAnimation = true, // 控制动画开始
  }) {
    final localization = LocalizationManager();
    final List<String> buttonTexts = [];

    // 如果有快速存档，添加"继续游戏"按钮文本
    if (onContinueGame != null) {
      buttonTexts.add(localization.t('menu.continue'));
    }

    buttonTexts.addAll([
      localization.t('menu.newGame'),
      localization.t('menu.loadGame'),
      localization.t('menu.settings'),
      if (_shouldShowExitButton()) localization.t('menu.exit'),
    ]);
    final isDarkMode = SettingsManager().currentDarkMode;
    final shadowColor = isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.9);

    final shadowContent = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: Stack(
        children: [
          // 阴影按钮文字和横线
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < buttonTexts.length; i++) ...[
                Container(
                  margin: EdgeInsets.only(right: 20 * scale),
                  child: Text(
                    buttonTexts[i],
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'ChillJinshuSongPro_Soft',
                      fontSize: 55 * scale,
                      color: shadowColor,
                      fontWeight: FontWeight.normal,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                if (i < buttonTexts.length - 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 200 * scale,
                      height: 2 * scale,
                      color: shadowColor,
                      margin: EdgeInsets.only(right: 0),
                    ),
                  ),
              ],
            ],
          ),
          // 阴影竖线
          Positioned(
            top: 20 * scale,
            right: 0,
            child: Container(
              width: 3 * scale,
              height: (buttonTexts.length * 80 + (buttonTexts.length - 1) * 20) * scale,
              color: shadowColor,
            ),
          ),
        ],
      ),
    );

    return Positioned(
      top: screenSize.height * 0.08,
      right: screenSize.width * 0.04,
      child: _AnimatedFadeIn(
        startAnimation: startAnimation,
        child: shadowContent,
      ),
    );
  }

  static List<MenuButtonConfig> createConfigs({
    required VoidCallback onNewGame,
    required VoidCallback onLoadGame,
    required VoidCallback onSettings,
    required VoidCallback onExit,
    required SakiEngineConfig config,
    required double scale,
  }) {
    return [];
  }

  static MenuButtonsLayoutConfig getLayoutConfig() {
    return const MenuButtonsLayoutConfig(
      isVertical: true,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.start,
      spacing: buttonSpacing,
      top: 0.08,
      right: 0.05,
    );
  }
}

/// 淡入动画包装器
/// 与卷帘动画同步的透明度淡入效果
class _AnimatedFadeIn extends StatefulWidget {
  final Widget child;
  final bool startAnimation;

  const _AnimatedFadeIn({
    required this.child,
    required this.startAnimation,
  });

  @override
  State<_AnimatedFadeIn> createState() => _AnimatedFadeInState();
}

class _AnimatedFadeInState extends State<_AnimatedFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800), // 与卷帘动画同步
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // 与卷帘动画同步
    );

    if (widget.startAnimation) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.startAnimation && widget.startAnimation) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}
