import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'dart:ui';
import 'dart:io';
import 'package:sakiengine/src/game/story_flowchart_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/widgets/common/square_icon_button.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/widgets/game_style_dropdown.dart';
import 'package:sakiengine/src/game/save_load_manager.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/widgets/confirm_dialog.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

/// 剧情流程图界面
class StoryFlowchartScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final Function(SaveSlot)? onLoadSave;
  final bool isInGame; // 是否在游戏中（用于区分弹窗提示内容）

  const StoryFlowchartScreen({
    Key? key,
    this.onClose,
    this.onLoadSave,
    this.isInGame = false, // 默认不在游戏中
  }) : super(key: key);

  @override
  State<StoryFlowchartScreen> createState() => _StoryFlowchartScreenState();
}

class _StoryFlowchartScreenState extends State<StoryFlowchartScreen> {
  final StoryFlowchartManager _flowchartManager = StoryFlowchartManager();
  final TransformationController _transformController = TransformationController();
  final UISoundManager _uiSoundManager = UISoundManager();
  final LocalizationManager _localization = LocalizationManager();

  String? _selectedChapter; // 当前选中的章节
  String? _hoveredNodeId; // 当前悬浮的节点ID

  // 节点尺寸常量（用于计算节点中心和偏移）
  static const double _largeNodeWidth = 280.0;
  static const double _smallNodeWidth = 200.0;

  // 估算的节点高度（padding + 内容）
  // 大节点：padding(16*2) + 标题(~20) + 间距(6) + 类型(~18) ≈ 76
  static const double _largeNodeHeight = 76.0;
  // 小节点：padding(10*2) + 单行文本(~18) ≈ 38
  static const double _smallNodeHeight = 38.0;

