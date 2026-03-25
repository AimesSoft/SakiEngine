import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// 截图缩略图组件
/// 用于显示存档截图，带有加载状态和错误处理
class ScreenshotThumbnail extends StatelessWidget {
  final Uint8List? screenshotData;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? placeholderColor;
  final Color? iconColor;
  final double iconSize;

  const ScreenshotThumbnail({
    super.key,
    this.screenshotData,
    this.width,
    this.height,
    this.borderRadius = 4.0,
    this.placeholderColor,
    this.iconColor,
    this.iconSize = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (screenshotData == null || screenshotData!.isEmpty) {
      return _buildPlaceholder(Icons.image_outlined, '无截图');
    }

    return Image.memory(
      screenshotData!,
      fit: BoxFit.cover,
      filterQuality: ImageSamplingManager().resolveWidgetFilterQuality(
        defaultQuality: FilterQuality.high,
      ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;

        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: frame == null
              ? _buildPlaceholder(Icons.image_outlined, '加载中...')
              : child,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildPlaceholder(Icons.broken_image_outlined, '图片损坏');
      },
    );
  }

  Widget _buildPlaceholder(IconData icon, String text) {
    return Container(
      color: placeholderColor ?? Colors.grey.withValues(alpha: 0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: iconColor ?? Colors.grey.withValues(alpha: 0.5),
          ),
          if (iconSize > 16) ...[
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: iconSize * 0.5,
                color: iconColor ?? Colors.grey.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
