import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/utils/engine_asset_loader.dart';
import 'package:sakiengine/src/utils/image_loader.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

/// CG角色渲染器，负责处理CG模式下的角色显示
class CgCharacterRenderer {
  static List<Widget> buildCgCharacters(
      BuildContext context,
      Map<String, CharacterState> cgCharacters,
      Map<String, PoseConfig> poseConfigs,
      Set<String> everShownCharacters) {
    //print('[CgCharacterRenderer] 构建CG角色，数量: ${cgCharacters.length}');
    if (cgCharacters.isEmpty) return [];

    // 按resourceId分组，保留最新的角色状态
    final Map<String, MapEntry<String, CharacterState>> charactersByResourceId =
        {};

    for (final entry in cgCharacters.entries) {
      final resourceId = entry.value.resourceId;
      //print('[CgCharacterRenderer] 处理CG角色: ${entry.key}, resourceId: $resourceId, pose: ${entry.value.pose}, expression: ${entry.value.expression}');
      // 总是保留最新的状态（覆盖之前的）
      charactersByResourceId[resourceId] = entry;
    }

    return charactersByResourceId.values.map((entry) {
      final characterId = entry.key;
      final characterState = entry.value;

      final widgetKey = 'cg_$characterId';

      return FutureBuilder<List<CharacterLayerInfo>>(
        key: ValueKey(widgetKey),
        future: CharacterLayerParser.parseCharacterLayers(
          resourceId: characterState.resourceId,
          pose: characterState.pose ?? 'pose1',
          expression: characterState.expression ?? 'happy',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }

          final layerInfos = snapshot.data!;

          // 使用同步CG显示组件来处理首次显示的同步问题
          return SynchronizedCgDisplay(
            key: ValueKey('sync_cg_$characterId'),
            layerInfos: layerInfos,
            resourceId: characterState.resourceId,
            isFadingOut: characterState.isFadingOut,
          );
        },
      );
    }).toList();
  }
}

/// CG角色图层组件，以铺满屏幕的方式渲染图像
class CgCharacterLayer extends StatefulWidget {
  final String assetName;
  final bool isFadingOut;
  final VoidCallback? onFadeOutComplete;
  final VoidCallback? onReady; // 图层准备好时的回调
  final bool showImmediately; // 是否立即显示

  const CgCharacterLayer({
    super.key,
    required this.assetName,
    this.isFadingOut = false,
    this.onFadeOutComplete,
    this.onReady,
    this.showImmediately = true,
  });

  @override
  State<CgCharacterLayer> createState() => _CgCharacterLayerState();
}

class _CgCharacterLayerState extends State<CgCharacterLayer>
    with SingleTickerProviderStateMixin {
  ui.Image? _currentImage;
  ui.Image? _previousImage;

  late final AnimationController _controller;
  late final Animation<double> _animation;

  static ui.FragmentProgram? _dissolveProgram;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _loadImage();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (_dissolveProgram == null) {
      try {
        final program = await EngineAssetLoader.loadFragmentProgram(
          'assets/shaders/dissolve.frag',
        );
        _dissolveProgram = program;
      } catch (e) {
        print('Error loading shader: $e');
      }
    }
  }

  @override
  void didUpdateWidget(covariant CgCharacterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检查是否开始淡出
    if (!oldWidget.isFadingOut && widget.isFadingOut) {
      // 开始淡出动画
      _controller.reverse().then((_) {
        // 淡出完成，通知回调
        widget.onFadeOutComplete?.call();
      });
      return;
    }

    // 无论是否资源名称改变，只要不是淡出状态，就确保图像完整显示
    if (oldWidget.assetName != widget.assetName) {
      // 资源改变时，保存当前图像作为过渡源
      _previousImage = _currentImage;
      _loadImage().then((_) {
        if (mounted && !widget.isFadingOut) {
          // 平滑过渡到新图像
          _controller.forward(from: 0.0);
        }
      });
    } else if (!widget.isFadingOut && _controller.value < 1.0) {
      // 资源未改变但动画未完成，继续动画
      _controller.forward();
    }
  }

  Future<void> _loadImage() async {
    final assetPath = await AssetManager().findAsset(widget.assetName);
    if (assetPath != null && mounted) {
      final image = await ImageLoader.loadImage(assetPath);
      if (mounted && image != null) {
        setState(() {
          _currentImage = image;
        });

        // 确保在下一帧再通知准备好了，这样setState已经完成
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onReady?.call();
            // 如果不是淡出状态，确保动画开始
            if (!widget.isFadingOut) {
              _controller.forward(from: 0.0);
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _currentImage?.dispose();
    _previousImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果不应该立即显示，先返回空组件
    if (!widget.showImmediately) {
      return const SizedBox.shrink();
    }

    if (_currentImage == null || _dissolveProgram == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // CG图像使用dissolve shader进行差分渐变，然后用BoxFit.cover铺满屏幕
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: CgDissolvePainter(
                program: _dissolveProgram!,
                progress: _animation.value,
                imageFrom: _previousImage ?? _currentImage!,
                imageTo: _currentImage!,
              ),
            );
          },
        );
      },
    );
  }
}

