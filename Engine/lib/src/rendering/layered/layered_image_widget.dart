/// Flutter层叠图像显示组件
///
/// 基于Stack的高性能层叠渲染组件
/// 实现Ren'Py式的实时层叠显示，支持流畅的动画切换

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/rendering/layered/layer_types.dart';
import 'package:sakiengine/src/rendering/layered/layered_image_renderer.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// 高性能层叠图像显示组件
///
/// 特性：
/// - 基于Stack的GPU加速层叠渲染
/// - 支持微秒级的图层切换
/// - 内置淡入淡出动画
/// - 自动内存管理和性能优化
class LayeredImageWidget extends StatefulWidget {
  /// 资源ID
  final String resourceId;

  /// 姿势
  final String pose;

  /// 表情
  final String expression;

  /// 额外属性
  final Set<String>? attributes;

  /// 是否正在淡出
  final bool isFadingOut;

  /// 全局透明度
  final double opacity;

  /// 全局缩放
  final double scale;

  /// 动画持续时间
  final Duration animationDuration;

  /// 自适应尺寸模式
  final BoxFit fit;

  /// 对齐方式
  final Alignment alignment;

  /// 性能监控回调
  final void Function(LayeredRenderingStats stats)? onStatsUpdate;

  /// 快进等场景下优先速度模式
  final bool preferSpeed;

  const LayeredImageWidget({
    super.key,
    required this.resourceId,
    required this.pose,
    required this.expression,
    this.attributes,
    this.isFadingOut = false,
    this.opacity = 1.0,
    this.scale = 1.0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.onStatsUpdate,
    this.preferSpeed = false,
  });

  @override
  State<LayeredImageWidget> createState() => _LayeredImageWidgetState();
}

class _LayeredImageWidgetState extends State<LayeredImageWidget>
    with TickerProviderStateMixin {
  /// 渲染器实例
  final LayeredImageRenderer _renderer = LayeredImageRenderer();

  /// 当前显示的图像状态
  LayeredImageState? _currentState;

  /// 图层纹理列表
  List<ui.Image> _layerTextures = [];

  /// 动画控制器
  late final AnimationController _fadeController;
  late final AnimationController _scaleController;

  /// 动画
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  /// 加载状态
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  /// 性能统计定时器
  Timer? _statsTimer;

  /// 上一次的参数（用于检测变化）
  String? _lastImageId;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // 初始加载
    _loadLayeredImage();

    // 启动性能监控
    if (widget.onStatsUpdate != null) {
      _startStatsMonitoring();
    }
  }

  @override
  void didUpdateWidget(LayeredImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检查参数是否改变
    final newImageId =
        '${widget.resourceId}_${widget.pose}_${widget.expression}';

    if (_lastImageId != newImageId) {
      // 图像参数改变，重新加载
      _loadLayeredImage(isUpdate: true);
    } else if (oldWidget.isFadingOut != widget.isFadingOut) {
      // 只是淡入淡出状态改变
      if (widget.isFadingOut) {
        _fadeController.reverse();
      } else {
        _fadeController.forward();
      }
    }

    // 更新性能监控
    if (widget.onStatsUpdate != null && _statsTimer == null) {
      _startStatsMonitoring();
    } else if (widget.onStatsUpdate == null && _statsTimer != null) {
      _stopStatsMonitoring();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _stopStatsMonitoring();
    _layerTextures = [];
    super.dispose();
  }

  /// 加载层叠图像
  Future<void> _loadLayeredImage({bool isUpdate = false}) async {
    if (!mounted) return;

    final stopwatch = Stopwatch()..start();

    final bool hadTextures = _layerTextures.isNotEmpty && _currentState != null;

    setState(() {
      _isLoading = !hadTextures;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final imageId =
          '${widget.resourceId}_${widget.pose}_${widget.expression}';

      LayeredImageState? newState;

      if (isUpdate && _lastImageId != null) {
        // 尝试快速更新（只更换表情等）
        newState = await _renderer.updateLayeredImage(
          baseImageId: _lastImageId!,
          newExpression: widget.expression,
          newAttributes: widget.attributes,
        );
      }

      // 如果快速更新失败或是首次加载，完整加载
      newState ??= await _renderer.createLayeredImage(
        resourceId: widget.resourceId,
        pose: widget.pose,
        expression: widget.expression,
        attributes: widget.attributes,
      );

      if (newState == null) {
        throw Exception('Failed to create layered image: $imageId');
      }

      // 加载纹理
      final newTextures = await _renderer.getLayerTextures(newState);

      if (!mounted) {
        return;
      }

      setState(() {
        _currentState = newState;
        _layerTextures = newTextures;
        _lastImageId = imageId;
        _isLoading = false;
      });

      // 开始动画
      if (!widget.isFadingOut) {
        _fadeController.forward();
        _scaleController.forward();
      }

      stopwatch.stop();

      if (kEngineDebugMode) {
        print(
          '[LayeredImageWidget] Loaded in ${stopwatch.elapsedMilliseconds}ms: $imageId (${newTextures.length} layers)',
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });

      if (kEngineDebugMode) {
        print('[LayeredImageWidget] Load error: $e\n$stackTrace');
      }
    }
  }

  /// 启动性能监控
  void _startStatsMonitoring() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || widget.onStatsUpdate == null) return;

      final stats = _renderer.getPerformanceStats();
      widget.onStatsUpdate!(stats);
    });
  }

  /// 停止性能监控
  void _stopStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasTextures = _layerTextures.isNotEmpty && _currentState != null;

    if (!hasTextures) {
      if (_hasError) {
        return _buildErrorWidget();
      }
      if (_isLoading) {
        return kIsWeb ? const SizedBox.expand() : _buildLoadingWidget();
      }
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_fadeAnimation, _scaleAnimation]),
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value * widget.opacity,
          child: Transform.scale(
            scale: _scaleAnimation.value * widget.scale,
            child: _buildLayeredStack(),
          ),
        );
      },
    );
  }

  /// 构建层叠Stack
  Widget _buildLayeredStack() {
    final visibleLayers = _currentState!.visibleLayers;

    return Stack(
      alignment: widget.alignment,
      fit: StackFit.expand,
      children: List.generate(_layerTextures.length, (index) {
        if (index >= visibleLayers.length) return const SizedBox.shrink();

        final layer = visibleLayers[index];
        final texture = _layerTextures[index];

        return _LayerWidget(
          key: ValueKey(layer.layerId),
          texture: texture,
          layer: layer,
          fit: widget.fit,
          preferSpeed: widget.preferSpeed,
        );
      }),
    );
  }

  /// 构建加载中组件
  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.transparent,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  /// 构建错误组件
  Widget _buildErrorWidget() {
    if (kEngineDebugMode) {
      return Container(
        color: Colors.red.withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                'LayeredImage Error',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _errorMessage ?? 'Unknown error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      // 生产环境中静默失败
      return const SizedBox.shrink();
    }
  }
}

