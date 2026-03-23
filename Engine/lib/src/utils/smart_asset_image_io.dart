import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 非Web平台的SVG文件加载实现
Widget buildSvgFile(String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  return SvgPicture.file(
    File(assetPath),
    fit: fit ?? BoxFit.contain,
    width: width,
    height: height,
    colorFilter: null,
    allowDrawingOutsideViewBox: true,
    placeholderBuilder: errorWidget != null 
      ? (context) => errorWidget!
      : null,
  );
}