/// CG图层的溶解绘制器，专门为铺满屏幕的CG渲染优化
class CgDissolvePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final double progress;
  final ui.Image imageFrom;
  final ui.Image imageTo;

  CgDissolvePainter({
    required this.program,
    required this.progress,
    required this.imageFrom,
    required this.imageTo,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    try {
      // 通用的BoxFit.cover计算函数
      ui.Rect _calculateCoverRect(ui.Image image, ui.Size targetSize) {
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        // 计算缩放比例
        final scaleX = targetSize.width / imageSize.width;
        final scaleY = targetSize.height / imageSize.height;
        final scale = math.max(scaleX, scaleY); // cover模式取较大的缩放比例

        // 计算缩放后的尺寸
        final scaledWidth = imageSize.width * scale;
        final scaledHeight = imageSize.height * scale;

        // 计算居中偏移
        final offsetX = (targetSize.width - scaledWidth) / 2;
        final offsetY = (targetSize.height - scaledHeight) / 2;

        return ui.Rect.fromLTWH(offsetX, offsetY, scaledWidth, scaledHeight);
      }

      // 如果没有之前的图片（首次显示），从透明开始
      if (imageFrom == imageTo) {
        // 首次显示：简单的透明度渐变，使用BoxFit.cover效果铺满整个画布
        final paint = ui.Paint()
          ..color = Colors.white.withOpacity(progress)
          ..isAntiAlias = true
          ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
            defaultQuality: ui.FilterQuality.high,
          );

        final imageRect = _calculateCoverRect(imageTo, size);

        // 绘制图像
        canvas.drawImageRect(
          imageTo,
          ui.Rect.fromLTWH(
              0, 0, imageTo.width.toDouble(), imageTo.height.toDouble()),
          imageRect,
          paint,
        );
        return;
      }

      // 差分切换：使用dissolve效果，但我们需要手动绘制两个图像并应用BoxFit.cover
      // 而不是直接使用shader，因为shader会拉伸图像

      // 计算两个图像的显示区域
      final fromRect = _calculateCoverRect(imageFrom, size);
      final toRect = _calculateCoverRect(imageTo, size);

      // 先绘制fromImage
      final fromPaint = ui.Paint()
        ..color = Colors.white.withOpacity(1.0 - progress)
        ..isAntiAlias = true
        ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
          defaultQuality: ui.FilterQuality.high,
        );

      canvas.drawImageRect(
        imageFrom,
        ui.Rect.fromLTWH(
            0, 0, imageFrom.width.toDouble(), imageFrom.height.toDouble()),
        fromRect,
        fromPaint,
      );

      // 再绘制toImage
      final toPaint = ui.Paint()
        ..color = Colors.white.withOpacity(progress)
        ..isAntiAlias = true
        ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
          defaultQuality: ui.FilterQuality.high,
        );

      canvas.drawImageRect(
        imageTo,
        ui.Rect.fromLTWH(
            0, 0, imageTo.width.toDouble(), imageTo.height.toDouble()),
        toRect,
        toPaint,
      );
    } catch (e) {
      print("Error painting CG dissolve shader: $e");
    }
  }

  @override
  bool shouldRepaint(covariant CgDissolvePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        imageFrom != oldDelegate.imageFrom ||
        imageTo != oldDelegate.imageTo;
  }
}

/// 同步CG显示组件，只在首次显示时等待所有图层准备好
class SynchronizedCgDisplay extends StatefulWidget {
  final List<CharacterLayerInfo> layerInfos;
  final String resourceId;
  final bool isFadingOut;

  const SynchronizedCgDisplay({
    super.key,
    required this.layerInfos,
    required this.resourceId,
    this.isFadingOut = false,
  });

  @override
  State<SynchronizedCgDisplay> createState() => _SynchronizedCgDisplayState();
}

class _SynchronizedCgDisplayState extends State<SynchronizedCgDisplay> {
  static final Set<String> _displayedCgs = <String>{}; // 跟踪已经显示过的CG
  bool _isFirstDisplay = false;
  bool _allLayersReady = false;
  final Map<String, bool> _layerReadyStatus = {};
  bool _canShowLayers = false; // 控制是否可以显示图层的标志

  @override
  void initState() {
    super.initState();
    _isFirstDisplay = !_displayedCgs.contains(widget.resourceId);

    //print('[SynchronizedCgDisplay] 初始化 ${widget.resourceId}, 是否首次显示: $_isFirstDisplay');

    // 修复：无论首次显示还是非首次显示，都直接允许显示图层，避免过渡动画中的空白
    _allLayersReady = true;
    _canShowLayers = true;

    // 标记这个CG已经显示过了，避免后续的同步等待
    if (_isFirstDisplay) {
      _displayedCgs.add(widget.resourceId);
    }

    //print('[SynchronizedCgDisplay] 直接允许显示，跳过同步等待');
  }

  void _onLayerReady(String layerType) {
    // 已经跳过同步等待逻辑，这个方法现在不需要做任何事情
    return;
  }

  @override
  Widget build(BuildContext context) {
    //print('[SynchronizedCgDisplay] 构建Widget - 可以显示图层: $_canShowLayers');

    // 根据解析结果创建图层组件，使用resourceId和图层类型作为key，保持差分动画
    final layers = widget.layerInfos.map((layerInfo) {
      return CgCharacterLayer(
        key: ValueKey('cg_${widget.resourceId}-${layerInfo.layerType}'),
        assetName: layerInfo.assetName,
        isFadingOut: widget.isFadingOut,
        onReady:
            _isFirstDisplay ? () => _onLayerReady(layerInfo.layerType) : null,
        // 使用标志来控制显示
        showImmediately: _canShowLayers,
      );
    }).toList();

    // CG角色直接返回层叠的图层，不使用pose配置的位置，而是铺满整个屏幕
    return Stack(
      fit: StackFit.expand, // 铺满整个屏幕
      children: layers,
    );
  }
}
