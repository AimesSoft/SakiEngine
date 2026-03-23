import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

/// 颜色背景渲染器
/// 专门处理十六进制颜色背景的绘制逻辑
class ColorBackgroundRenderer {
  
  /// 验证是否为有效的十六进制颜色格式
  /// 支持格式: #RGB, #RRGGBB, #RRGGBBAA
  static bool isValidHexColor(String color) {
    if (!color.startsWith('#')) return false;
    
    final hex = color.substring(1);
    return RegExp(r'^([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(hex);
  }
  
  /// 将十六进制颜色字符串转换为Color对象
  /// 支持格式: #RGB, #RRGGBB, #RRGGBBAA
  static Color hexToColor(String hexColor) {
    if (!isValidHexColor(hexColor)) {
      throw ArgumentError('Invalid hex color format: $hexColor');
    }
    
    String hex = hexColor.substring(1); // 移除 # 符号
    
    // 处理 #RGB 格式 -> #RRGGBB
    if (hex.length == 3) {
      hex = hex.split('').map((char) => char + char).join('');
    }
    
    // 处理 #RRGGBB 格式 -> #AARRGGBB (添加不透明度)
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    
    // 现在 hex 应该是 8 位格式 (AARRGGBB)
    if (hex.length != 8) {
      throw ArgumentError('Invalid hex color format after processing: #$hex');
    }
    
    final value = int.parse(hex, radix: 16);
    return Color(value);
  }
  
  /// 在Canvas上绘制纯色背景（支持动画）
  static void drawColorBackground(
    Canvas canvas,
    String hexColor,
    Size canvasSize, {
    Map<String, double>? animationProperties,
  }) {
    try {
      final color = hexToColor(hexColor);
      
      // 应用动画属性
      if (animationProperties != null && animationProperties.isNotEmpty) {
        canvas.save();
        
        // 计算变换中心点
        final centerX = canvasSize.width / 2;
        final centerY = canvasSize.height / 2;
        
        // 应用平移
        final xOffset = (animationProperties['xcenter'] ?? 0.0) * canvasSize.width;
        final yOffset = (animationProperties['ycenter'] ?? 0.0) * canvasSize.height;
        canvas.translate(centerX + xOffset, centerY + yOffset);
        
        // 应用旋转
        final rotation = animationProperties['rotation'] ?? 0.0;
        if (rotation != 0.0) {
          canvas.rotate(rotation);
        }
        
        // 应用缩放
        final scale = animationProperties['scale'] ?? 1.0;
        if (scale != 1.0) {
          canvas.scale(scale);
        }
        
        // 移回中心点
        canvas.translate(-centerX, -centerY);
        
        // 设置透明度
        final alpha = (animationProperties['alpha'] ?? 1.0).clamp(0.0, 1.0);
        final paint = Paint()..color = color.withOpacity(alpha);
        
        canvas.drawRect(
          Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
          paint,
        );
        
        canvas.restore();
      } else {
        // 无动画时使用原来的绘制方式
        final paint = Paint()..color = color;
        
        canvas.drawRect(
          Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
          paint,
        );
      }
    } catch (e) {
      print('绘制颜色背景失败: $e');
      // 回退到黑色背景
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
        Paint()..color = Colors.black,
      );
    }
  }
  
  /// 创建纯色背景的Widget
  static Widget createColorBackgroundWidget(String hexColor) {
    try {
      final color = hexToColor(hexColor);
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: color,
      );
    } catch (e) {
      print('创建颜色背景Widget失败: $e');
      // 回退到黑色背景
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
      );
    }
  }
}