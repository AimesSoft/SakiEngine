import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/svg_color_filter_utils.dart';

/// 对话框背景容器组件
/// 
/// 负责渲染对话框的背景、边框和阴影效果
class DialogueBackground extends StatelessWidget {
  final Widget child;
  final bool isHovered;
  final double dialogOpacity;
  final double uiScale;
  final Widget? overlay; // 新增：覆盖层组件（如已读标记）

  const DialogueBackground({
    super.key,
    required this.child,
    required this.isHovered,
    required this.dialogOpacity,
    required this.uiScale,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final config = SakiEngineConfig();

    return Container(
      width: screenSize.width * 0.85,
      height: screenSize.height * 0.25,
      margin: EdgeInsets.all(16.0 * uiScale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(config.baseWindowBorder > 0 
            ? config.baseWindowBorder * uiScale 
            : 0 * uiScale),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(isHovered ? 0.4 : 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12 * uiScale,
            offset: Offset(0, 4 * uiScale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(config.baseWindowBorder > 0 
            ? config.baseWindowBorder * uiScale 
            : 0 * uiScale),
        child: Stack(
          children: [
            // 底层：纯色背景
            Container(
              width: double.infinity,
              height: double.infinity,
              color: config.themeColors.background.withOpacity(dialogOpacity),
            ),
            // 中层：背景图片
            if (config.baseWindowBackground != null && config.baseWindowBackground!.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: config.baseWindowBackgroundAlpha * dialogOpacity,
                  child: ColorFiltered(
                    colorFilter: SvgColorFilterUtils.getSvgColorTemperatureFilter(config),
                    child: FittedBox(
                      fit: BoxFit.none,
                      alignment: Alignment(
                        (config.dialogueBackgroundXAlign - 0.5) * 2,
                        (config.dialogueBackgroundYAlign - 0.5) * 2,
                      ),
                      child: Transform.scale(
                        scale: config.dialogueBackgroundScale,
                        child: SmartAssetImage(
                          assetName: config.baseWindowBackground!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 上层：半透明控件
            Container(
              color: config.themeColors.background.withOpacity(config.baseWindowAlpha * 0.3),
              child: child,
            ),
            // 覆盖层：已读标记等
            if (overlay != null) overlay!,
          ],
        ),
      ),
    );
  }
}