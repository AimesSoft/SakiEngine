import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/widgets/common/configurable_menu_button.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class DefaultMenuButtons {
  static List<MenuButtonConfig> createDefaultConfigs({
    required VoidCallback onNewGame,
    VoidCallback? onContinueGame, // 新增：继续游戏回调（可选）
    required VoidCallback onLoadGame,
    required VoidCallback onSettings,
    required VoidCallback onAbout,
    required VoidCallback onExit,
    required SakiEngineConfig config,
    required double scale,
  }) {
    final localization = LocalizationManager();

    final buttons = <MenuButtonConfig>[];

    // 如果有快速存档，显示"继续游戏"按钮
    if (onContinueGame != null) {
      buttons.add(
        MenuButtonConfig(
          text: localization.t('menu.continue'),
          onPressed: onContinueGame,
          backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
          textColor: config.themeColors.primary,
          hoverColor: HSLColor.fromColor(config.themeColors.background)
              .withLightness(
                  (HSLColor.fromColor(config.themeColors.background).lightness -
                          0.1)
                      .clamp(0.0, 1.0))
              .toColor()
              .withValues(alpha: 0.9),
          border: Border.all(
            color: config.themeColors.primary.withValues(alpha: 0.5),
            width: 1,
          ),
          textStyle: TextStyle(
            fontFamily: 'SourceHanSansCN',
            fontSize: 28 * scale,
            color: config.themeColors.primary,
            letterSpacing: 2,
          ),
        ),
      );
    }

    buttons.add(
      MenuButtonConfig(
        text: localization.t('menu.newGame'),
        onPressed: onNewGame,
        backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
        textColor: config.themeColors.primary,
        hoverColor: HSLColor.fromColor(config.themeColors.background)
            .withLightness(
                (HSLColor.fromColor(config.themeColors.background).lightness -
                        0.1)
                    .clamp(0.0, 1.0))
            .toColor()
            .withValues(alpha: 0.9),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.5),
          width: 1,
        ),
        textStyle: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: 28 * scale,
          color: config.themeColors.primary,
          letterSpacing: 2,
        ),
      ),
    );

    buttons.add(
      MenuButtonConfig(
        text: localization.t('menu.loadGame'),
        onPressed: onLoadGame,
        backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
        textColor: config.themeColors.primary,
        hoverColor: HSLColor.fromColor(config.themeColors.background)
            .withLightness(
                (HSLColor.fromColor(config.themeColors.background).lightness -
                        0.1)
                    .clamp(0.0, 1.0))
            .toColor()
            .withValues(alpha: 0.9),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.5),
          width: 1,
        ),
        textStyle: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: 28 * scale,
          color: config.themeColors.primary,
          letterSpacing: 2,
        ),
      ),
    );

    buttons.add(
      MenuButtonConfig(
        text: localization.t('menu.settings'),
        onPressed: onSettings,
        backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
        textColor: config.themeColors.primary,
        hoverColor: HSLColor.fromColor(config.themeColors.background)
            .withLightness(
                (HSLColor.fromColor(config.themeColors.background).lightness -
                        0.1)
                    .clamp(0.0, 1.0))
            .toColor()
            .withValues(alpha: 0.9),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.5),
          width: 1,
        ),
        textStyle: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: 28 * scale,
          color: config.themeColors.primary,
          letterSpacing: 2,
        ),
      ),
    );

    buttons.add(
      MenuButtonConfig(
        text: localization.t('menu.about'),
        onPressed: onAbout,
        backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
        textColor: config.themeColors.primary,
        hoverColor: HSLColor.fromColor(config.themeColors.background)
            .withLightness(
                (HSLColor.fromColor(config.themeColors.background).lightness -
                        0.1)
                    .clamp(0.0, 1.0))
            .toColor()
            .withValues(alpha: 0.9),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.5),
          width: 1,
        ),
        textStyle: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: 28 * scale,
          color: config.themeColors.primary,
          letterSpacing: 2,
        ),
      ),
    );

    if (!kIsWeb) {
      buttons.add(
        MenuButtonConfig(
          text: localization.t('menu.exitGame'),
          onPressed: onExit,
          backgroundColor: config.themeColors.background.withValues(alpha: 0.9),
          textColor: config.themeColors.primary,
          hoverColor: HSLColor.fromColor(config.themeColors.background)
              .withLightness(
                  (HSLColor.fromColor(config.themeColors.background).lightness -
                          0.1)
                      .clamp(0.0, 1.0))
              .toColor()
              .withValues(alpha: 0.9),
          border: Border.all(
            color: config.themeColors.primary.withValues(alpha: 0.5),
            width: 1,
          ),
          textStyle: TextStyle(
            fontFamily: 'SourceHanSansCN',
            fontSize: 28 * scale,
            color: config.themeColors.primary,
            letterSpacing: 2,
          ),
        ),
      );
    }

    return buttons;
  }
}
