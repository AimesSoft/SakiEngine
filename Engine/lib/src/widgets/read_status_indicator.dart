import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

/// 已读状态指示器
/// 
/// 显示一个小的"已读"标记，相对定位在容器的左上角
class ReadStatusIndicator extends StatelessWidget {
  final bool isRead;
  final double uiScale;
  final double textScale;
  final bool positioned; // 新增：是否自动定位

  const ReadStatusIndicator({
    super.key,
    required this.isRead,
    required this.uiScale,
    required this.textScale,
    this.positioned = true, // 默认自动定位
  });

  @override
  Widget build(BuildContext context) {
    if (!isRead) {
      return const SizedBox.shrink();
    }

    final config = SakiEngineConfig();
    
    final indicator = Transform.rotate(
      angle: 0, 
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 18.0 * uiScale,
          vertical: 4.0 * uiScale,
        ),
        decoration: BoxDecoration(
          color: config.themeColors.onSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              offset: Offset(2.0 * uiScale, 2.0 * uiScale), // 右下偏移
              blurRadius: 4.0 * uiScale,
            ),
          ],
        ),
        child: Text(
          '已读',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: config.themeColors.surface,
            fontSize: 14.0 * textScale,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );

    if (positioned) {
      return Positioned(
        // 相对于Stack容器的左上角定位
        top: 0.0 * uiScale,
        left: 0 * uiScale,
        child: indicator,
      );
    } else {
      return indicator;
    }
  }
}
