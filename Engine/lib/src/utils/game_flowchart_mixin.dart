import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/story_flowchart_helper.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';

/// 游戏内流程图功能扩展
/// 为GamePlayScreen提供流程图功能
mixin GameFlowchartMixin {
  /// 显示流程图界面
  ///
  /// [context] BuildContext
  /// [gameManager] 游戏管理器实例
  /// [onLoadGame] 加载游戏回调
  Future<void> showGameFlowchart(
    BuildContext context,
    GameManager gameManager,
    Function(SaveSlot)? onLoadGame,
  ) async {
    await StoryFlowchartHelper.showFlowchart(
      context,
      analyzeScriptFirst: false, // 游戏内不需要重新分析
      onLoadSave: (saveSlot) {
        // 加载存档
        onLoadGame?.call(saveSlot);
      },
    );
  }
}
