/// 智能图层缓存管理系统
/// 
/// 负责GPU纹理的预测性加载、智能缓存策略和内存管理
/// 基于Ren'Py的缓存策略进行优化

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:collection';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/rendering/layered/layer_types.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/image_loader.dart';

/// 智能图层缓存管理器
/// 
/// 功能：
/// - GPU纹理的预测性加载和缓存
/// - LRU缓存策略自动管理内存
/// - 支持预热常用图层组合
/// - 提供详细的缓存统计信息
class SmartLayerCache {
  static final SmartLayerCache _instance = SmartLayerCache._internal();
  factory SmartLayerCache() => _instance;
  SmartLayerCache._internal();

  /// GPU纹理缓存 - assetPath -> Image
  final Map<String, ui.Image> _textureCache = <String, ui.Image>{};
  
  /// LRU访问顺序记录
  final LinkedHashMap<String, DateTime> _accessOrder = LinkedHashMap<String, DateTime>();
  
  /// 正在加载的任务，避免重复加载
  final Map<String, Future<ui.Image?>> _loadingTasks = <String, Future<ui.Image?>>{};
  
  /// 预热队列 - 预测即将需要的图层
  final Queue<String> _preloadQueue = Queue<String>();
  
  /// 缓存统计信息
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;
  DateTime _statsResetTime = DateTime.now();
  
  /// 缓存配置
  static const int _maxCacheSize = 50; // 最大缓存图层数
  static const Duration _maxCacheAge = Duration(minutes: 30); // 最大缓存时间
  static const int _preloadBatchSize = 3; // 每批预加载的图层数
  
  /// 预测模式配置
  bool _predictiveLoadingEnabled = true;
  Set<String> _commonExpressions = {'1', '2', '3', '4', '5', 'happy', 'sad', 'angry', 'surprised'};

  /// 获取图层纹理
  /// 
  /// 优先从缓存获取，缓存未命中时异步加载
  Future<ui.Image?> getLayerTexture(String assetPath) async {
    _totalRequests++;
    
    // 更新访问时间
    _updateAccessTime(assetPath);
    
    // 检查缓存
    if (_textureCache.containsKey(assetPath)) {
      _cacheHits++;
      if (kEngineDebugMode) {
        print('[SmartLayerCache] Cache hit: $assetPath');
      }
      return _textureCache[assetPath];
    }
    
    _cacheMisses++;
    
    // 检查是否已在加载中
    if (_loadingTasks.containsKey(assetPath)) {
      if (kEngineDebugMode) {
        print('[SmartLayerCache] Loading in progress: $assetPath');
      }
      return await _loadingTasks[assetPath];
    }
    
    // 开始异步加载
    final loadingTask = _loadTexture(assetPath);
    _loadingTasks[assetPath] = loadingTask;
    
    try {
      final texture = await loadingTask;
      if (texture != null) {
        _cacheTexture(assetPath, texture);
        if (kEngineDebugMode) {
          print('[SmartLayerCache] Loaded and cached: $assetPath');
        }
      }
      return texture;
    } finally {
      _loadingTasks.remove(assetPath);
    }
  }

  /// 预热图层缓存
  /// 
  /// 根据当前显示的图层预测并预加载可能需要的图层
  Future<void> preloadLayers(String resourceId, String pose, {String? currentExpression}) async {
    if (!_predictiveLoadingEnabled) return;
    
    final basePattern = '${resourceId}_$pose';
    
    // 预加载常见表情差分
    for (final expression in _commonExpressions) {
      if (expression == currentExpression) continue; // 跳过当前表情
      
      final assetPath = '${basePattern}_$expression';
      
      // 检查资源是否存在
      final fullPath = await AssetManager().findAsset(assetPath);
      if (fullPath != null && !_textureCache.containsKey(fullPath)) {
        _preloadQueue.add(fullPath);
      }
    }
    
    // 批量预加载
    _processPreloadQueue();
  }

  /// 批量预热指定的图层列表
  Future<void> batchPreload(List<String> assetPaths) async {
    for (final assetPath in assetPaths) {
      final fullPath = await AssetManager().findAsset(assetPath);
      if (fullPath != null && !_textureCache.containsKey(fullPath)) {
        _preloadQueue.add(fullPath);
      }
    }
    
    _processPreloadQueue();
  }

  /// 处理预加载队列
  void _processPreloadQueue() {
    if (_preloadQueue.isEmpty) return;
    
    // 取出一批进行预加载
    final batch = <String>[];
    for (int i = 0; i < _preloadBatchSize && _preloadQueue.isNotEmpty; i++) {
      batch.add(_preloadQueue.removeFirst());
    }
    
    // 异步预加载，不阻塞主流程
    unawaited(_preloadBatch(batch));
  }

  /// 异步预加载一批图层
  Future<void> _preloadBatch(List<String> assetPaths) async {
    final preloadTasks = assetPaths.map((assetPath) async {
      try {
        await getLayerTexture(assetPath);
      } catch (e) {
        if (kEngineDebugMode) {
          print('[SmartLayerCache] Preload failed: $assetPath - $e');
        }
      }
    });
    
    await Future.wait(preloadTasks);
    
    // 继续处理剩余队列
    if (_preloadQueue.isNotEmpty) {
      _processPreloadQueue();
    }
  }

