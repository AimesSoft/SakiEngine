import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/effects/mouse_parallax.dart';

class SceneLayer {
  final String assetName;
  final LayerPosition? position;
  
  SceneLayer({
    required this.assetName,
    this.position,
  });
  
  static SceneLayer? fromString(String layerString) {
    if (layerString.contains(':')) {
      final parts = layerString.split(':');
      final assetName = parts[0];
      final positionString = parts[1];
      
      final position = LayerPosition.fromString(positionString);
      return SceneLayer(assetName: assetName, position: position);
    } else {
      return SceneLayer(assetName: layerString);
    }
  }
}

class LayerPosition {
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double? width;
  final double? height;
  final double zoom; // 缩放参数，默认1.0
  final double? parallax; // 视差深度（可选）
  
  LayerPosition({
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.width,
    this.height,
    this.zoom = 1.0, // 默认不缩放
    this.parallax,
  });
  
  static LayerPosition? fromString(String positionString) {
    double? left, right, top, bottom, width, height;
    double zoom = 1.0; // 默认缩放
    double? parallax;
    
    final params = positionString.split(' ');
    for (final param in params) {
      if (param.startsWith('left=')) {
        left = double.tryParse(param.substring(5));
      } else if (param.startsWith('right=')) {
        right = double.tryParse(param.substring(6));
      } else if (param.startsWith('top=')) {
        top = double.tryParse(param.substring(4));
      } else if (param.startsWith('bottom=')) {
        bottom = double.tryParse(param.substring(7));
      } else if (param.startsWith('width=')) {
        width = double.tryParse(param.substring(6));
      } else if (param.startsWith('height=')) {
        height = double.tryParse(param.substring(7));
      } else if (param.startsWith('zoom=')) {
        zoom = double.tryParse(param.substring(5)) ?? 1.0;
      } else if (param.startsWith('parallax=')) {
        parallax = double.tryParse(param.substring(9));
      }
    }
    
    return LayerPosition(
      left: left,
      right: right, 
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      zoom: zoom,
      parallax: parallax,
    );
  }
}

class MultiLayerRenderer {
  static Widget buildMultiLayerScene({
    required List<SceneLayer> layers,
    required Size screenSize,
  }) {
    return Stack(
      children: [
        for (var i = 0; i < layers.length; i++)
          _buildLayer(layers[i], screenSize, i, layers.length),
      ],
    );
  }

  static Widget _buildLayer(
    SceneLayer layer,
    Size screenSize,
    int index,
    int totalLayers,
  ) {
    // The base widget is the Image, configured to fill its parent container.
    Widget imageContent = SmartAssetImage(
      assetName: 'backgrounds/${layer.assetName.replaceAll(' ', '-')}',
      fit: BoxFit.cover,
      errorWidget: SmartAssetImage(
        assetName: 'gui/${layer.assetName}',
        errorWidget: Container(
          color: Colors.transparent,
          child: Center(
            child: Text(
              'Missing: ${layer.assetName}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
    );

    final pos = layer.position;
    final parallaxDepth = pos?.parallax ?? _resolveDepth(index, totalLayers);

    // Apply the zoom transformation directly to the image content.
    if (pos != null && pos.zoom != 1.0) {
      imageContent = Transform.scale(
        scale: pos.zoom,
        alignment: _determineScaleAlignment(pos),
        child: imageContent,
      );
    }

    // For a layer with no position info, fill the screen.
    if (pos == null) {
      return Positioned.fill(
        child: ParallaxAware(
          depth: parallaxDepth,
          child: imageContent,
        ),
      );
    }

    Widget finalChild = imageContent;

    // CRITICAL FIX: If no explicit size is defined in the script (width/height are null),
    // the image would use its static, intrinsic size, which is not responsive.
    // To fix this, we provide a default responsive container that scales with the screen height,
    // mirroring the behavior of character sprites.
    if (pos.width == null && pos.height == null) {
      finalChild = SizedBox(
        height: screenSize.height,
        child: finalChild,
      );
    }

    // Position the final widget. If width/height are specified in the script,
    // they will create a responsive container that overrides the default SizedBox.
    return Positioned(
      left: pos.left != null ? screenSize.width * pos.left! : null,
      right: pos.right != null ? screenSize.width * pos.right! : null,
      top: pos.top != null ? screenSize.height * pos.top! : null,
      bottom: pos.bottom != null ? screenSize.height * pos.bottom! : null,
      width: pos.width != null ? screenSize.width * pos.width! : null,
      height: pos.height != null ? screenSize.height * pos.height! : null,
      child: ParallaxAware(
        depth: parallaxDepth,
        child: finalChild,
      ),
    );
  }

  static Alignment _determineScaleAlignment(LayerPosition? pos) {
    if (pos == null) return Alignment.center;
    
    final double y = (pos.top != null) ? -1.0 : (pos.bottom != null) ? 1.0 : 0.0;
    final double x = (pos.left != null) ? -1.0 : (pos.right != null) ? 1.0 : 0.0;

    return Alignment(x, y);
  }

  static double _resolveDepth(int index, int totalLayers) {
    if (totalLayers <= 1) {
      return 0.2;
    }
    final t = index / (totalLayers - 1);
    return 0.15 + t * 0.18;
  }
}
