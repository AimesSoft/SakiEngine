import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';
import 'package:sakiengine/src/utils/character_expression_layers.dart';
import 'package:sakiengine/src/utils/expression_offset_manager.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/widgets/expression_focus_preview.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';

/// 表情和姿势选项
class ExpressionOption {
  final String name;
  final String displayName;
  final int layerLevel;

  const ExpressionOption({
    required this.name,
    required this.displayName,
    required this.layerLevel,
  });
}

/// 角色差分选择器
/// 使用OverlayScaffold显示，包含图片预览功能
class ExpressionSelectorDialog extends StatefulWidget {
  final String characterId;
  final String characterName;
  final String currentPose;
  final String currentExpression;
  final String? currentAnimation;
  final String? previousDialogue;
  final String? currentDialogue;
  final String? nextDialogue;
  final void Function(String pose, String expression, String? animation)
  onSelectionChanged;
  final VoidCallback onClose;

  const ExpressionSelectorDialog({
    Key? key,
    required this.characterId,
    required this.characterName,
    required this.currentPose,
    required this.currentExpression,
    this.currentAnimation,
    this.previousDialogue,
    this.currentDialogue,
    this.nextDialogue,
    required this.onSelectionChanged,
    required this.onClose,
  }) : super(key: key);

  @override
  State<ExpressionSelectorDialog> createState() =>
      _ExpressionSelectorDialogState();
}

