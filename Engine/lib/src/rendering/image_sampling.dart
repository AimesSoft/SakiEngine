import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 引擎图像采样管理器。
///
/// 默认保持高质量缩放；当项目通过 runSakiEngine 显式开启后，
/// 图像渲染会统一走最近邻采样（FilterQuality.none）。
class ImageSamplingManager {
  static final ImageSamplingManager _instance =
      ImageSamplingManager._internal();

  factory ImageSamplingManager() => _instance;

  ImageSamplingManager._internal();

  bool _useNearestNeighbor = false;

  bool get useNearestNeighbor => _useNearestNeighbor;

  void configure({required bool useNearestNeighbor}) {
    _useNearestNeighbor = useNearestNeighbor;
  }

  FilterQuality resolveWidgetFilterQuality({
    FilterQuality defaultQuality = FilterQuality.high,
  }) {
    if (_useNearestNeighbor) {
      return FilterQuality.none;
    }
    return defaultQuality;
  }

  ui.FilterQuality resolveCanvasFilterQuality({
    ui.FilterQuality defaultQuality = ui.FilterQuality.high,
  }) {
    if (_useNearestNeighbor) {
      return ui.FilterQuality.none;
    }
    return defaultQuality;
  }

  ui.FilterQuality resolveCanvasFilterQualityBySpeed({
    required bool preferSpeed,
  }) {
    return resolveCanvasFilterQuality(
      defaultQuality:
          preferSpeed ? ui.FilterQuality.low : ui.FilterQuality.high,
    );
  }
}
