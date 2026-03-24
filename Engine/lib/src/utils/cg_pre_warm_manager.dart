import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/utils/cg_image_compositor.dart';
import 'package:sakiengine/src/utils/gpu_image_compositor.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// CG预热任务优先级
enum PreWarmPriority {
  /// 紧急：当前正在显示的CG，需要立即预热
  urgent(100),

  /// 高：即将出现的CG，优先预热
  high(80),

  /// 中：预测性预热，可能会用到的CG
  medium(50),

  /// 低：后台预热，空闲时处理
  low(20);

  const PreWarmPriority(this.value);
  final int value;
}

/// CG预热任务
class PreWarmTask {
  final String resourceId;
  final String pose;
  final String expression;
  final String cacheKey;
  final PreWarmPriority priority;
  final DateTime createdAt;

  /// 预热完成的Completer
  final Completer<bool> _completer = Completer<bool>();

  PreWarmTask({
    required this.resourceId,
    required this.pose,
    required this.expression,
    required this.cacheKey,
    required this.priority,
  }) : createdAt = DateTime.now();

  /// 获取预热完成的Future
  Future<bool> get completed => _completer.future;

  /// 标记任务完成
  void complete(bool success) {
    if (!_completer.isCompleted) {
      _completer.complete(success);
    }
  }

  /// 标记任务失败
  void completeWithError(Object error) {
    if (!_completer.isCompleted) {
      _completer.completeError(error);
    }
  }
}

/// CG预热状态
enum PreWarmStatus {
  /// 未预热
  notWarmed,

  /// 预热中
  warming,

  /// 预热完成
  warmed,

  /// 预热失败
  failed,
}

/// CG预热管理器 - 智能管理CG图像的预热
///
/// 功能：
/// - 优先级队列管理预热任务
/// - 智能预热调度，避免阻塞主线程
/// - 预热状态追踪和查询
/// - 内存管理和生命周期控制
class CgPreWarmManager {
  static final CgPreWarmManager _instance = CgPreWarmManager._internal();
  factory CgPreWarmManager() => _instance;
  CgPreWarmManager._internal();

  final CgImageCompositor _compositor = CgImageCompositor();
  final GpuImageCompositor _gpuCompositor = GpuImageCompositor();

  /// 性能优化开关
  bool _useGpuAcceleration = true;

  /// 预热任务优先级队列
  final PriorityQueue<PreWarmTask> _taskQueue = PriorityQueue<PreWarmTask>(
    (a, b) => b.priority.value.compareTo(a.priority.value), // 高优先级在前
  );

  /// 预热状态追踪：cacheKey -> 状态
  final Map<String, PreWarmStatus> _warmStatus = {};

  /// 正在执行的预热任务
  final Set<String> _processingTasks = {};

  /// 预热工作器是否正在运行
  bool _isWorkerRunning = false;

  /// 最大并发预热任务数量
  static const int _maxConcurrentTasks = 2;