class _ExpressionSelectorDialogState extends State<ExpressionSelectorDialog>
    with TickerProviderStateMixin {
  static const Duration _previewAnimationLoopInterval = Duration(
    milliseconds: 900,
  );
  static const Map<String, double> _previewAnimationBaseProperties = {
    'xcenter': 0.0,
    'ycenter': 0.0,
    'scale': 1.0,
    'alpha': 1.0,
    'rotation': 0.0,
  };

  final ExpressionPreviewMetadataRepository _previewMetadataRepository =
      ExpressionPreviewMetadataRepository();
  List<ExpressionOption> _poses = [];
  List<ExpressionOption> _layer1Expressions = [];
  List<ExpressionOption> _layer2Expressions = [];
  List<String> _animations = [];
  bool _isLoading = true;
  String _selectedPose = '';

  /// 第一层差分名（不含层级前缀），空字符串表示未选择。
  String _selectedLayer1 = '';

  /// 第二层差分名（不含层级前缀），空字符串表示没有第二层。
  String _selectedLayer2 = '';
  String? _selectedAnimation;
  Map<String, double> _previewAnimationProperties = Map.of(
    _previewAnimationBaseProperties,
  );
  CharacterAnimationController? _previewAnimationController;
  int _previewAnimationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedPose = widget.currentPose;
    final current = CharacterExpressionLayers.parse(widget.currentExpression);
    _selectedLayer1 = current.nameAt(1) ?? '';
    _selectedLayer2 = current.nameAt(2) ?? '';
    _selectedAnimation = widget.currentAnimation;
    _loadCharacterLayers();
  }

  /// 当前选择编码出的差分表达式，例如 `happy+--mask`。
  String get _selectedExpression {
    final layers = <CharacterExpressionLayer>[
      if (_selectedLayer1.isNotEmpty)
        CharacterExpressionLayer(
          name: _selectedLayer1,
          level: 1,
          explicit: false,
        ),
      if (_selectedLayer2.isNotEmpty)
        CharacterExpressionLayer(
          name: _selectedLayer2,
          level: 2,
          explicit: true,
        ),
    ];
    return CharacterExpressionLayers(layers: layers).encode();
  }

  /// 层级 1 是 `characters/<id>-<name>`，层级 2 是 `characters/<id>--<name>`。
  String _assetNameForLayer(int level, String name) => level <= 1
      ? 'characters/${widget.characterId}-$name'
      : 'characters/${widget.characterId}-${'-' * (level - 1)}$name';

  /// 高亮某一层时的垫底资源：第一层只垫姿态，第二层再垫上第一层。
  List<String> _baseAssetNamesForLayer(int level) {
    return <String>[
      'characters/${widget.characterId}-$_selectedPose',
      if (level >= 2 && _selectedLayer1.isNotEmpty)
        _assetNameForLayer(1, _selectedLayer1),
    ];
  }

  @override
  void dispose() {
    _previewAnimationGeneration++;
    _previewAnimationController?.dispose();
    _previewMetadataRepository.dispose();
    super.dispose();
  }

  void _selectAnimation(String? animation) {
    setState(() {
      _selectedAnimation = animation;
      _previewAnimationProperties = Map.of(_previewAnimationBaseProperties);
    });
    _restartAnimationPreview();
  }

  void _restartAnimationPreview() {
    final generation = ++_previewAnimationGeneration;
    _previewAnimationController?.dispose();
    _previewAnimationController = null;

    final animation = _selectedAnimation;
    if (animation == null || animation.isEmpty) {
      if (mounted) {
        setState(() {
          _previewAnimationProperties = Map.of(_previewAnimationBaseProperties);
        });
      }
      return;
    }

    final definition = AnimationManager.getAnimation(animation);
    if (definition == null) return;

    unawaited(
      _playAnimationPreviewLoop(
        animation,
        generation: generation,
        shouldLoop: definition.keyframes.isNotEmpty,
      ),
    );
  }

  Future<void> _playAnimationPreviewLoop(
    String animation, {
    required int generation,
    required bool shouldLoop,
  }) async {
    do {
      if (!mounted || generation != _previewAnimationGeneration) return;

      late final CharacterAnimationController controller;
      controller = CharacterAnimationController(
        characterId: 'expression-selector-preview',
        onAnimationUpdate: (properties) {
          if (!mounted ||
              generation != _previewAnimationGeneration ||
              _previewAnimationController != controller) {
            return;
          }
          setState(() {
            _previewAnimationProperties = properties;
          });
        },
      );
      _previewAnimationController = controller;

      try {
        await controller.playAnimation(
          animation,
          this,
          _previewAnimationBaseProperties,
          repeatCount: 1,
        );
      } on TickerCanceled {
        // 切换预览或关闭选择器时，取消上一段动画是预期行为。
        return;
      }

      if (!shouldLoop ||
          !mounted ||
          generation != _previewAnimationGeneration) {
        return;
      }

      // 每轮先回到正常立绘，再留出停顿，避免短动画连续抽动。
      controller.dispose();
      _previewAnimationController = null;
      setState(() {
        _previewAnimationProperties = Map.of(_previewAnimationBaseProperties);
      });

      await Future<void>.delayed(_previewAnimationLoopInterval);
      if (!mounted || generation != _previewAnimationGeneration) return;
    } while (shouldLoop);
  }

  Widget _buildLayeredPreview() {
    final layers = <Widget>[];

    if (_selectedPose.isNotEmpty) {
      layers.add(
        SmartAssetImage(
          key: ValueKey('pose_${widget.characterId}_$_selectedPose'),
          assetName: 'characters/${widget.characterId}-$_selectedPose',
          fit: BoxFit.contain,
        ),
      );
    }

    if (_selectedLayer1.isNotEmpty) {
      layers.add(
        SmartAssetImage(
          key: ValueKey('layer1_${widget.characterId}_$_selectedLayer1'),
          assetName: _assetNameForLayer(1, _selectedLayer1),
          fit: BoxFit.contain,
        ),
      );
    }

    if (_selectedLayer2.isNotEmpty) {
      layers.add(
        SmartAssetImage(
          key: ValueKey('layer2_${widget.characterId}_$_selectedLayer2'),
          assetName: _assetNameForLayer(2, _selectedLayer2),
          fit: BoxFit.contain,
        ),
      );
    }

    if (layers.isEmpty) {
      return Center(
        child: Text(
          '无预览',
          style: SakiEngineConfig().dialogueTextStyle.copyWith(
            fontSize:
                SakiEngineConfig().dialogueTextStyle.fontSize! *
                context.scaleFor(ComponentType.text) *
                0.5,
            color: SakiEngineConfig().themeColors.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }

    return Stack(
      key: ValueKey(
        'preview_${widget.characterId}_${_selectedPose}_$_selectedExpression',
      ),
      fit: StackFit.expand,
      children: layers,
    );
  }

  Widget _buildAnimatedLayeredPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final xOffset = _previewAnimationProperties['xcenter'] ?? 0.0;
        final yOffset = _previewAnimationProperties['ycenter'] ?? 0.0;
        final scale = _previewAnimationProperties['scale'] ?? 1.0;
        final alpha = (_previewAnimationProperties['alpha'] ?? 1.0).clamp(
          0.0,
          1.0,
        );
        final rotation = _previewAnimationProperties['rotation'] ?? 0.0;
        final reveal = (_previewAnimationProperties['reveal'] ?? 1.0).clamp(
          0.0,
          1.0,
        );

        Widget preview = _buildLayeredPreview();
        if (reveal < 1.0) {
          preview = ClipRect(
            clipper: _BottomRevealClipper(reveal.toDouble()),
            child: preview,
          );
        }
        preview = Opacity(opacity: alpha.toDouble(), child: preview);
        preview = Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: preview,
        );
        preview = Transform.rotate(
          angle: rotation,
          alignment: Alignment.center,
          child: preview,
        );
        return Transform.translate(
          offset: Offset(
            xOffset * constraints.maxWidth,
            yOffset * constraints.maxHeight,
          ),
          child: preview,
        );
      },
    );
  }

  Future<void> _loadCharacterLayers() async {
    try {
      await AnimationManager.loadAnimations();
      // 使用新的递归搜索方法，和游戏的findAsset使用相同逻辑
      final layers = await AssetManager.getAvailableCharacterLayersRecursive(
        widget.characterId,
      );

      final poses = <ExpressionOption>[];
      final layer1 = <ExpressionOption>[];
      final layer2 = <ExpressionOption>[];

      for (final layer in layers) {
        if (layer.isEmpty) {
          continue;
        }
        // 姿态只认 `pose` 开头（含 `pose1` 这类）；差分名里出现 "pose"
        // 不应再被误判成姿态。
        if (layer.toLowerCase().startsWith('pose')) {
          poses.add(
            ExpressionOption(
              name: layer,
              displayName: _formatDisplayName(layer),
              layerLevel: 0,
            ),
          );
          continue;
        }

        final tokenLevel = CharacterExpressionLayers.levelOfToken(layer);
        final name = CharacterExpressionLayers.stripPrefixes(layer);
        if (name.isEmpty) {
          continue;
        }
        final option = ExpressionOption(
          name: name,
          displayName: _formatDisplayName(name),
          layerLevel: tokenLevel,
        );
        if (tokenLevel <= 1) {
          layer1.add(option);
        } else if (tokenLevel == 2) {
          layer2.add(option);
        }
      }

      // 同一层可能出现"带前缀"和"裸名字"两种磁盘命名，去重后展示。
      List<ExpressionOption> dedupe(List<ExpressionOption> options) {
        final seen = <String>{};
        final result = <ExpressionOption>[];
        for (final option in options) {
          if (seen.add(option.name)) {
            result.add(option);
          }
        }
        result.sort((a, b) => a.displayName.compareTo(b.displayName));
        return result;
      }

      poses.sort((a, b) => a.displayName.compareTo(b.displayName));
      final layer1Options = dedupe(layer1);
      final layer2Options = dedupe(layer2);
      final animations = AnimationManager.getAnimationNames();
      final currentAnimation = widget.currentAnimation?.trim();
      if (currentAnimation != null &&
          currentAnimation.isNotEmpty &&
          !animations.contains(currentAnimation)) {
        animations.insert(0, currentAnimation);
      }

      if (!mounted) {
        return;
      }
      _preloadPreviewMetadata(
        pose: _selectedPose,
        layer1: _selectedLayer1,
        layer2: _selectedLayer2,
      );
      setState(() {
        _poses = poses;
        _layer1Expressions = layer1Options;
        _layer2Expressions = layer2Options;
        _animations = animations;
        _isLoading = false;
      });
      _restartAnimationPreview();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _preloadPreviewMetadata({
    required String pose,
    required String layer1,
    required String layer2,
  }) {
    if (pose.isEmpty) {
      return;
    }
    for (final level in <int>[if (layer1.isNotEmpty) 1, if (layer2.isNotEmpty) 2]) {
      final name = level == 1 ? layer1 : layer2;
      final (xOffset, yOffset, opacity, scale) = ExpressionOffsetManager()
          .getExpressionOffset(
            characterId: widget.characterId,
            pose: pose,
            layerType: 'expression_layer_$level',
          );
      unawaited(
        _previewMetadataRepository.load(
          baseAssetNames: <String>[
            'characters/${widget.characterId}-$pose',
            if (level >= 2 && layer1.isNotEmpty)
              _assetNameForLayer(1, layer1),
          ],
          overlayAssetName: _assetNameForLayer(level, name),
          expressionTransform: ExpressionPreviewTransform(
            xOffset: xOffset,
            yOffset: yOffset,
            opacity: opacity,
            scale: scale,
          ),
        ),
      );
    }
  }

  String _formatDisplayName(String name) {
    // 简单的格式化：将下划线转为空格，首字母大写
    return name
        .split('_')
        .map(
          (word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : word,
        )
        .join(' ');
  }

  void _applySelection(String pose, String expression) {
    setState(() {
      _selectedPose = pose;
      final layers = CharacterExpressionLayers.parse(expression);
      _selectedLayer1 = layers.nameAt(1) ?? '';
      _selectedLayer2 = layers.nameAt(2) ?? '';
    });

    // 立即应用更改并关闭对话框
    widget.onSelectionChanged(pose, expression, _selectedAnimation);
    widget.onClose();
  }

  /// 用当前两层选择应用更改（供"应用"按钮与双击使用）。
  ///
  /// 两层都为空时写入显式清除标记 `--none`，让脚本改写能把已有的差分摘掉，
  /// 而不是因为表达式为空而跳过这一行。
  void _applySelectionFromLayers(String pose) {
    final expression = _selectedExpression.isEmpty
        ? CharacterExpressionLayers.removalTokensForLevel(2)
        : _selectedExpression;
    setState(() {
      _selectedPose = pose;
    });
    widget.onSelectionChanged(pose, expression, _selectedAnimation);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);

    return OverlayScaffold(
      title: '差分选择器 - ${widget.characterName}',
      onClose: (_) => widget.onClose(),
      content: _isLoading
          ? _buildLoadingContent(config, uiScale, textScale)
          : _buildContent(config, uiScale, textScale),
    );
  }

  Widget _buildLoadingContent(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: config.themeColors.primary),
          SizedBox(height: 16 * uiScale),
          Text(
            '加载差分数据...',
            style: config.dialogueTextStyle.copyWith(
              fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
              color: config.themeColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：选项列表
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 当前台词及前后相邻台词
                if (_hasDialogueContext) ...[
                  _buildSectionTitle('对话上下文', config, textScale),
                  SizedBox(height: 8 * uiScale),
                  _buildDialogueContext(config, uiScale, textScale),
                  SizedBox(height: 16 * uiScale),
                ],

                if (_poses.isNotEmpty) ...[
                  _buildSectionTitle('姿势 (Poses)', config, textScale),
                  SizedBox(height: 8 * uiScale),
                  _buildPoseList(config, uiScale, textScale),
                  SizedBox(height: 16 * uiScale),
                ],

                if (_layer1Expressions.isNotEmpty) ...[
                  _buildSectionTitle(
                    '第一层差分 (Layer 1)',
                    config,
                    textScale,
                  ),
                  SizedBox(height: 8 * uiScale),
                  _buildExpressionLayerGrid(
                    level: 1,
                    options: _layer1Expressions,
                    selectedName: _selectedLayer1,
                    config: config,
                    uiScale: uiScale,
                    textScale: textScale,
                  ),
                  SizedBox(height: 16 * uiScale),
                ],

                if (_layer2Expressions.isNotEmpty) ...[
                  _buildSectionTitle(
                    '第二层差分 (Layer 2 · 叠加在第一层之上)',
                    config,
                    textScale,
                  ),
                  SizedBox(height: 8 * uiScale),
                  _buildExpressionLayerGrid(
                    level: 2,
                    options: _layer2Expressions,
                    selectedName: _selectedLayer2,
                    config: config,
                    uiScale: uiScale,
                    textScale: textScale,
                  ),
                  SizedBox(height: 16 * uiScale),
                ],

                if (_animations.isNotEmpty) ...[
                  _buildSectionTitle('动画 (Animations)', config, textScale),
                  SizedBox(height: 8 * uiScale),
                  _buildAnimationList(config, uiScale, textScale),
                  SizedBox(height: 16 * uiScale),
                ],

                if (_poses.isEmpty &&
                    _layer1Expressions.isEmpty &&
                    _layer2Expressions.isEmpty) ...[
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32 * uiScale),
                      child: Text(
                        '未找到可用的差分数据',
                        style: config.dialogueTextStyle.copyWith(
                          fontSize:
                              config.dialogueTextStyle.fontSize! *
                              textScale *
                              0.6,
                          color: config.themeColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        SizedBox(width: 16 * uiScale),

        // 右侧：预览图片
        Expanded(
          flex: 1,
          child: _buildPreviewSection(config, uiScale, textScale),
        ),
      ],
    );
  }

  bool get _hasDialogueContext =>
      _hasText(widget.previousDialogue) ||
      _hasText(widget.currentDialogue) ||
      _hasText(widget.nextDialogue);

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  Widget _buildDialogueContext(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    return Container(
      key: const ValueKey('expression-dialogue-context'),
      width: double.infinity,
      padding: EdgeInsets.all(8 * uiScale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8 * uiScale),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildDialogueContextLine(
            key: const ValueKey('expression-dialogue-previous'),
            label: '上一句',
            dialogue: widget.previousDialogue,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),
          SizedBox(height: 6 * uiScale),
          _buildDialogueContextLine(
            key: const ValueKey('expression-dialogue-current'),
            label: '当前句',
            dialogue: widget.currentDialogue,
            isCurrent: true,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),
          SizedBox(height: 6 * uiScale),
          _buildDialogueContextLine(
            key: const ValueKey('expression-dialogue-next'),
            label: '下一句',
            dialogue: widget.nextDialogue,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),
        ],
      ),
    );
  }

  Widget _buildDialogueContextLine({
    required Key key,
    required String label,
    required String? dialogue,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
    bool isCurrent = false,
  }) {
    final hasDialogue = _hasText(dialogue);
    return Container(
      key: key,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 10 * uiScale,
        vertical: 8 * uiScale,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? config.themeColors.primary.withOpacity(0.12)
            : config.themeColors.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(6 * uiScale),
        border: isCurrent
            ? Border.all(
                color: config.themeColors.primary.withOpacity(0.55),
                width: 1,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52 * uiScale,
            child: Text(
              label,
              style: config.dialogueTextStyle.copyWith(
                fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.38,
                color: isCurrent
                    ? config.themeColors.primary
                    : config.themeColors.onSurface.withOpacity(0.62),
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(width: 8 * uiScale),
          Expanded(
            child: Text(
              hasDialogue ? dialogue!.trim() : '—',
              style: config.dialogueTextStyle.copyWith(
                fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.46,
                color: hasDialogue
                    ? config.themeColors.onSurface
                    : config.themeColors.onSurface.withOpacity(0.38),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('预览', config, textScale),
        SizedBox(height: 8 * uiScale),
        Expanded(
          child: Container(
            key: ValueKey(
              'preview_container_${_selectedPose}_$_selectedExpression',
            ),
            width: double.infinity,
            decoration: BoxDecoration(
              color: config.themeColors.surface,
              borderRadius: BorderRadius.circular(8 * uiScale),
              border: Border.all(
                color: config.themeColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8 * uiScale),
              child: _buildAnimatedLayeredPreview(),
            ),
          ),
        ),
        SizedBox(height: 8 * uiScale),
        Row(
          children: [
            Expanded(
              child: Text(
                '当前选择: $_selectedPose / '
                '${_selectedExpression.isEmpty ? '无差分' : _selectedExpression}\n'
                '动画: ${_selectedAnimation ?? '无动画'}',
                style: config.dialogueTextStyle.copyWith(
                  fontSize:
                      config.dialogueTextStyle.fontSize! * textScale * 0.4,
                  color: config.themeColors.primary,
                ),
              ),
            ),
            if (_selectedAnimation != null)
              IconButton(
                tooltip: '重新播放动画',
                onPressed: _restartAnimationPreview,
                color: config.themeColors.primary,
                icon: const Icon(Icons.replay),
              ),
          ],
        ),
        SizedBox(height: 12 * uiScale),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () =>
                _applySelection(_selectedPose, _selectedExpression),
            style: ElevatedButton.styleFrom(
              backgroundColor: config.themeColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12 * uiScale),
            ),
            child: Text(
              '应用所有更改',
              style: TextStyle(
                fontSize: 14 * textScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    String title,
    SakiEngineConfig config,
    double textScale,
  ) {
    return Text(
      title,
      style: config.reviewTitleTextStyle.copyWith(
        fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.6,
        color: config.themeColors.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPoseList(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    return Container(
      height: 150 * uiScale,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _poses.length,
        itemBuilder: (context, index) {
          final pose = _poses[index];
          final isSelected = pose.name == _selectedPose;

          return Container(
            width: 120 * uiScale,
            margin: EdgeInsets.only(right: 8 * uiScale),
            child: Column(
              children: [
                Expanded(
                  child: _buildOptionTile(
                    title: pose.displayName,
                    subtitle: 'pose',
                    isSelected: isSelected,
                    onTap: () {
                      _preloadPreviewMetadata(
                        pose: pose.name,
                        layer1: _selectedLayer1,
                        layer2: _selectedLayer2,
                      );
                      setState(() {
                        _selectedPose = pose.name;
                      });
                    },
                    config: config,
                    uiScale: uiScale,
                    textScale: textScale,
                  ),
                ),
                SizedBox(height: 4 * uiScale),
                SizedBox(
                  width: double.infinity,
                  height: 24 * uiScale,
                  child: ElevatedButton(
                    onPressed: () =>
                        _applySelection(pose.name, _selectedExpression),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: config.themeColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 4 * uiScale),
                    ),
                    child: Text(
                      '应用',
                      style: TextStyle(fontSize: 10 * textScale),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 某一层的差分栅格。
  ///
  /// [level] 为 1 时列出基础表情，为 2 时列出叠加层；第二层额外提供"清除"
  /// 项，用来在保留第一层的前提下摘掉叠加层（脚本中写作 `--none`）。
  Widget _buildExpressionLayerGrid({
    required int level,
    required List<ExpressionOption> options,
    required String selectedName,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
  }) {
    final hasClearTile = level >= 2;
    final itemCount = options.length + (hasClearTile ? 1 : 0);

    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 148 * uiScale,
        mainAxisExtent: 176 * uiScale,
        crossAxisSpacing: 8 * uiScale,
        mainAxisSpacing: 8 * uiScale,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final isClearTile = hasClearTile && index == 0;
        if (isClearTile) {
          final isSelected = selectedName.isEmpty;
          return _buildLayerTile(
            title: '清除第二层',
            subtitle: '不叠加任何层',
            preview: const SizedBox.shrink(),
            isSelected: isSelected,
            onTap: () => setState(() => _selectedLayer2 = ''),
            onApply: () {
              setState(() => _selectedLayer2 = '');
              _applySelectionFromLayers(_selectedPose);
            },
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          );
        }

        final option = options[index - (hasClearTile ? 1 : 0)];
        final isSelected = option.name == selectedName;
        return _buildLayerTile(
          title: option.displayName,
          subtitle: level >= 2 ? '叠加层' : '基础表情',
          preview: _selectedPose.isEmpty
              ? const SizedBox.shrink()
              : ExpressionFocusPreview(
                  key: ValueKey(
                    'expression_tile_${widget.characterId}_${_selectedPose}_'
                    '${level}_${option.name}',
                  ),
                  metadataRepository: _previewMetadataRepository,
                  characterId: widget.characterId,
                  pose: _selectedPose,
                  expression: option.name,
                  layerLevel: level,
                  baseLayerAssetNames: _baseAssetNamesForLayer(level),
                  paddingFraction: 0.14,
                ),
          isSelected: isSelected,
          onTap: () {
            setState(() {
              if (level <= 1) {
                _selectedLayer1 = option.name;
              } else {
                _selectedLayer2 = option.name;
              }
            });
          },
          onApply: () {
            setState(() {
              if (level <= 1) {
                _selectedLayer1 = option.name;
              } else {
                _selectedLayer2 = option.name;
              }
            });
            _applySelectionFromLayers(_selectedPose);
          },
          config: config,
          uiScale: uiScale,
          textScale: textScale,
        );
      },
    );
  }

  Widget _buildLayerTile({
    required String title,
    required String subtitle,
    required Widget preview,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onApply,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
  }) {
    return Column(
      children: [
        Expanded(
          child: _buildOptionTile(
            title: title,
            subtitle: subtitle,
            preview: preview,
            isSelected: isSelected,
            onTap: onTap,
            onDoubleTap: onApply,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),
        ),
        SizedBox(height: 4 * uiScale),
        SizedBox(
          width: double.infinity,
          height: 24 * uiScale,
          child: ElevatedButton(
            onPressed: onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: config.themeColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 4 * uiScale),
            ),
            child: Text('应用', style: TextStyle(fontSize: 10 * textScale)),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimationList(
    SakiEngineConfig config,
    double uiScale,
    double textScale,
  ) {
    final animationOptions = <String?>[null, ..._animations];
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180 * uiScale,
        mainAxisExtent: 108 * uiScale,
        crossAxisSpacing: 8 * uiScale,
        mainAxisSpacing: 8 * uiScale,
      ),
      itemCount: animationOptions.length,
      itemBuilder: (context, index) {
        final animation = animationOptions[index];
        final isSelected = animation == _selectedAnimation;
        final definition = animation == null
            ? null
            : AnimationManager.getAnimation(animation);
        final subtitle = animation == null
            ? '清除 an / repeat'
            : definition == null
            ? '未找到动画定义'
            : definition.keyframes.isEmpty
            ? '静态变换'
            : '${definition.keyframes.length} 个关键帧';

        return Column(
          children: [
            Expanded(
              child: _buildOptionTile(
                title: animation ?? '无动画',
                subtitle: subtitle,
                isSelected: isSelected,
                onTap: () => _selectAnimation(animation),
                onDoubleTap: () {
                  _selectAnimation(animation);
                  _applySelection(_selectedPose, _selectedExpression);
                },
                config: config,
                uiScale: uiScale,
                textScale: textScale,
              ),
            ),
            SizedBox(height: 4 * uiScale),
            SizedBox(
              width: double.infinity,
              height: 24 * uiScale,
              child: ElevatedButton(
                onPressed: () {
                  _selectAnimation(animation);
                  _applySelection(_selectedPose, _selectedExpression);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: config.themeColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 4 * uiScale),
                ),
                child: Text('应用', style: TextStyle(fontSize: 10 * textScale)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    Widget? preview,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? config.themeColors.primary.withOpacity(0.2)
            : config.themeColors.surface,
        borderRadius: BorderRadius.circular(config.baseWindowBorder * 0.5),
        border: Border.all(
          color: isSelected
              ? config.themeColors.primary
              : config.themeColors.onSurface.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          borderRadius: BorderRadius.circular(config.baseWindowBorder * 0.5),
          child: Padding(
            padding: EdgeInsets.all(12 * uiScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (preview != null) ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        config.baseWindowBorder * 0.3,
                      ),
                      child: SizedBox.expand(child: preview),
                    ),
                  ),
                  SizedBox(height: 6 * uiScale),
                ],
                Text(
                  title,
                  style: config.dialogueTextStyle.copyWith(
                    fontSize:
                        config.dialogueTextStyle.fontSize! * textScale * 0.5,
                    color: isSelected
                        ? config.themeColors.primary
                        : config.themeColors.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2 * uiScale),
                Text(
                  subtitle,
                  style: config.dialogueTextStyle.copyWith(
                    fontSize:
                        config.dialogueTextStyle.fontSize! * textScale * 0.4,
                    color: config.themeColors.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomRevealClipper extends CustomClipper<Rect> {
  final double progress;

  const _BottomRevealClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      size.height * (1.0 - progress),
      size.width,
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _BottomRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
