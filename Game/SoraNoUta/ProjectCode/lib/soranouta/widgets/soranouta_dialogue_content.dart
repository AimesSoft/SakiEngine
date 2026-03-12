import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';
import 'package:sakiengine/src/widgets/dialogue_next_arrow.dart';
import 'package:sakiengine/src/utils/svg_color_filter_utils.dart';

/// 主对话框内容组件
class SoranoutaDialogueContent extends StatefulWidget {
  final String? speaker;
  final String? speakerAlias; // 新增：角色简写
  final String dialogue;
  final TextStyle dialogueStyle;
  final Size screenSize;
  final double uiScale;
  final double textScale;
  final bool isHovered;
  final bool isDialogueComplete;
  final double dialogOpacity;
  final VoidCallback onTap;
  final Function(bool) onHoverChanged;
  final dynamic config;
  final bool enableTypewriter;
  final dynamic typewriterController;
  final Animation<double> textFadeAnimation;
  final Animation<double> blinkAnimation;
  final Widget? readStatusOverlay;
  final bool isRead;
  final GlobalKey? dialogueKey;

  const SoranoutaDialogueContent({
    super.key,
    this.speaker,
    this.speakerAlias, // 新增：角色简写参数
    required this.dialogue,
    required this.dialogueStyle,
    required this.screenSize,
    required this.uiScale,
    required this.textScale,
    required this.isHovered,
    required this.isDialogueComplete,
    required this.dialogOpacity,
    required this.onTap,
    required this.onHoverChanged,
    required this.config,
    required this.enableTypewriter,
    required this.typewriterController,
    required this.textFadeAnimation,
    required this.blinkAnimation,
    this.readStatusOverlay,
    required this.isRead,
    this.dialogueKey,
  });

  @override
  State<SoranoutaDialogueContent> createState() => _SoranoutaDialogueContentState();
}

class _SoranoutaDialogueContentState extends State<SoranoutaDialogueContent> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MouseRegion(
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) => widget.onHoverChanged(false),
          child: Container(
            key: widget.dialogueKey, // 重新添加key来获取位置
            width: widget.screenSize.width * 0.85,
            height: widget.screenSize.height * 0.35 / 1.5,
            margin: EdgeInsets.all(16.0 * widget.uiScale),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                widget.config.baseWindowBorder > 0
                    ? widget.config.baseWindowBorder * widget.uiScale
                    : 0 * widget.uiScale,
              ),
              border: Border.all(
                color: widget.config.themeColors.primary
                    .withValues(alpha: widget.isHovered ? 0.4 : 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12 * widget.uiScale,
                  offset: Offset(0, 4 * widget.uiScale),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                widget.config.baseWindowBorder > 0
                    ? widget.config.baseWindowBorder * widget.uiScale
                    : 0 * widget.uiScale,
              ),
              child: Stack(
                children: [
                  // 底层：纯色背景
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: widget.config.themeColors.background
                        .withValues(alpha: widget.dialogOpacity),
                  ),
                  // 中层：背景图片
                  if (widget.config.baseWindowBackground != null &&
                      widget.config.baseWindowBackground!.isNotEmpty)
                    Positioned.fill(
                      child: Opacity(
                        opacity: widget.config.baseWindowBackgroundAlpha *
                            widget.dialogOpacity,
                        child: ColorFiltered(
                          colorFilter: SvgColorFilterUtils.getSvgColorTemperatureFilter(widget.config),
                          child: FittedBox(
                            fit: BoxFit.none,
                            alignment: Alignment(
                              (widget.config.dialogueBackgroundXAlign - 0.5) * 2,
                              (widget.config.dialogueBackgroundYAlign - 0.5) * 2,
                            ),
                            child: Transform.scale(
                              scale: widget.config.dialogueBackgroundScale,
                              child: SmartAssetImage(
                                assetName: widget.config.baseWindowBackground!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 上层：文本区域
                  _buildTextArea(),
                  // 覆盖层：已读状态指示器
                  if (widget.readStatusOverlay != null) widget.readStatusOverlay!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextArea() {
    return Padding(
      padding: EdgeInsets.only(
        left: 16.0 * widget.uiScale + widget.config.dialogueTextXPos,
        right: 100.0 * widget.uiScale,
        top: 16.0 * widget.uiScale + widget.config.dialogueTextYPos,
        bottom: 16.0 * widget.uiScale,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Opacity(
                  opacity: widget.isRead ? 0.7 : 1.0, // 已读文本透明度调整为0.7
                  child: FadeTransition(
                    opacity: widget.textFadeAnimation,
                    child: RichText(
                      text: TextSpan(
                        children: [
                          ...(widget.enableTypewriter
                              ? widget.typewriterController.getTextSpans(widget.dialogueStyle)
                              : RichTextParser.createTextSpans(widget.dialogue, widget.dialogueStyle)),
                          if (widget.isDialogueComplete)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: widget.uiScale),
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 7 * widget.uiScale),
                                  child: DialogueNextArrow(
                                    visible: widget.isDialogueComplete,
                                    fontSize: widget.dialogueStyle.fontSize!,
                                    color: SettingsManager().currentDarkMode
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : widget.config.themeColors.primary.withValues(alpha: 0.7),
                                    speaker: widget.speaker,
                                    speakerAlias: widget.speakerAlias, // 新增：传递角色简写
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
