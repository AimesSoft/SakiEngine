import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter_avif/flutter_avif.dart';

/// 非Web平台的图像文件加载实现

Widget buildImageFile(String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  return Image.file(
    File(assetPath),
    fit: fit ?? BoxFit.contain,
    width: width,
    height: height,
    errorBuilder: errorWidget != null 
      ? (context, error, stackTrace) => errorWidget!
      : null,
  );
}

Widget buildAvifFile(String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  return AvifImage.file(
    File(assetPath),
    fit: fit ?? BoxFit.contain,
    isAntiAlias: true,
    filterQuality: FilterQuality.high,
    errorBuilder: errorWidget != null 
      ? (context, error, stackTrace) => errorWidget!
      : null,
  );
}

Future<bool> checkFileExists(String assetPath) async {
  return await File(assetPath).exists();
}