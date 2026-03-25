import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/typewriter_animation_manager.dart';
import 'package:sakiengine/src/widgets/dialogue_next_arrow.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';

/// 对话框内容区域组件
/// 
/// 显示对话文本和下一页箭头
class DialogueContent extends StatelessWidget {
  final String dialogue;
  final String? speaker;
  final String? speakerAlias; // 新增：角色简写
  final TextStyle dialogueStyle;
  final TypewriterAnimationManager typewriterController;
  final Animation<double> textFadeAnimation;
  final bool enableTypewriter;
  final bool isDialogueComplete;
  final double uiScale;
  final bool isRead;

  const DialogueContent({
    super.key,
    required this.dialogue,
    required this.speaker,
    this.speakerAlias, // 新增：角色简写参数
    required this.dialogueStyle,
    required this.typewriterController,
    required this.textFadeAnimation,
    required this.enableTypewriter,
    required this.isDialogueComplete,
    required this.uiScale,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();

    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0 * uiScale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Opacity(
                opacity: isRead ? 0.7 : 1.0, // 已读文本透明度调整为0.7
                child: FadeTransition(
                  opacity: textFadeAnimation,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        ...(enableTypewriter 
                          ? typewriterController.getTextSpans(dialogueStyle)
                          : RichTextParser.createTextSpans(dialogue, dialogueStyle)),
                        if (isDialogueComplete)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(left: uiScale),
                              child: DialogueNextArrow(
                                visible: isDialogueComplete,
                                fontSize: dialogueStyle.fontSize!,
                              color: config.themeColors.primary.withOpacity(0.7),
                              speaker: speaker,
                              speakerAlias: speakerAlias, // 新增：传递角色简写
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
        ),
      ),
    );
  }
}