import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
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
  final String? currentDialogue;
  final Function(String pose, String expression) onSelectionChanged;
  final VoidCallback onClose;

  const ExpressionSelectorDialog({
    Key? key,
    required this.characterId,
    required this.characterName,
    required this.currentPose,
    required this.currentExpression,
    this.currentDialogue,
    required this.onSelectionChanged,
    required this.onClose,
  }) : super(key: key);

  @override
  State<ExpressionSelectorDialog> createState() => _ExpressionSelectorDialogState();
}

class _ExpressionSelectorDialogState extends State<ExpressionSelectorDialog> {
  List<ExpressionOption> _poses = [];
  List<ExpressionOption> _expressions = [];
  bool _isLoading = true;
  String _selectedPose = '';
  String _selectedExpression = '';

  @override
  void initState() {
    super.initState();
    _selectedPose = widget.currentPose;
    _selectedExpression = widget.currentExpression;
    _loadCharacterLayers();
  }

  Widget _buildLayeredPreview() {
    // 使用 Stack 叠加图层，类似游戏中的角色渲染
    final layers = <Widget>[];
    
    // 基础层：姿势
    if (_selectedPose.isNotEmpty) {
      final poseAssetName = 'characters/${widget.characterId}-$_selectedPose';
      layers.add(
        SmartAssetImage(
          key: ValueKey('pose_${widget.characterId}_$_selectedPose'),
          assetName: poseAssetName,
          fit: BoxFit.contain,
        ),
      );
    }
    
    // 表情层：差分叠加
    if (_selectedExpression.isNotEmpty) {
      final expressionAssetName = 'characters/${widget.characterId}-$_selectedExpression';
      layers.add(
        SmartAssetImage(
          key: ValueKey('expression_${widget.characterId}_$_selectedExpression'),
          assetName: expressionAssetName,
          fit: BoxFit.contain,
        ),
      );
    }
    
    if (layers.isEmpty) {
      return Center(
        child: Text(
          '无预览',
          style: SakiEngineConfig().dialogueTextStyle.copyWith(
            fontSize: SakiEngineConfig().dialogueTextStyle.fontSize! * 
                context.scaleFor(ComponentType.text) * 0.5,
            color: SakiEngineConfig().themeColors.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }
    
    // 使用Stack叠加所有图层，和游戏中的渲染效果一样
    return Stack(
      key: ValueKey('preview_${widget.characterId}_${_selectedPose}_$_selectedExpression'),
      fit: StackFit.expand,
      children: layers,
    );
  }

  Future<void> _loadCharacterLayers() async {
    try {
      // 使用新的递归搜索方法，和游戏的findAsset使用相同逻辑
      final layers = await AssetManager.getAvailableCharacterLayersRecursive(widget.characterId);
      
      final poses = <ExpressionOption>[];
      final expressions = <ExpressionOption>[];
      
      for (final layer in layers) {
        // 判断是pose还是expression - 基于文件名内容而不是"-"数量
        if (layer.startsWith('pose') || layer.contains('pose')) {
          // 这是pose（姿势）
          poses.add(ExpressionOption(
            name: layer,
            displayName: _formatDisplayName(layer),
            layerLevel: 0,
          ));
        } else {
          // 这是expression（表情差分）
          // 解析层级 - 基于开头的"-"数量
          int dashCount = 0;
          for (int i = 0; i < layer.length; i++) {
            if (layer[i] == '-') {
              dashCount++;
            } else {
              break;
            }
          }
          final layerLevel = dashCount > 0 ? dashCount : 1;
          
          expressions.add(ExpressionOption(
            name: layer,
            displayName: _formatDisplayName(layer),
            layerLevel: layerLevel,
          ));
        }
      }
      
      // 按层级和名称排序
      poses.sort((a, b) => a.displayName.compareTo(b.displayName));
      expressions.sort((a, b) {
        final levelCompare = a.layerLevel.compareTo(b.layerLevel);
        if (levelCompare != 0) return levelCompare;
        return a.displayName.compareTo(b.displayName);
      });
      
      setState(() {
        _poses = poses;
        _expressions = expressions;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDisplayName(String name) {
    // 简单的格式化：将下划线转为空格，首字母大写
    return name.split('_')
        .map((word) => word.isNotEmpty 
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : word)
        .join(' ');
  }

  void _applySelection(String pose, String expression) {
    setState(() {
      _selectedPose = pose;
      _selectedExpression = expression;
    });
    
    // 立即应用更改并关闭对话框
    widget.onSelectionChanged(pose, expression);
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

  Widget _buildLoadingContent(SakiEngineConfig config, double uiScale, double textScale) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: config.themeColors.primary,
          ),
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

  Widget _buildContent(SakiEngineConfig config, double uiScale, double textScale) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：选项列表
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当前台词显示
              if (widget.currentDialogue != null && widget.currentDialogue!.isNotEmpty) ...[
                _buildSectionTitle('当前台词', config, textScale),
                SizedBox(height: 8 * uiScale),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12 * uiScale),
                  decoration: BoxDecoration(
                    color: config.themeColors.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8 * uiScale),
                    border: Border.all(
                      color: config.themeColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.currentDialogue!,
                    style: config.dialogueTextStyle.copyWith(
                      fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.5,
                      color: config.themeColors.onSurface,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: 16 * uiScale),
              ],
              
              if (_poses.isNotEmpty) ...[
                _buildSectionTitle('姿势 (Poses)', config, textScale),
                SizedBox(height: 8 * uiScale),
                _buildPoseList(config, uiScale, textScale),
                SizedBox(height: 16 * uiScale),
              ],
              
              if (_expressions.isNotEmpty) ...[
                _buildSectionTitle('表情差分 (Expressions)', config, textScale),
                SizedBox(height: 8 * uiScale),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildExpressionList(config, uiScale, textScale),
                  ),
                ),
                SizedBox(height: 16 * uiScale),
              ],
              
              if (_poses.isEmpty && _expressions.isEmpty) ...[
                Expanded(
                  child: Center(
                    child: Text(
                      '未找到可用的差分数据',
                      style: config.dialogueTextStyle.copyWith(
                        fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                        color: config.themeColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ],
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

  Widget _buildPreviewSection(SakiEngineConfig config, double uiScale, double textScale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('预览', config, textScale),
        SizedBox(height: 8 * uiScale),
        Expanded(
          child: Container(
            key: ValueKey('preview_container_${_selectedPose}_$_selectedExpression'),
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
              child: _buildLayeredPreview(),
            ),
          ),
        ),
        SizedBox(height: 8 * uiScale),
        Text(
          '当前选择: $_selectedPose / $_selectedExpression',
          style: config.dialogueTextStyle.copyWith(
            fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.4,
            color: config.themeColors.primary,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 12 * uiScale),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _applySelection(_selectedPose, _selectedExpression),
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

  Widget _buildSectionTitle(String title, SakiEngineConfig config, double textScale) {
    return Text(
      title,
      style: config.reviewTitleTextStyle.copyWith(
        fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.6,
        color: config.themeColors.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPoseList(SakiEngineConfig config, double uiScale, double textScale) {
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
                    onPressed: () => _applySelection(pose.name, _selectedExpression),
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

  Widget _buildExpressionList(SakiEngineConfig config, double uiScale, double textScale) {
    return Wrap(
      spacing: 8 * uiScale,
      runSpacing: 8 * uiScale,
      children: _expressions.map((expression) {
        final isSelected = expression.name == _selectedExpression;
        
        return SizedBox(
          width: 120 * uiScale,
          height: 120 * uiScale,
          child: Column(
            children: [
              Expanded(
                child: _buildOptionTile(
                  title: expression.displayName,
                  subtitle: 'Layer ${expression.layerLevel}',
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedExpression = expression.name;
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
                  onPressed: () => _applySelection(_selectedPose, expression.name),
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
      }).toList(),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
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
          borderRadius: BorderRadius.circular(config.baseWindowBorder * 0.5),
          child: Padding(
            padding: EdgeInsets.all(12 * uiScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.5,
                    color: isSelected 
                        ? config.themeColors.primary
                        : config.themeColors.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                SizedBox(height: 2 * uiScale),
                Text(
                  subtitle,
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.4,
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