  /// 启动预热管理器
  void start() {
    if (!_isWorkerRunning) {
      _isWorkerRunning = true;
      _runPreWarmWorker();

      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] 🔥 预热管理器已启动');
      }
    }
  }

  /// 停止预热管理器
  void stop() {
    _isWorkerRunning = false;
    _clearAllTasks();

    if (kEngineDebugMode) {
      //print('[CgPreWarmManager] 🔥 预热管理器已停止');
    }
  }

  /// 添加预热任务
  Future<bool> preWarm({
    required String resourceId,
    required String pose,
    required String expression,
    PreWarmPriority priority = PreWarmPriority.medium,
  }) async {
    final cacheKey = '${resourceId}_${pose}_$expression';

    // 检查是否已经预热完成
    if (_warmStatus[cacheKey] == PreWarmStatus.warmed) {
      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] ✅ 已预热: $cacheKey');
      }
      return true;
    }

    // 检查是否已在队列中或正在处理
    if (_warmStatus[cacheKey] == PreWarmStatus.warming ||
        _processingTasks.contains(cacheKey)) {
      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] ⏳ 预热中: $cacheKey');
      }
      return await _waitForCompletion(cacheKey);
    }

    // 创建预热任务
    final task = PreWarmTask(
      resourceId: resourceId,
      pose: pose,
      expression: expression,
      cacheKey: cacheKey,
      priority: priority,
    );

    // 添加到队列
    _taskQueue.add(task);
    _warmStatus[cacheKey] = PreWarmStatus.warming;

    if (kEngineDebugMode) {
      //print('[CgPreWarmManager] 🔥 添加预热任务: $cacheKey (优先级: ${priority.name})');
    }

    // 确保工作器运行
    start();

    return await task.completed;
  }

  /// 批量预热
  Future<List<bool>> preWarmBatch(List<Map<String, dynamic>> cgList) async {
    final futures = <Future<bool>>[];

    for (final cg in cgList) {
      final resourceId = cg['resourceId'] as String;
      final pose = cg['pose'] as String? ?? 'pose1';
      final expression = cg['expression'] as String? ?? '1';
      final priority =
          cg['priority'] as PreWarmPriority? ?? PreWarmPriority.medium;

      futures.add(preWarm(
        resourceId: resourceId,
        pose: pose,
        expression: expression,
        priority: priority,
      ));
    }

    return await Future.wait(futures);
  }

  /// 紧急预热：立即处理高优先级任务
  Future<bool> preWarmUrgent({
    required String resourceId,
    required String pose,
    required String expression,
  }) async {
    return await preWarm(
      resourceId: resourceId,
      pose: pose,
      expression: expression,
      priority: PreWarmPriority.urgent,
    );
  }

  /// 检查CG是否已预热
  bool isWarmed(String resourceId, String pose, String expression) {
    final cacheKey = '${resourceId}_${pose}_$expression';
    return _warmStatus[cacheKey] == PreWarmStatus.warmed;
  }

  /// 获取预热状态
  PreWarmStatus getWarmStatus(
      String resourceId, String pose, String expression) {
    final cacheKey = '${resourceId}_${pose}_$expression';
    return _warmStatus[cacheKey] ?? PreWarmStatus.notWarmed;
  }

  /// 获取预热的图像（如果有）
  ui.Image? getPreWarmedImage(
      String resourceId, String pose, String expression) {
    return null;
  }

  /// 预热工作器：后台处理预热队列
  void _runPreWarmWorker() async {
    while (_isWorkerRunning) {
      try {
        // 控制并发数量
        if (_processingTasks.length >= _maxConcurrentTasks) {
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }

        // 获取下一个任务
        if (_taskQueue.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final task = _taskQueue.removeFirst();

        // 启动预热任务（不等待完成）
        _processPreWarmTask(task);
      } catch (e) {
        if (kEngineDebugMode) {
          //print('[CgPreWarmManager] ⚠️ 预热工作器错误: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// 处理单个预热任务
  Future<void> _processPreWarmTask(PreWarmTask task) async {
    _processingTasks.add(task.cacheKey);

    try {
      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] 🔥 开始预热: ${task.cacheKey} (优先级: ${task.priority.name})');
      }

      if (_useGpuAcceleration) {
        final entry = await _gpuCompositor.getCompositeEntry(
          resourceId: task.resourceId,
          pose: task.pose,
          expression: task.expression,
        );

        if (entry == null) {
          throw Exception('Failed to compose image');
        }

        await _performGpuPreWarm(task.cacheKey, entry.result);
      } else {
        final imagePath = await _compositor.getCompositeImagePath(
          resourceId: task.resourceId,
          pose: task.pose,
          expression: task.expression,
        );

        if (imagePath == null) {
          throw Exception('Failed to compose image');
        }

        final imageBytes = _compositor.getImageBytes(imagePath);
        if (imageBytes == null) {
          throw Exception('Failed to get image bytes');
        }

        await _performCpuPreWarm(task.cacheKey, imageBytes);
      }

      // 标记完成
      _warmStatus[task.cacheKey] = PreWarmStatus.warmed;
      task.complete(true);

      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] ✅ 预热完成: ${task.cacheKey}');
      }
    } catch (e) {
      _warmStatus[task.cacheKey] = PreWarmStatus.failed;
      task.completeWithError(e);

      if (kEngineDebugMode) {
        //print('[CgPreWarmManager] ❌ 预热失败: ${task.cacheKey}, 错误: $e');
      }
    } finally {
      _processingTasks.remove(task.cacheKey);
    }
  }

  /// 执行 CPU 合成路径的预热操作
  Future<void> _performCpuPreWarm(String cacheKey, Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      // 解码失败时忽略，预热流程不应中断
    }
  }

  /// 执行 GPU 图层的预热操作
  Future<void> _performGpuPreWarm(
    String cacheKey,
    GpuCompositeResult result,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final targetRect = ui.Rect.fromLTWH(
      0,
      0,
      result.width.toDouble(),
      result.height.toDouble(),
    );
    final srcRect = ui.Rect.fromLTWH(
      0,
      0,
      result.width.toDouble(),
      result.height.toDouble(),
    );
    final paint = ui.Paint()
      ..isAntiAlias = false
      ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
        defaultQuality: ui.FilterQuality.none,
      );

    for (var i = 0; i < result.layers.length; i++) {
      paint.blendMode = i == 0 ? ui.BlendMode.src : ui.BlendMode.srcOver;
      canvas.drawImageRect(
        result.layers[i],
        srcRect,
        targetRect,
        paint,
      );
    }

    final picture = recorder.endRecording();
    final raster = await picture.toImage(result.width, result.height);
    picture.dispose();
    raster.dispose();
  }

  /// 等待指定CG的预热完成
  Future<bool> _waitForCompletion(String cacheKey) async {
    // 简单的轮询等待（可以优化为更精确的Future等待）
    while (_warmStatus[cacheKey] == PreWarmStatus.warming) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    return _warmStatus[cacheKey] == PreWarmStatus.warmed;
  }

  /// 清理所有预热任务
  void _clearAllTasks() {
    _taskQueue.clear();
    _warmStatus.clear();
    _processingTasks.clear();
  }

  /// 设置GPU加速开关
  void setGpuAcceleration(bool enabled) {
    _useGpuAcceleration = enabled;
    if (kEngineDebugMode) {
      print('[CgPreWarmManager] GPU加速已${enabled ? "启用" : "禁用"}');
    }
  }

  /// 获取预热管理器状态
  Map<String, dynamic> getStatus() {
    return {
      'gpu_acceleration': _useGpuAcceleration,
      'worker_running': _isWorkerRunning,
      'queue_size': _taskQueue.length,
      'processing_tasks': _processingTasks.length,
      'warmed_count':
          _warmStatus.values.where((s) => s == PreWarmStatus.warmed).length,
      'warm_status': _warmStatus,
    };
  }
}

/// 简单的优先级队列实现
class PriorityQueue<T> {
  final List<T> _items = [];
  final int Function(T, T) _comparator;

  PriorityQueue(this._comparator);

  void add(T item) {
    _items.add(item);
    _items.sort(_comparator);
  }

  T removeFirst() {
    if (_items.isEmpty) {
      throw StateError('Queue is empty');
    }
    return _items.removeAt(0);
  }

  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  void clear() {
    _items.clear();
  }
}