  /// 实际加载纹理的方法
  Future<ui.Image?> _loadTexture(String assetPath) async {
    try {
      final fullPath = await AssetManager().findAsset(assetPath);
      if (fullPath == null) {
        if (kEngineDebugMode) {
          print('[SmartLayerCache] Asset not found: $assetPath');
        }
        return null;
      }
      
      return await ImageLoader.loadImage(fullPath);
    } catch (e) {
      if (kEngineDebugMode) {
        print('[SmartLayerCache] Failed to load texture: $assetPath - $e');
      }
      return null;
    }
  }

  /// 缓存纹理
  void _cacheTexture(String assetPath, ui.Image texture) {
    // 检查缓存大小，必要时清理
    if (_textureCache.length >= _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }
    
    _textureCache[assetPath] = texture;
    _updateAccessTime(assetPath);
  }

  /// 更新访问时间
  void _updateAccessTime(String assetPath) {
    _accessOrder[assetPath] = DateTime.now();
  }

  /// LRU缓存淘汰
  void _evictLeastRecentlyUsed() {
    if (_accessOrder.isEmpty) return;
    
    // 找出最久未访问的资源
    String? oldestKey;
    DateTime? oldestTime;
    
    for (final entry in _accessOrder.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestKey = entry.key;
        oldestTime = entry.value;
      }
    }
    
    if (oldestKey != null) {
      _evictTexture(oldestKey);
      if (kEngineDebugMode) {
        print('[SmartLayerCache] Evicted LRU texture: $oldestKey');
      }
    }
  }

  /// 淘汰指定纹理
  void _evictTexture(String assetPath) {
    final texture = _textureCache.remove(assetPath);
    texture?.dispose();
    _accessOrder.remove(assetPath);
  }

  /// 清理过期缓存
  void cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _accessOrder.entries) {
      if (now.difference(entry.value) > _maxCacheAge) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _evictTexture(key);
    }
    
    if (expiredKeys.isNotEmpty && kEngineDebugMode) {
      print('[SmartLayerCache] Cleaned up ${expiredKeys.length} expired textures');
    }
  }

  /// 强制清理所有缓存
  void clearAll() {
    for (final texture in _textureCache.values) {
      texture.dispose();
    }
    _textureCache.clear();
    _accessOrder.clear();
    _loadingTasks.clear();
    _preloadQueue.clear();
    
    // 重置统计
    _resetStats();
    
    if (kEngineDebugMode) {
      print('[SmartLayerCache] All cache cleared');
    }
  }

  /// 获取缓存统计信息
  LayeredRenderingStats getCacheStats() {
    final cacheHitRate = _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0;
    final now = DateTime.now();
    final timeWindow = now.difference(_statsResetTime);
    
    // 计算GPU内存使用（估算）
    int gpuMemoryUsage = 0;
    for (final texture in _textureCache.values) {
      gpuMemoryUsage += texture.width * texture.height * 4; // RGBA, 4 bytes per pixel
    }
    
    return LayeredRenderingStats(
      activeLayers: _textureCache.length,
      cacheHitRate: cacheHitRate,
      averageRenderTime: 0.0, // 由渲染器计算
      gpuMemoryUsage: gpuMemoryUsage,
      systemMemoryUsage: 0, // 由系统监控计算
      framesPerSecond: 0.0, // 由渲染器计算
      timeWindow: timeWindow,
      timestamp: now,
    );
  }

  /// 获取详细的缓存信息
  Map<String, dynamic> getDetailedCacheInfo() {
    return {
      'cached_textures': _textureCache.length,
      'loading_tasks': _loadingTasks.length,
      'preload_queue_size': _preloadQueue.length,
      'cache_hits': _cacheHits,
      'cache_misses': _cacheMisses,
      'total_requests': _totalRequests,
      'cache_hit_rate': _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0,
      'max_cache_size': _maxCacheSize,
      'predictive_loading_enabled': _predictiveLoadingEnabled,
      'stats_reset_time': _statsResetTime.toIso8601String(),
      'cached_assets': _textureCache.keys.toList(),
    };
  }

  /// 重置统计信息
  void _resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _totalRequests = 0;
    _statsResetTime = DateTime.now();
  }

  /// 启用/禁用预测性加载
  void setPredictiveLoading(bool enabled) {
    _predictiveLoadingEnabled = enabled;
    if (kEngineDebugMode) {
      print('[SmartLayerCache] Predictive loading: ${enabled ? "enabled" : "disabled"}');
    }
  }

  /// 设置常见表情列表
  void setCommonExpressions(Set<String> expressions) {
    _commonExpressions = expressions;
    if (kEngineDebugMode) {
      print('[SmartLayerCache] Common expressions updated: $expressions');
    }
  }

  /// 检查资源是否已缓存
  bool isTextureCached(String assetPath) {
    return _textureCache.containsKey(assetPath);
  }

  /// 获取缓存大小
  int get cacheSize => _textureCache.length;

  /// 获取缓存命中率
  double get cacheHitRate => _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0;
}