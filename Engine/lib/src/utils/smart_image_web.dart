import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// Web平台的图像文件加载实现 - 总是使用asset方式

Widget buildImageFile(
  String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  final filterQuality = ImageSamplingManager().resolveWidgetFilterQuality(
    defaultQuality: FilterQuality.high,
  );
  return Image.asset(
    assetPath,
    fit: fit ?? BoxFit.contain,
    width: width,
    height: height,
    filterQuality: filterQuality,
    errorBuilder: errorWidget != null
        ? (context, error, stackTrace) => errorWidget!
        : null,
  );
}

Widget buildAvifFile(
  String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  final filterQuality = ImageSamplingManager().resolveWidgetFilterQuality(
    defaultQuality: FilterQuality.high,
  );
  return AvifImage.asset(
    assetPath,
    fit: fit ?? BoxFit.contain,
    isAntiAlias: true,
    filterQuality: filterQuality,
    errorBuilder: errorWidget != null
        ? (context, error, stackTrace) => errorWidget!
        : null,
  );
}

Future<bool> checkFileExists(String assetPath) async {
  // Web平台不检查文件系统，总是返回false
  return false;
}
