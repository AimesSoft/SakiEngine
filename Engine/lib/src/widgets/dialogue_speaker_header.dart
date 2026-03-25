import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

/// 对话框标题栏组件
/// 
/// 显示说话者的名称
class DialogueSpeakerHeader extends StatelessWidget {
  final String? speaker;
  final double uiScale;
  final double textScale;

  const DialogueSpeakerHeader({
    super.key,
    required this.speaker,
    required this.uiScale,
    required this.textScale,
  });

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16 * uiScale,
        vertical: 12 * uiScale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Text(
        speaker ?? '',
        style: config.speakerTextStyle.copyWith(
          fontSize: config.speakerTextStyle.fontSize! * textScale,
          color: config.themeColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}