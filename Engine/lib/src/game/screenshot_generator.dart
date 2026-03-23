import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/rendering/game_renderer.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/config/config_models.dart';

/// 游戏截图生成器
/// 根据当前游戏状态生成16:9的假截图，包含背景和角色，但不显示对话框
class ScreenshotGenerator {
  static const double targetWidth = 640.0;
  static const double targetHeight = 360.0;  // 16:9 比例
  
  /// 生成当前游戏状态的截图数据
  /// 返回WebP格式的截图字节数据，如果失败返回null
  static Future<Uint8List?> generateScreenshotData(
    GameState gameState, 
    Map<String, PoseConfig> poseConfigs,
  ) async {
    try {
      // 创建画布
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, targetWidth, targetHeight));
      const canvasSize = Size(targetWidth, targetHeight);
      
      // 使用统一的渲染器绘制背景
      await GameRenderer.drawBackground(canvas, gameState.background, canvasSize);
      
      // 如果有CG角色，优先渲染CG角色（铺满屏幕，类似背景）
      if (gameState.cgCharacters.isNotEmpty) {
        await GameRenderer.drawCgCharacters(canvas, gameState.cgCharacters, poseConfigs, canvasSize);
      } else {
        // 没有CG时才绘制普通角色
        await GameRenderer.drawCharacters(canvas, gameState.characters, poseConfigs, canvasSize);
      }
      
      // 完成绘制
      final picture = recorder.endRecording();
      final image = await picture.toImage(targetWidth.toInt(), targetHeight.toInt());
      
      // 尝试使用WebP格式，如果不支持则使用PNG
      ui.ImageByteFormat format;
      try {
        // 先尝试WebP格式
        final webpData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (webpData != null) {
          // Flutter的ImageByteFormat没有直接的WebP支持，我们使用PNG
          // PNG提供了较好的压缩率，虽然不如WebP，但兼容性更好
          format = ui.ImageByteFormat.png;
        } else {
          format = ui.ImageByteFormat.png;
        }
      } catch (e) {
        format = ui.ImageByteFormat.png;
      }
      
      final byteData = await image.toByteData(format: format);
      if (byteData == null) return null;
      
      return byteData.buffer.asUint8List();
    } catch (e) {
      print('生成截图失败: $e');
      return null;
    }
  }
}