import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/game_style_dropdown.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class GameplaySettingsTab extends StatelessWidget {
  final String mouseRollbackBehavior;
  final String fastForwardMode;
  final Function(String) onMouseRollbackBehaviorChanged;
  final Function(String) onFastForwardModeChanged;

  const GameplaySettingsTab({
    super.key,
    required this.mouseRollbackBehavior,
    required this.fastForwardMode,
    required this.onMouseRollbackBehaviorChanged,
    required this.onFastForwardModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMouseRollbackBehaviorSelector(config, scale, context),
            SizedBox(height: 40 * scale),
            _buildFastForwardModeDropdown(config, scale, context),
            SizedBox(height: 40 * scale),
          ],
        ),
      ),
    );
  }

  Widget _buildMouseRollbackBehaviorSelector(SakiEngineConfig config, double scale, BuildContext context) {
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    final items = [
      GameStyleDropdownItem<String>(
        value: 'rewind',
        label: localization.t('settings.mouseRollback.option.rewind'),
        icon: Icons.undo,
      ),
      GameStyleDropdownItem<String>(
        value: 'history',
        label: localization.t('settings.mouseRollback.option.history'),
        icon: Icons.menu_book,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.5),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            mouseRollbackBehavior == 'history' ? Icons.menu_book : Icons.undo,
            color: config.themeColors.primary,
            size: 24 * scale,
          ),
          SizedBox(width: 16 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.t('settings.mouseRollback.title'),
                  style: config.reviewTitleTextStyle.copyWith(
                    fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                    color: config.themeColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  localization.t('settings.mouseRollback.description'),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                    color: config.themeColors.primary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 16 * scale),
          GameStyleDropdown<String>(
            items: items,
            value: mouseRollbackBehavior,
            onChanged: onMouseRollbackBehaviorChanged,
            scale: scale,
            textScale: textScale,
            config: config,
            width: 220 * scale,
          ),
        ],
      ),
    );
  }

  Widget _buildFastForwardModeDropdown(SakiEngineConfig config, double scale, BuildContext context) {
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    final items = [
      GameStyleDropdownItem<String>(
        value: 'read_only',
        label: localization.t('settings.fastForward.read'),
        icon: Icons.skip_next,
      ),
      GameStyleDropdownItem<String>(
        value: 'force',
        label: localization.t('settings.fastForward.force'),
        icon: Icons.fast_forward,
      ),
    ];

    final descriptionKey =
        fastForwardMode == 'force'
            ? 'settings.fastForward.descriptionForce'
            : 'settings.fastForward.descriptionRead';

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.5),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fastForwardMode == 'force' ? Icons.fast_forward : Icons.skip_next,
            color: config.themeColors.primary,
            size: 24 * scale,
          ),
          SizedBox(width: 16 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.t('settings.fastForward.title'),
                  style: config.reviewTitleTextStyle.copyWith(
                    fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                    color: config.themeColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  localization.t(descriptionKey),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                    color: config.themeColors.primary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 16 * scale),
          GameStyleDropdown<String>(
            items: items,
            value: fastForwardMode,
            onChanged: onFastForwardModeChanged,
            scale: scale,
            textScale: textScale,
            config: config,
            width: 200 * scale,
          ),
        ],
      ),
    );
  }
}