/// 单个图层显示组件
class _LayerWidget extends StatelessWidget {
  final ui.Image texture;
  final LayerInfo layer;
  final BoxFit fit;
  final bool preferSpeed;

  const _LayerWidget({
    super.key,
    required this.texture,
    required this.layer,
    required this.fit,
    required this.preferSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: layer.opacity,
      child: Transform.translate(
        offset: Offset(layer.offsetX, layer.offsetY),
        child: Transform.scale(
          scale: layer.scale,
          child: CustomPaint(
            painter: _LayerPainter(
              texture: texture,
              fit: fit,
              preferSpeed: preferSpeed,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// 自定义图层绘制器
class _LayerPainter extends CustomPainter {
  final ui.Image texture;
  final BoxFit fit;
  final bool preferSpeed;

  _LayerPainter({
    required this.texture,
    required this.fit,
    this.preferSpeed = false,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;

    // 检查纹理是否有效
    if (texture.width <= 0 || texture.height <= 0) return;

    try {
      final textureSize = Size(
        texture.width.toDouble(),
        texture.height.toDouble(),
      );

      // 根据BoxFit计算源和目标矩形
      final fittedSizes = applyBoxFit(fit, textureSize, size);
      final sourceSize = fittedSizes.source;
      final destinationSize = fittedSizes.destination;

      // 确保源矩形不超出纹理边界
      final sourceRect = Rect.fromLTWH(
        math.max(0, (textureSize.width - sourceSize.width) / 2),
        math.max(0, (textureSize.height - sourceSize.height) / 2),
        math.min(sourceSize.width, textureSize.width),
        math.min(sourceSize.height, textureSize.height),
      );

      final destinationRect = Rect.fromLTWH(
        (size.width - destinationSize.width) / 2,
        (size.height - destinationSize.height) / 2,
        destinationSize.width,
        destinationSize.height,
      );

      // 验证矩形有效性
      if (sourceRect.isEmpty || destinationRect.isEmpty) return;

      // 高质量绘制
      final paint = ui.Paint()
        ..isAntiAlias = true
        ..filterQuality =
            ImageSamplingManager().resolveCanvasFilterQualityBySpeed(
          preferSpeed: preferSpeed,
        );

      canvas.drawImageRect(texture, sourceRect, destinationRect, paint);
    } catch (e) {
      if (kEngineDebugMode) {
        print('[_LayerPainter] Paint error: $e');
      }
      // 静默失败，避免崩溃
    }
  }

  @override
  bool shouldRepaint(covariant _LayerPainter oldDelegate) {
    return texture != oldDelegate.texture ||
        fit != oldDelegate.fit ||
        preferSpeed != oldDelegate.preferSpeed;
  }
}

/// 性能监控组件（可选）
class LayeredImagePerformanceMonitor extends StatelessWidget {
  final LayeredRenderingStats stats;
  final Widget child;

  const LayeredImagePerformanceMonitor({
    super.key,
    required this.stats,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!kEngineDebugMode) return child;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FPS: ${stats.framesPerSecond.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                Text(
                  'Layers: ${stats.activeLayers}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                Text(
                  'Cache: ${(stats.cacheHitRate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                Text(
                  'Render: ${stats.averageRenderTime.toStringAsFixed(1)}ms',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
