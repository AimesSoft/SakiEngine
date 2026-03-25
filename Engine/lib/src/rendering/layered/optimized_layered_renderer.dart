/// 优化的层叠渲染器
///
/// 针对首次加载慢和快进卡顿进行专项优化
library optimized_layered_renderer;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/rendering/layered/layer_types.dart';
import 'package:sakiengine/src/rendering/layered/smart_layer_cache.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/image_loader.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// 超高性能层叠渲染器
///
/// 优化策略：
/// 1. 激进预加载 - 提前加载所有可能的CG组合
/// 2. 内存优先 - 宁可多用内存也要保证速度
/// 3. 异步优化 - 所有加载都在后台进行
/// 4. 智能预测 - 基于脚本预分析进行预加载
class OptimizedLayeredRenderer {
  static final OptimizedLayeredRenderer _instance =
      OptimizedLayeredRenderer._internal();
  factory OptimizedLayeredRenderer() => _instance;
  OptimizedLayeredRenderer._internal();

  /// 激进缓存 - 预加载所有资源
  final Map<String, ui.Image> _aggressiveCache = <String, ui.Image>{};

  /// 预合成缓存 - 对于经常使用的组合进行预合成
  final Map<String, ui.Image> _precompositeCache = <String, ui.Image>{};

  /// 正在加载的任务
  final Map<String, Future<ui.Image?>> _loadingTasks =
      <String, Future<ui.Image?>>{};

  /// 性能统计
  int _totalRequests = 0;
  int _cacheHits = 0;
  DateTime _lastStatsReset = DateTime.now();

