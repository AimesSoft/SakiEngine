import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Web平台的SVG文件加载实现 - 总是使用asset方式
Widget buildSvgFile(String assetPath, {
  BoxFit? fit,
  double? width,
  double? height,
  Widget? errorWidget,
}) {
  return SvgPicture.asset(
    assetPath,
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