import 'dart:ui' as ui;
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/utils/expression_offset_manager.dart';
import 'package:sakiengine/src/utils/image_loader.dart';
import 'package:sakiengine/src/rendering/image_sampling.dart';

class CharacterCompositeCache {
  CharacterCompositeCache._();
  static final CharacterCompositeCache instance = CharacterCompositeCache._();

  final Map<String, ui.Image> _imageCache = {};
  final Map<String, Future<ui.Image?>> _pendingTasks = {};

  String _buildKey(String resourceId, String pose, String expression) {
    return '$resourceId::$pose::$expression';
  }

  ui.Image? getCached(String resourceId, String pose, String expression) {
    return _imageCache[_buildKey(resourceId, pose, expression)];
  }

  Future<ui.Image?> preload(String resourceId, String pose, String expression) {
    final key = _buildKey(resourceId, pose, expression);
    //print('[CharacterCompositeCache] preload调用 - key: $key');

    final cached = _imageCache[key];
    if (cached != null) {
      //print('[CharacterCompositeCache] 使用缓存图像 - key: $key');
      return SynchronousFuture(cached);
    }

    final pending = _pendingTasks[key];
    if (pending != null) {
      //print('[CharacterCompositeCache] 等待进行中的任务 - key: $key');
      return pending;
    }

    //print('[CharacterCompositeCache] 启动新的合成任务 - key: $key');
    final task = _compose(resourceId, pose, expression).then((image) {
      if (image != null) {
        //print('[CharacterCompositeCache] 合成成功，缓存图像 - key: $key');
        _imageCache[key] = image;
      } else {
        //print('[CharacterCompositeCache] 合成失败 - key: $key');
      }
      _pendingTasks.remove(key);
      return image;
    });

    _pendingTasks[key] = task;
    return task;
  }

  Future<ui.Image?> _compose(
      String resourceId, String pose, String expression) async {
    try {
      //print('[CharacterCompositeCache] 开始合成角色 - resourceId: $resourceId, pose: $pose, expression: $expression');

      final layerInfos = await CharacterLayerParser.parseCharacterLayers(
        resourceId: resourceId,
        pose: pose,
        expression: expression,
      );

      //print('[CharacterCompositeCache] 图层解析完成 - 图层数量: ${layerInfos.length}');

      if (layerInfos.isEmpty) {
        //print('[CharacterCompositeCache] 没有图层信息，返回null');
        return null;
      }

      final images = <_CompositeLayer>[];
      ui.Image? baseImage;

      for (final info in layerInfos) {
        //print('[CharacterCompositeCache] 处理图层: ${info.layerType}, 资源名: ${info.assetName}');

        final assetPath = await AssetManager().findAsset(info.assetName);
        if (assetPath == null) {
          //print('[CharacterCompositeCache] 找不到资源: ${info.assetName}');
          continue;
        }

        final image = await ImageLoader.loadImage(assetPath);
        if (image == null) {
          //print('[CharacterCompositeCache] 图像加载失败: $assetPath');
          continue;
        }

        //print('[CharacterCompositeCache] 图像加载成功: $assetPath');

        final (xOffset, yOffset, alpha, scale) =
            ExpressionOffsetManager().getExpressionOffset(
          characterId: resourceId,
          pose: pose,
          layerType: info.layerType,
        );

        images.add(_CompositeLayer(
          image: image,
          xOffset: xOffset,
          yOffset: yOffset,
          alpha: alpha,
          scale: scale,
        ));

        baseImage ??= image;
      }

      final base = baseImage;
      if (base == null) {
        //print('[CharacterCompositeCache] 没有基础图像，返回null');
        return null;
      }

      //print('[CharacterCompositeCache] 开始Canvas合成 - 基础尺寸: ${base.width}x${base.height}');

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()
        ..isAntiAlias = true
        ..filterQuality = ImageSamplingManager().resolveCanvasFilterQuality(
          defaultQuality: ui.FilterQuality.high,
        );

      final width = base.width.toDouble();
      final height = base.height.toDouble();

      // 保存基础图像的尺寸，用于后续的toImage调用
      final baseWidth = base.width;
      final baseHeight = base.height;

      for (final layer in images) {
        canvas.save();
        final dx = layer.xOffset * width;
        final dy = layer.yOffset * height;
        canvas.translate(dx, dy);
        if (layer.scale != 1.0) {
          canvas.scale(layer.scale, layer.scale);
        }
        paint.color = ui.Color.fromRGBO(
          255,
          255,
          255,
          layer.alpha.clamp(0.0, 1.0),
        );
        canvas.drawImage(layer.image, ui.Offset.zero, paint);
        canvas.restore();
      }

      //print('[CharacterCompositeCache] Canvas绘制完成，开始转换为图像');

      final picture = recorder.endRecording();
      final composed = await picture.toImage(baseWidth, baseHeight);
      picture.dispose();

      // 现在安全地释放所有图层图像
      for (final layer in images) {
        layer.image.dispose();
      }

      //print('[CharacterCompositeCache] 图像合成成功');
      return composed;
    } catch (e, stackTrace) {
      //print('[CharacterCompositeCache] 合成失败: $e');
      //print('[CharacterCompositeCache] 错误堆栈: $stackTrace');
      return null;
    }
  }

  void clear() {
    _imageCache.clear();
    _pendingTasks.clear();
  }

  void invalidate(String resourceId, String pose) {
    final prefix = '$resourceId::$pose::';
    final keysToRemove = _imageCache.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keysToRemove) {
      _imageCache.remove(key);
      _pendingTasks.remove(key);
    }
  }
}

class _CompositeLayer {
  _CompositeLayer({
    required this.image,
    required this.xOffset,
    required this.yOffset,
    required this.alpha,
    required this.scale,
  });

  final ui.Image image;
  final double xOffset;
  final double yOffset;
  final double alpha;
  final double scale;
}