  /// 激进预热 - 预加载项目中所有CG资源
  Future<void> aggressivePreload() async {
    if (kEngineDebugMode) {
      print('[OptimizedLayeredRenderer] 开始激进预热...');
    }

    try {
      // 获取所有CG资源
      final cgResources = await _discoverAllCgResources();

      // 分批加载，避免内存峰值过高
      const batchSize = 5;
      for (int i = 0; i < cgResources.length; i += batchSize) {
        final batch = cgResources.skip(i).take(batchSize);
        await _preloadBatch(batch.toList());

        // 小延迟避免UI阻塞
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (kEngineDebugMode) {
        print('[OptimizedLayeredRenderer] 预热完成，加载了${cgResources.length}个资源');
      }
    } catch (e) {
      if (kEngineDebugMode) {
        print('[OptimizedLayeredRenderer] 预热失败: $e');
      }
    }
  }

  /// 发现所有CG资源
  Future<List<String>> _discoverAllCgResources() async {
    final resources = <String>[];

    // 常见的CG资源模式
    final patterns = [
      'cg_cp0_1',
      'cg_cp0_2',
      'cg_cp0_3',
      'cg_cp1_1',
      'cg_cp1_2',
      'cg_cp1_3',
      'cg_cp1_4',
      'cg_cp1_5',
    ];

    final poses = ['pose1', 'pose2'];
    final expressions = ['1', '2', '3', '4', '5'];

    for (final pattern in patterns) {
      for (final pose in poses) {
        // 基础图层
        final basePath = '$pattern-$pose';
        if (await _resourceExists(basePath)) {
          resources.add(basePath);
        }

        // 表情差分
        for (final expr in expressions) {
          final exprPath = '$pattern-$expr';
          if (await _resourceExists(exprPath)) {
            resources.add(exprPath);
          }
        }
      }
    }

    return resources;
  }

  /// 检查资源是否存在
  Future<bool> _resourceExists(String assetName) async {
    try {
      final fullPath = await AssetManager().findAsset('characters/$assetName');
      return fullPath != null;
    } catch (e) {
      return false;
    }
  }

  /// 分批预加载
  Future<void> _preloadBatch(List<String> resources) async {
    final loadTasks = resources.map(_preloadSingleResource);
    await Future.wait(loadTasks, eagerError: false);
  }

  /// 预加载单个资源
  Future<void> _preloadSingleResource(String assetName) async {
    if (_aggressiveCache.containsKey(assetName)) {
      return; // 已经缓存
    }

    try {
      final fullPath = await AssetManager().findAsset('characters/$assetName');
      if (fullPath == null) return;

      final image = await ImageLoader.loadImage(fullPath);
      if (image != null) {
        _aggressiveCache[assetName] = image;
      }
    } catch (e) {
      // 静默失败
    }
  }

  /// 超快速获取图层纹理 - 优化版本
  Future<ui.Image?> getLayerTextureFast(String assetPath) async {
    _totalRequests++;

    // 首先检查激进缓存
    if (_aggressiveCache.containsKey(assetPath)) {
      _cacheHits++;
      return _aggressiveCache[assetPath];
    }

    // 检查正在加载的任务
    if (_loadingTasks.containsKey(assetPath)) {
      return await _loadingTasks[assetPath];
    }

    // 开始快速加载
    final loadingTask = _loadTextureFast(assetPath);
    _loadingTasks[assetPath] = loadingTask;

    try {
      final texture = await loadingTask;
      if (texture != null) {
        _aggressiveCache[assetPath] = texture;
      }
      return texture;
    } finally {
      _loadingTasks.remove(assetPath);
    }
  }

  /// 快速纹理加载
  Future<ui.Image?> _loadTextureFast(String assetPath) async {
    try {
      final fullPath = await AssetManager().findAsset('characters/$assetPath');
      if (fullPath == null) return null;

      // 使用优化的加载方式
      return await _loadImageOptimized(fullPath);
    } catch (e) {
      return null;
    }
  }

  /// 优化的图像加载
  Future<ui.Image?> _loadImageOptimized(String path) async {
    try {
      // 直接读取文件
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();

      // 使用UI线程的图像解码
      final codec = await ui.instantiateImageCodec(
        bytes,
        allowUpscaling: false, // 禁用放大以提高性能
      );

      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  /// 预合成常用组合
  Future<ui.Image?> getPrecompositeImage(
      String resourceId, String pose, String expression) async {
    final key = '${resourceId}_${pose}_$expression';

    // 检查预合成缓存
    if (_precompositeCache.containsKey(key)) {
      return _precompositeCache[key];
    }

    // 获取图层
    final basePath = '$resourceId-$pose';
    final exprPath = '$resourceId-$expression';

    final baseImage = await getLayerTextureFast(basePath);
    final exprImage = await getLayerTextureFast(exprPath);

    if (baseImage == null) return null;

    // 如果只有基础图层，直接返回
    if (exprImage == null) {
      _precompositeCache[key] = baseImage;
      return baseImage;
    }

    // 快速合成
    final compositeImage = await _fastComposite([baseImage, exprImage]);
    if (compositeImage != null) {
      _precompositeCache[key] = compositeImage;
    }

    return compositeImage;
  }

  /// 快速图像合成
  Future<ui.Image?> _fastComposite(List<ui.Image> layers) async {
    if (layers.isEmpty) return null;
    if (layers.length == 1) return layers[0];

    try {
      final baseImage = layers[0];
      final width = baseImage.width;
      final height = baseImage.height;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      // 快速绘制所有图层
      for (final layer in layers) {
        final paint = ui.Paint()
          ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
            defaultQuality: ui.FilterQuality.low,
          ); // 使用低质量以提高速度
        canvas.drawImage(layer, Offset.zero, paint);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();

      return image;
    } catch (e) {
      return null;
    }
  }

  /// 获取性能统计
  Map<String, dynamic> getStats() {
    final hitRate = _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0;

    return {
      'cache_type': 'optimized',
      'total_requests': _totalRequests,
      'cache_hits': _cacheHits,
      'hit_rate': hitRate,
      'aggressive_cache_size': _aggressiveCache.length,
      'precomposite_cache_size': _precompositeCache.length,
      'loading_tasks': _loadingTasks.length,
    };
  }

  /// 清理缓存
  void clearCache() {
    for (final image in _aggressiveCache.values) {
      try {
        image.dispose();
      } catch (e) {
        // 静默处理
      }
    }
    _aggressiveCache.clear();

    for (final image in _precompositeCache.values) {
      try {
        image.dispose();
      } catch (e) {
        // 静默处理
      }
    }
    _precompositeCache.clear();

    _loadingTasks.clear();
    _totalRequests = 0;
    _cacheHits = 0;
    _lastStatsReset = DateTime.now();
  }
}