  @override
  void initState() {
    super.initState();
    _flowchartManager.addListener(_onFlowchartUpdate);
    // 初始化时选择第一个章节并居中视图
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chapters = _getAvailableChapters();
      if (chapters.isNotEmpty && _selectedChapter == null) {
        setState(() {
          _selectedChapter = chapters.first;
        });
      }
      // 将视图居中到画布中心
      _centerView();
    });
  }

  /// 将视图居中到根节点
  void _centerView() {
    // 获取视图尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final viewportSize = renderBox.size;

      // 获取当前章节的根节点
      final currentChapterNodes = _getNodesForCurrentChapter();
      final rootNodes = currentChapterNodes
          .where((node) => node.type == StoryNodeType.chapter)
          .toList();

      if (rootNodes.isEmpty) return;

      // 计算根节点的布局位置
      final layoutInfo = _calculateLayout(rootNodes);
      final rootNode = rootNodes.first;
      final rootLayout = layoutInfo[rootNode.id];

      if (rootLayout == null) return;

      // 默认缩放比例为2倍
      const double defaultScale = 2.0;

      // 获取根节点的中心坐标
      final double rootCenterX = rootLayout['x']! + (_largeNodeWidth / 2);
      final double rootCenterY = rootLayout['y']! + (_largeNodeHeight / 2);

      // 计算需要的平移，使根节点中心对齐到视口中心（考虑缩放）
      final double translateX = -rootCenterX * defaultScale + viewportSize.width / 2;
      final double translateY = -rootCenterY * defaultScale + viewportSize.height / 2;

      _transformController.value = Matrix4.identity()
        ..translate(translateX, translateY)
        ..scale(defaultScale);
    });
  }

  @override
  void dispose() {
    _flowchartManager.removeListener(_onFlowchartUpdate);
    _transformController.dispose();
    super.dispose();
  }

  void _onFlowchartUpdate() {
    setState(() {});
  }

  /// 获取所有可用的章节（只包含有解锁节点的章节）
  List<String> _getAvailableChapters() {
    final allNodes = _flowchartManager.nodes.values;
    final chapterNames = <String>[];

    // 遍历所有章节名称
    final allChapterNames = allNodes
        .where((node) => node.chapterName != null)
        .map((node) => node.chapterName!)
        .toSet()
        .toList();

    // 对每个章节，检查是否有解锁的节点
    for (final chapterName in allChapterNames) {
      final hasUnlockedNodes = allNodes.any((node) =>
        node.chapterName == chapterName && node.isUnlocked
      );

      // 只有包含解锁节点的章节才添加到列表
      if (hasUnlockedNodes) {
        chapterNames.add(chapterName);
      }
    }

    chapterNames.sort();
    return chapterNames;
  }

  /// 获取当前章节的所有节点
  List<StoryFlowNode> _getNodesForCurrentChapter() {
    if (_selectedChapter == null) return [];

    final allNodes = _flowchartManager.nodes.values.toList();
    final nodesMap = {for (var n in allNodes) n.id: n};

    // 递归查找最近的有解锁状态的祖先节点（章节、分支选择、结局）
    bool isAncestorUnlocked(String? nodeId) {
      if (nodeId == null) return false;
      final node = nodesMap[nodeId];
      if (node == null) return false;

      // 如果是分支选项或汇合点，继续向上查找
      final bool isBranchOption = node.metadata != null && node.metadata!.containsKey('branchText');
      final bool isMergePoint = node.type == StoryNodeType.merge;

      if (isBranchOption || isMergePoint) {
        // 汇合点可能有多个父节点
        if (isMergePoint && node.metadata != null) {
          final parentIds = node.metadata!['parentIds'] as List<dynamic>?;
          if (parentIds != null && parentIds.isNotEmpty) {
            // 只要有一个父节点的祖先解锁就返回 true
            return parentIds.any((id) => isAncestorUnlocked(id as String));
          }
        }
        // 分支选项向上查找
        return isAncestorUnlocked(node.parentNodeId);
      }

      // 找到有解锁状态的节点，返回其解锁状态
      return node.isUnlocked;
    }

    return allNodes.where((node) {
      if (node.chapterName != _selectedChapter) return false;

      // 分支选项和汇合点：检查祖先节点是否已解锁
      final bool isBranchOption = node.metadata != null && node.metadata!.containsKey('branchText');
      final bool isMergePoint = node.type == StoryNodeType.merge;

      if (isBranchOption || isMergePoint) {
        return isAncestorUnlocked(node.id);
      }

      // 其他节点：只返回已解锁的节点
      return node.isUnlocked;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);

    return OverlayScaffold(
      title: _localization.t('flowchart.title'),
      onClose: (_) {
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context).pop();
        }
      },
      content: _buildContent(uiScale, textScale),
    );
  }

  /// 构建主要内容
  Widget _buildContent(double uiScale, double textScale) {
    return Stack(
      children: [
        // 流程图主体（全屏）
        _buildFlowchartViewer(uiScale, textScale),

        // 右侧信息面板（顶对齐，毛玻璃背景）
        Positioned(
          top: 0,
          right: 0,
          bottom: 0, // 让面板上下铺满
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // 真正的毛玻璃模糊效果
              child: Container(
                width: 280 * uiScale,
                decoration: BoxDecoration(
                  color: SakiEngineConfig().themeColors.background.withOpacity(0.7), // 半透明背景
                  border: Border(
                    left: BorderSide(
                      color: SakiEngineConfig().themeColors.primary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: _buildInfoPanel(uiScale, textScale),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建流程图查看器
  Widget _buildFlowchartViewer(double uiScale, double textScale) {
    final config = SakiEngineConfig();

    // 只获取当前章节的节点
    final currentChapterNodes = _getNodesForCurrentChapter();
    final rootNodes = currentChapterNodes
        .where((node) => node.type == StoryNodeType.chapter)
        .toList();

    // 计算所有节点的布局信息
    final layoutInfo = _calculateLayout(rootNodes);

    return ClipRect( // 添加裁剪，防止内容超出边界
      child: Container(
        color: Colors.transparent, // 移除黑色遮罩，改为透明
        child: InteractiveViewer(
          transformationController: _transformController,
          // 无边界限制 - 移除boundaryMargin让用户可以无限平移
          constrained: false, // 关键：允许子组件超出视图边界
          minScale: 0.1,
          maxScale: 4.0,
          clipBehavior: Clip.hardEdge, // 改为硬边缘裁剪，防止内容溢出
          child: CustomPaint(
            painter: FlowchartPainter(
              nodes: currentChapterNodes,
              currentNodeId: _flowchartManager.currentNode?.id,
              primaryColor: config.themeColors.primary,
              layoutInfo: layoutInfo, // 传递布局信息
              uiScale: uiScale, // 传递 UI 缩放比例
            ),
            child: SizedBox(
              width: 40000, // 极大的宽度，左右各20000
              height: 40000, // 极大的高度，上下各20000
              child: _buildNodeWidgets(uiScale, textScale, layoutInfo),
            ),
          ),
        ),
      ),
    );
  }

  /// 信息面板
  Widget _buildInfoPanel(double uiScale, double textScale) {
    final currentNode = _flowchartManager.currentNode;
    final unlockedEndings = _flowchartManager.getUnlockedEndingsCount();
    final totalEndings = _flowchartManager.getTotalEndingsCount();
    final config = SakiEngineConfig();
    final availableChapters = _getAvailableChapters();

    return Container(
      padding: EdgeInsets.all(20 * uiScale),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 让面板不垂直拉伸
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节选择下拉菜单
          if (availableChapters.isNotEmpty) ...[
            Text(
              _localization.t('flowchart.selectChapter'),
              style: TextStyle(
                color: config.themeColors.primary,
                fontSize: 18 * textScale,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12 * uiScale),
            GameStyleDropdown<String>(
              items: availableChapters.map((chapter) {
                return GameStyleDropdownItem<String>(
                  value: chapter,
                  label: chapter,
                );
              }).toList(),
              value: _selectedChapter ?? availableChapters.first,
              onChanged: (newChapter) {
                setState(() {
                  _selectedChapter = newChapter;
                });
                _centerView(); // 切换章节后居中视图
              },
              scale: uiScale,
              textScale: textScale,
              config: config,
              width: 240 * uiScale, // 固定宽度，下拉列表会自动匹配
            ),
            SizedBox(height: 24 * uiScale),
          ],

          // 重置视图按钮
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _uiSoundManager.playButtonClick();
                  _centerView();
                },
                onHover: (hovering) {
                  if (hovering) {
                    _uiSoundManager.playButtonHover();
                  }
                },
                hoverColor: config.themeColors.primary.withOpacity(0.1),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12 * uiScale),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: config.themeColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 20 * uiScale,
                        color: config.themeColors.primary,
                      ),
                      SizedBox(width: 8 * uiScale),
                      Text(
                        _localization.t('flowchart.resetView'),
                        style: TextStyle(
                          fontSize: 16 * textScale, // 增大字体
                          color: config.themeColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, double uiScale, double textScale, SakiEngineConfig config) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * uiScale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60 * uiScale,
            child: Text(
              '$label:',
              style: TextStyle(
                color: config.themeColors.primary.withOpacity(0.5),
                fontSize: 15 * textScale, // 增大字体
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: config.themeColors.primary,
                fontSize: 15 * textScale, // 增大字体
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String action, String description, double uiScale, double textScale, SakiEngineConfig config) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * uiScale),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8 * uiScale, vertical: 4 * uiScale),
            decoration: BoxDecoration(
              border: Border.all(
                color: config.themeColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              action,
              style: TextStyle(
                color: config.themeColors.primary,
                fontSize: 13 * textScale, // 增大字体
              ),
            ),
          ),
          SizedBox(width: 8 * uiScale),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: config.themeColors.primary.withOpacity(0.6),
                fontSize: 13 * textScale, // 增大字体
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, double uiScale, double textScale, SakiEngineConfig config) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * uiScale),
      child: Row(
        children: [
          Container(
            width: 20 * uiScale, // 增大图例色块
            height: 20 * uiScale,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: config.themeColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          SizedBox(width: 8 * uiScale),
          Text(
            label,
            style: TextStyle(
              color: config.themeColors.primary.withOpacity(0.8),
              fontSize: 15 * textScale, // 增大字体
            ),
          ),
        ],
      ),
    );
  }

  /// 构建节点组件
  Widget _buildNodeWidgets(double uiScale, double textScale, Map<String, Map<String, double>> layoutInfo) {
    return Stack(
      clipBehavior: Clip.none, // 不裁切超出边界的内容
      children: [
        for (final entry in layoutInfo.entries)
          Positioned(
            left: entry.value['x'] as double,
            top: entry.value['y'] as double,
            child: _buildNodeWidget(
              _flowchartManager.nodes[entry.key]!,
              uiScale,
              textScale,
            ),
          ),
      ],
    );
  }

  /// 计算节点布局（避免重叠，垂直居中对称）
  Map<String, Map<String, double>> _calculateLayout(List<StoryFlowNode> rootNodes) {
    final Map<String, Map<String, double>> layoutInfo = {};
    final Map<int, List<StoryFlowNode>> depthNodes = {}; // 每个深度的节点列表

    // 获取当前章节的所有节点，用于查找子节点
    final currentChapterNodes = _getNodesForCurrentChapter();
    final nodesMap = {for (var n in currentChapterNodes) n.id: n};

    // 第一步：收集每个深度的所有节点
    void collectNodes(StoryFlowNode node, int depth) {
      depthNodes[depth] = depthNodes[depth] ?? [];
      depthNodes[depth]!.add(node);

      // 递归处理子节点
      final children = node.childNodeIds
          .map((id) => nodesMap[id])
          .whereType<StoryFlowNode>()
          .toList();
      for (var child in children) {
        collectNodes(child, depth + 1);
      }
    }

    // 收集所有根节点及其子节点
    for (var root in rootNodes) {
      collectNodes(root, 0);
    }

    // 第二步：计算每个深度的垂直居中位置（使用画布中心作为原点）
    const double canvasCenter = 20000.0; // 画布中心点（40000 / 2）

    for (var entry in depthNodes.entries) {
      final depth = entry.key;
      final nodes = entry.value;
      final nodeCount = nodes.length;

      // 计算垂直居中的起始Y坐标（以画布中心为原点）
      final totalHeight = (nodeCount - 1) * 200.0;
      final startY = canvasCenter - totalHeight / 2; // 以画布中心为基准居中

      for (int i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final double x = canvasCenter + 100 + depth * 400.0; // X也以画布中心为基准
        final double y = startY + i * 200.0;

        layoutInfo[node.id] = {'x': x, 'y': y, 'depth': depth.toDouble()};
      }
    }

    // 第三步：调整小节点的Y坐标，使其中心对齐到大节点的中心
    final double verticalAdjustment = (_largeNodeHeight - _smallNodeHeight) / 2;
    for (var entry in layoutInfo.entries) {
      final node = nodesMap[entry.key];
      if (node != null) {
        final bool isSmallNode = (node.metadata != null && node.metadata!.containsKey('branchText')) ||
                                  node.type == StoryNodeType.merge;
        if (isSmallNode) {
          entry.value['y'] = entry.value['y']! + verticalAdjustment;
        }
      }
    }

    return layoutInfo;
  }

  /// 构建单个节点组件
  Widget _buildNodeWidget(StoryFlowNode node, double uiScale, double textScale) {
    final config = SakiEngineConfig();
    final color = _getNodeColor(node.type, node.isUnlocked, config);
    final isCurrentNode = _flowchartManager.currentNode?.id == node.id;
    final isHovered = _hoveredNodeId == node.id;

    // 判断节点类型
    final bool isBranchOption = node.metadata != null && node.metadata!.containsKey('branchText'); // 分支选项（option_xxx）
    final bool isMergePoint = node.type == StoryNodeType.merge; // 汇合点

    // 只有分支选项和汇合点不可点击
    final bool isClickable = !isBranchOption && !isMergePoint;
    // 只有分支选项和汇合点使用更小的样式
    final bool isSmallNode = isBranchOption || isMergePoint;

    // 不再需要 Transform.translate，因为 y 坐标已经在 layoutInfo 中调整过了
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 主节点容器
        CustomPaint(
          painter: _NotchBorderPainter(
            notchSize: 16 * uiScale,
            borderColor: isCurrentNode
                ? config.themeColors.primary
                : (isBranchOption
                    ? config.themeColors.primary.withOpacity(0.5)
                    : color.withOpacity(node.isUnlocked ? 0.8 : 0.5)),
            borderWidth: isCurrentNode ? 3 : (isSmallNode ? 1.5 : 2),
            isSmallNode: isSmallNode, // 传递小节点标识
          ),
          child: ClipPath(
            clipper: _NotchCornerClipper(
              notchSize: 16 * uiScale,
              isSmallNode: isSmallNode,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isClickable ? () => _onNodeTapped(node) : null,
                onHover: isClickable ? (hovering) {
                  setState(() {
                    _hoveredNodeId = hovering ? node.id : null;
                  });
                  if (hovering) {
                    _uiSoundManager.playButtonHover();
                  }
                } : null,
                hoverColor: isClickable ? config.themeColors.primary.withOpacity(0.1) : Colors.transparent,
                child: Container(
                  width: (isSmallNode ? 200 : 280) * uiScale,
                  padding: EdgeInsets.all(isSmallNode ? 10 * uiScale : 16 * uiScale),
                  decoration: BoxDecoration(
                    // 分支选项使用浅白色背景
                    color: isBranchOption
                        ? config.themeColors.background.withOpacity(0.8)
                        : (node.isUnlocked
                            ? color.withOpacity(0.6)
                            : color.withOpacity(0.3)),
                  ),
                  child: isSmallNode
                      ? // 分支选项和汇合点：单行显示，垂直居中
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            node.displayName,
                            style: TextStyle(
                              // 分支选项使用暗色文字，汇合点使用白色文字
                              color: isBranchOption ? config.themeColors.primary : config.themeColors.background,
                              fontSize: 14 * textScale, // 更小的字体
                              fontWeight: FontWeight.normal, // 不加粗
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : // 章节、分支选择和结局：双行显示
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              node.displayName,
                              style: TextStyle(
                                // 完全不透明的白色
                                color: config.themeColors.background,
                                fontSize: 16 * textScale,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 6 * uiScale),
                            Text(
                              _getNodeTypeText(node.type),
                              style: TextStyle(
                                // 完全不透明的白色
                                color: config.themeColors.background,
                                fontSize: 14 * textScale,
                              ),
                            ),

                            // 只有章节和结局才显示"未解锁"标签
                            if (!node.isUnlocked)
                              Container(
                                margin: EdgeInsets.only(top: 8 * uiScale),
                                padding: EdgeInsets.symmetric(horizontal: 8 * uiScale, vertical: 4 * uiScale),
                                decoration: BoxDecoration(
                                  color: config.themeColors.primary.withOpacity(0.2),
                                  border: Border.all(
                                    color: config.themeColors.background.withOpacity(0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _localization.t('flowchart.unlocked'),
                                  style: TextStyle(
                                    color: config.themeColors.background.withOpacity(0.7),
                                    fontSize: 12 * textScale,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),

        // 可点击节点的悬浮图标（右上角）
        if (isClickable && node.isUnlocked)
          Positioned(
            top: -8 * uiScale,
            right: -8 * uiScale,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: isHovered ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (value * 0.4), // 从0.8放大到1.2
                  child: Transform.rotate(
                    angle: value * 0.2, // 轻微旋转
                    child: Container(
                      width: 32 * uiScale,
                      height: 32 * uiScale,
                      decoration: BoxDecoration(
                        color: config.themeColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: config.themeColors.primary.withOpacity(0.4 + value * 0.3),
                            blurRadius: 8 + (value * 8),
                            spreadRadius: value * 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: config.themeColors.background,
                        size: 20 * uiScale,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 节点点击事件
  Future<void> _onNodeTapped(StoryFlowNode node) async {
    _uiSoundManager.playButtonClick();

    if (!node.isUnlocked) {
      // 未解锁节点，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localization.t('flowchart.notification.nodeUnlocked'),
            style: TextStyle(color: SakiEngineConfig().themeColors.primary),
          ),
          backgroundColor: Colors.black.withOpacity(0.8),
        ),
      );
      return;
    }

    // 显示确认对话框，防止误触
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ConfirmDialog(
          title: _localization.t('flowchart.loadConfirm.title'),
          content: widget.isInGame
              ? _localization.t('flowchart.loadConfirm.inGame', params: {'name': node.displayName})
              : _localization.t('flowchart.loadConfirm.normal', params: {'name': node.displayName}),
          confirmResult: true,
          cancelResult: false,
        );
      },
    );

    if (confirmed != true) {
      return; // 用户取消，不执行加载
    }

    // 从自动存档加载
    if (node.autoSaveId != null && node.autoSaveId!.isNotEmpty) {
      try {
        final saveLoadManager = SaveLoadManager();

        // 构建存档文件路径
        final directory = await saveLoadManager.getSavesDirectory();
        final file = File('$directory/${node.autoSaveId}.sakisav');

        if (await file.exists()) {
          final binaryData = await file.readAsBytes();
          final saveSlot = SaveSlot.fromBinary(binaryData);

          if (kEngineDebugMode) {
            //print('[StoryFlowchart] 从节点 ${node.id} 的自动存档加载成功');
          }

          // 使用 onLoadSave 回调来加载存档（和"继续游戏"一样的方式）
          if (widget.onLoadSave != null) {
            widget.onLoadSave!(saveSlot);
            // onLoadSave 回调内部会关闭流程图并显示通知，这里不需要再调用 onClose
          } else {
            // 如果没有 onLoadSave 回调，则调用 onClose（兼容性）
            if (mounted && widget.onClose != null) {
              widget.onClose!();
            }
          }
        } else {
          if (kEngineDebugMode) {
            //print('[StoryFlowchart] 自动存档文件不存在: ${node.autoSaveId}');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localization.t('flowchart.notification.saveNotFound'),
                style: TextStyle(color: SakiEngineConfig().themeColors.primary),
              ),
              backgroundColor: Colors.black.withOpacity(0.8),
            ),
          );
        }
      } catch (e) {
        if (kEngineDebugMode) {
          //print('[StoryFlowchart] 加载自动存档失败: $e');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localization.t('flowchart.notification.loadFailed', params: {'error': e.toString()}),
              style: TextStyle(color: SakiEngineConfig().themeColors.primary),
            ),
            backgroundColor: Colors.black.withOpacity(0.8),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localization.t('flowchart.notification.noSaveAssociated'),
            style: TextStyle(color: SakiEngineConfig().themeColors.primary),
          ),
          backgroundColor: Colors.black.withOpacity(0.8),
        ),
      );
    }
  }

  /// 获取节点颜色
  Color _getNodeColor(StoryNodeType type, bool isUnlocked, SakiEngineConfig config) {
    final primary = config.themeColors.primary;

    switch (type) {
      case StoryNodeType.chapter:
        return primary.withOpacity(0.8); // 章节用主题色
      case StoryNodeType.branch:
        return Color.lerp(primary, Colors.orange, 0.3)!; // 分支用橙色调
      case StoryNodeType.merge:
        return Color.lerp(primary, Colors.purple, 0.3)!; // 汇合用紫色调
      case StoryNodeType.ending:
        return isUnlocked
            ? Color.lerp(primary, Colors.green, 0.3)! // 已达成结局用绿色调
            : primary.withOpacity(0.2); // 未达成结局用灰色
    }
  }

  /// 获取节点类型文本
  String _getNodeTypeText(StoryNodeType type) {
    switch (type) {
      case StoryNodeType.chapter:
        return _localization.t('flowchart.nodeType.chapter');
      case StoryNodeType.branch:
        return _localization.t('flowchart.nodeType.branch');
      case StoryNodeType.merge:
        return _localization.t('flowchart.nodeType.merge');
      case StoryNodeType.ending:
        return _localization.t('flowchart.nodeType.ending');
    }
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 流程图画笔（绘制连接线）
class FlowchartPainter extends CustomPainter {
  final List<StoryFlowNode> nodes;
  final String? currentNodeId;
  final Color primaryColor;
  final Map<String, Map<String, double>> layoutInfo;
  final double uiScale; // 新增：UI缩放比例

  FlowchartPainter({
    required this.nodes,
    this.currentNodeId,
    required this.primaryColor,
    required this.layoutInfo,
    required this.uiScale, // 新增：接收UI缩放比例
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor.withOpacity(0.3) // 增加线条不透明度，更清晰
      ..strokeWidth = 2.5 // 增粗线条
      ..style = PaintingStyle.stroke;

    // 绘制节点间的连接线
    for (final node in nodes) {
      // 特殊处理汇合点：绘制所有分支到汇合点的连接线
      if (node.type == StoryNodeType.merge && node.metadata != null) {
        final parentIds = node.metadata!['parentIds'] as List<dynamic>?;
        if (parentIds != null && parentIds.isNotEmpty) {
          // 绘制每个父节点到汇合点的连接线
          for (final parentId in parentIds) {
            final parentNode = nodes.firstWhere(
              (n) => n.id == parentId,
              orElse: () => node,
            );
            if (parentNode.id != node.id) {
              _drawConnection(canvas, paint, parentNode, node);
            }
          }
        }
      }
      // 处理普通的父子关系（非汇合点）
      else if (node.parentNodeId != null) {
        final parentNode = nodes.firstWhere(
          (n) => n.id == node.parentNodeId,
          orElse: () => node,
        );

        if (parentNode.id != node.id) {
          _drawConnection(canvas, paint, parentNode, node);
        }
      }
    }
  }

  /// 绘制两个节点之间的连接线
  void _drawConnection(Canvas canvas, Paint paint, StoryFlowNode parentNode, StoryFlowNode childNode) {
    // 使用布局信息获取精确位置
    final parentLayout = layoutInfo[parentNode.id];
    final childLayout = layoutInfo[childNode.id];

    if (parentLayout != null && childLayout != null) {
      // 判断节点是否为小节点
      final bool isParentSmall = (parentNode.metadata != null && parentNode.metadata!.containsKey('branchText')) ||
                                  parentNode.type == StoryNodeType.merge;
      final bool isChildSmall = (childNode.metadata != null && childNode.metadata!.containsKey('branchText')) ||
                                 childNode.type == StoryNodeType.merge;

      // 使用常量定义的节点尺寸，并应用 uiScale
      final double parentWidth = (isParentSmall ? 200.0 : 280.0) * uiScale;
      final double parentHeight = (isParentSmall ? 38.0 : 76.0) * uiScale;
      final double childHeight = (isChildSmall ? 38.0 : 76.0) * uiScale;

      final double x1 = parentLayout['x']! + parentWidth; // 父节点右边缘
      final double y1 = parentLayout['y']! + parentHeight / 2; // 父节点中心
      final double x2 = childLayout['x']!; // 子节点左边缘
      final double y2 = childLayout['y']! + childHeight / 2; // 子节点中心

      // 绘制贝塞尔曲线
      final path = Path();
      path.moveTo(x1, y1);
      path.cubicTo(
        x1 + 50, y1,
        x2 - 50, y2,
        x2, y2,
      );

      canvas.drawPath(path, paint);

      // 在线的终点绘制箭头
      _drawArrow(canvas, x2 - 10, y2, paint);
    }
  }

  void _drawArrow(Canvas canvas, double x, double y, Paint paint) {
    final arrowPaint = Paint()
      ..color = primaryColor.withOpacity(0.5) // 增加箭头不透明度
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(x, y);
    path.lineTo(x - 10, y - 6); // 增大箭头尺寸
    path.lineTo(x - 10, y + 6);
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(FlowchartPainter oldDelegate) {
    return oldDelegate.currentNodeId != currentNodeId ||
        oldDelegate.nodes.length != nodes.length;
  }
}

/// 左上角切角裁剪器
class _NotchCornerClipper extends CustomClipper<Path> {
  final double notchSize;
  final bool isSmallNode;

  _NotchCornerClipper({
    required this.notchSize,
    required this.isSmallNode,
  });

  @override
  Path getClip(Size size) {
    final path = Path();

    if (isSmallNode) {
      // 小节点：左上角 + 右下角双切角
      path.moveTo(notchSize, 0); // 从左上角切角后开始
      path.lineTo(size.width, 0); // 顶边到右上角
      path.lineTo(size.width, size.height - notchSize); // 右边到右下角切角前
      path.lineTo(size.width - notchSize, size.height); // 右下角斜切
      path.lineTo(0, size.height); // 底边到左下角
      path.lineTo(0, notchSize); // 左边到左上角切角前
      path.lineTo(notchSize, 0); // 左上角斜切回起点
    } else {
      // 大节点：只有左上角切角
      path.moveTo(notchSize, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.lineTo(0, notchSize);
      path.lineTo(notchSize, 0);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(_NotchCornerClipper oldClipper) {
    return oldClipper.notchSize != notchSize || oldClipper.isSmallNode != isSmallNode;
  }
}

/// 自定义边框绘制器（绘制切角边框）
class _NotchBorderPainter extends CustomPainter {
  final double notchSize;
  final Color borderColor;
  final double borderWidth;
  final bool isSmallNode;

  _NotchBorderPainter({
    required this.notchSize,
    required this.borderColor,
    required this.borderWidth,
    this.isSmallNode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    final path = Path();

    if (isSmallNode) {
      // 小节点：左上角 + 右下角双切角
      path.moveTo(notchSize, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height - notchSize);
      path.lineTo(size.width - notchSize, size.height);
      path.lineTo(0, size.height);
      path.lineTo(0, notchSize);
      path.lineTo(notchSize, 0);
    } else {
      // 大节点：只有左上角切角
      path.moveTo(notchSize, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.lineTo(0, notchSize);
      path.lineTo(notchSize, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_NotchBorderPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.notchSize != notchSize ||
        oldDelegate.isSmallNode != isSmallNode;
  }
}
