import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'dart:convert';

/// 二进制已读指示器
/// 将角色名称转换为二进制格式，然后用符号表示
/// 1 -> -    0 -> \
class BinaryReadIndicator extends StatelessWidget {
  final String? speaker;
  final String? speakerAlias; // 新增：角色简写
  final double uiScale;
  final double textScale;
  final bool positioned;

  const BinaryReadIndicator({
    super.key,
    required this.speaker,
    this.speakerAlias, // 新增：可选的角色简写参数
    required this.uiScale,
    required this.textScale,
    this.positioned = true,
  });

  /// 将字符串转换为二进制符号表示
  String _convertToBinarySymbols(String text) {
    final bytes = utf8.encode(text);
    final binaryString =
        bytes.map((byte) => byte.toRadixString(2).padLeft(8, '0')).join();

    return binaryString.replaceAll('1', '-').replaceAll('0', r'\');
  }

  /// 根据说话人简称确定显示内容
  String _getDisplayText() {
    // 直接使用传入的简写，如果没有则默认为ai
    final alias = speakerAlias ?? 'unknown';    // 特殊处理：旁白角色不显示
    if (alias == 'nr' || alias == 'n' || alias == 'unknown') {
      return _convertToBinarySymbols('system');
    }

    // l (林澄) 显示 admin 转换后的符号
    if (alias == 'ls' || alias == 'x2') {
      return _convertToBinarySymbols('admin');
    }
    if (alias == 'l') {
      return _convertToBinarySymbols('error');
    }
    // 其他说话人显示 ai 转换后的符号
    return _convertToBinarySymbols('ai');
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _getDisplayText();

    if (displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    final config = SakiEngineConfig();

    final indicator = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6.0 * uiScale,
        vertical: 2.0 * uiScale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.onSurface.withAlpha(0),
        borderRadius: BorderRadius.circular(2.0 * uiScale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.0),
            offset: Offset(1.0 * uiScale, 1.0 * uiScale),
            blurRadius: 2.0 * uiScale,
          ),
        ],
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 24.0 * textScale,
          color: config.themeColors.onSurface.withOpacity(0.3),
          fontFamily: 'monospace',
          letterSpacing: -0.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (positioned) {
      return Positioned(
        bottom: 20.0 * uiScale,
        left: 150.0 * uiScale,
        child: indicator,
      );
    } else {
      return indicator;
    }
  }
}
