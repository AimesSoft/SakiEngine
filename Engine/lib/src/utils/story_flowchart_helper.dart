import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/screens/story_flowchart_screen.dart';
import 'package:sakiengine/src/game/story_flowchart_analyzer.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';

/// 剧情流程图界面入口工具类
class StoryFlowchartHelper {
  /// 显示剧情流程图界面
  static Future<void> showFlowchart(
    BuildContext context, {
    Function(SaveSlot)? onLoadSave,
    bool analyzeScriptFirst = false,
  }) async {
    // 如果需要，先分析脚本
    if (analyzeScriptFirst) {
      final analyzer = StoryFlowchartAnalyzer();
      await analyzer.analyzeScript();
    }

    // 显示流程图界面
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StoryFlowchartScreen(
            onClose: () => Navigator.of(context).pop(),
            onLoadSave: onLoadSave,
          ),
        ),
      );
    }
  }

  /// 重置并重新分析脚本（用于开发调试）
  static Future<void> resetAndAnalyzeScript() async {
    final analyzer = StoryFlowchartAnalyzer();
    await analyzer.resetAndAnalyze();
  }
}
