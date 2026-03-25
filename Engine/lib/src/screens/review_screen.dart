import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/close_button.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class ReviewOverlay extends StatefulWidget {
  final List<DialogueHistoryEntry> dialogueHistory;
  final void Function(bool triggeredByOverscroll) onClose;
  final Function(DialogueHistoryEntry)? onJumpToEntry;
  final bool enableBottomScrollClose;

  const ReviewOverlay({
    super.key,
    required this.dialogueHistory,
    required this.onClose,
    this.onJumpToEntry,
    this.enableBottomScrollClose = false,
  });

  @override
  State<ReviewOverlay> createState() => _ReviewOverlayState();
}

class _ReviewOverlayState extends State<ReviewOverlay> {
  final GlobalKey<OverlayScaffoldState> _overlayKey = GlobalKey<OverlayScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final LocalizationManager _localization = LocalizationManager();
  
  // 字体大小百分比 (相对于标题字体大小)
  static const double _titleSizeRatio = 1.0;              // 标题: 100%
  static const double _speakerSizeRatio = 0.56;           // 说话人: 56%
  static const double _dialogueSizeRatio = 0.5;           // 对话内容: 50%
  static const double _indexSizeRatio = 0.44;             // 序号: 44%
  static const double _timestampSizeRatio = 0.39;         // 时间戳: 39%
  static const double _jumpButtonSizeRatio = 0.39;        // 跳转按钮: 39%
  static const double _emptyMainTextSizeRatio = 0.61;     // 空状态主文字: 61%
  static const double _emptySubTextSizeRatio = 0.5;       // 空状态副文字: 50%
  static const double _bottomTextSizeRatio = 0.44;        // 底部统计: 44%

  @override
  void initState() {
    super.initState();
    // 使用 reverse: true 的 ListView，无需额外滚动逻辑
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);

    Widget overlay = OverlayScaffold(
      key: _overlayKey,
      title: _localization.t('review.title'),
      onClose: widget.onClose,
      content: widget.dialogueHistory.isEmpty
          ? _buildEmptyState(uiScale, textScale, config)
          : _buildDialogueList(uiScale, textScale, config),
      footer: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 12 * uiScale),
        decoration: BoxDecoration(
          color: config.themeColors.primary.withValues(alpha: 0.05),
          border: Border(
            top: BorderSide(
              color: config.themeColors.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Center(
          child: Text(
            _localization.t('review.count', params: {'count': widget.dialogueHistory.length.toString()}),
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _bottomTextSizeRatio,
              color: config.themeColors.primary.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ),
    );

    if (!widget.enableBottomScrollClose) {
      return overlay;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        behavior: HitTestBehavior.translucent,
        child: overlay,
      ),
    );
  }

  Widget _buildEmptyState(double uiScale, double textScale, SakiEngineConfig config) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80 * uiScale,
            height: 80 * uiScale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.themeColors.primary.withValues(alpha: 0.1),
              border: Border.all(
                color: config.themeColors.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 36 * uiScale,
              color: config.themeColors.primary.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 24 * uiScale),
          Text(
            _localization.t('review.empty.title'),
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _emptyMainTextSizeRatio,
              color: config.themeColors.primary.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 8 * uiScale),
          Text(
            _localization.t('review.empty.subtitle'),
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _emptySubTextSizeRatio,
              color: config.themeColors.primary.withValues(alpha: 0.5),
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogueList(double uiScale, double textScale, SakiEngineConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 估算每条记录的高度（包括padding和spacing）
        final estimatedItemHeight = (config.reviewTitleTextStyle.fontSize! * textScale * 0.7) * 4 + (20 * uiScale); // 大致估算
        final estimatedTotalHeight = widget.dialogueHistory.length * estimatedItemHeight;
        final availableHeight = constraints.maxHeight - (32 * uiScale); // 减去padding
        
        // 判断内容是否会超出可视区域
        final needsScroll = estimatedTotalHeight > availableHeight;
        
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView.builder(
            controller: _scrollController,
            reverse: needsScroll, // 只有需要滚动时才反转，这样能确保最新记录在可视区域
            padding: EdgeInsets.symmetric(horizontal: 32 * uiScale, vertical: 16 * uiScale),
            itemCount: widget.dialogueHistory.length,
            itemBuilder: (context, index) {
              // 根据是否反转列表来决定索引处理
              final actualIndex = needsScroll 
                  ? widget.dialogueHistory.length - 1 - index  // 反转列表时：最新记录在视觉底部
                  : index;  // 正常列表时：按原始顺序显示
              final entry = widget.dialogueHistory[actualIndex];
              return Column(
                children: [
                  _buildDialogueEntry(entry, actualIndex, uiScale, textScale, config),
                  SizedBox(height: 8 * uiScale),
                ],
              );
            },
          ),
        );
      },
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.enableBottomScrollClose) {
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) {
      return false;
    }

    if (!_isAtLatestEntryWithMetrics(metrics)) {
      return false;
    }

    if (notification is OverscrollNotification) {
      if (_isScrollDeltaTowardsLatest(notification.overscroll, metrics.axisDirection)) {
        _overlayKey.currentState?.close(triggeredByOverscroll: true);
        return true;
      }
    } else if (notification is ScrollUpdateNotification && metrics.outOfRange) {
      final delta = notification.scrollDelta ?? 0.0;
      if (_isScrollDeltaTowardsLatest(delta, metrics.axisDirection)) {
        _overlayKey.currentState?.close(triggeredByOverscroll: true);
        return true;
      }
    }

    return false;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.enableBottomScrollClose) {
      return;
    }

    if (event is! PointerScrollEvent) {
      return;
    }

    if (!_scrollController.hasClients) {
      return;
    }

    final scrollEvent = event as PointerScrollEvent;

    if (scrollEvent.scrollDelta.dy <= 0) {
      return;
    }

    if (_isAtLatestEntry()) {
      _overlayKey.currentState?.close(triggeredByOverscroll: true);
    }
  }

  bool _isAtLatestEntry() {
    if (!_scrollController.hasClients) {
      return true;
    }

    return _isAtLatestEntryWithMetrics(_scrollController.position);
  }

  bool _isAtLatestEntryWithMetrics(ScrollMetrics metrics) {
    const tolerance = 6.0;

    if (metrics.maxScrollExtent <= metrics.minScrollExtent) {
      return true;
    }

    switch (metrics.axisDirection) {
      case AxisDirection.down:
        return metrics.pixels >= metrics.maxScrollExtent - tolerance;
      case AxisDirection.up:
        return metrics.pixels <= metrics.minScrollExtent + tolerance;
      default:
        if (kEngineDebugMode) {
          debugPrint('[ReviewOverlay] Unexpected axisDirection=${metrics.axisDirection}, treating as latest');
        }
        return true;
    }
  }

  bool _isScrollDeltaTowardsLatest(double delta, AxisDirection axisDirection) {
    if (delta == 0) {
      return false;
    }

    switch (axisDirection) {
      case AxisDirection.down:
        return delta > 0;
      case AxisDirection.up:
        return delta < 0;
      default:
        if (kEngineDebugMode) {
          debugPrint('[ReviewOverlay] Unexpected axisDirection=$axisDirection in delta check');
        }
        return delta > 0;
    }
  }

  Widget _buildDialogueEntry(
    DialogueHistoryEntry entry,
    int index,
    double uiScale,
    double textScale,
    SakiEngineConfig config,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20 * uiScale,
        vertical: 12 * uiScale,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号和说话人
          Row(
            children: [
              // 固定宽度的序号区域，确保对齐
              SizedBox(
                width: 40 * uiScale,
                child: Text(
                  '${index + 1}',
                  style: config.reviewTitleTextStyle.copyWith(
                    fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _indexSizeRatio,
                    color: config.themeColors.primary.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              // 说话人（如果有的话）
              if (entry.speaker != null && entry.speaker!.isNotEmpty) ...[
                Expanded(
                  child: Text(
                    entry.speaker!,
                    style: config.reviewTitleTextStyle.copyWith(
                      fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _speakerSizeRatio,
                      fontWeight: FontWeight.w500,
                      color: config.themeColors.primary,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
              // 时间戳
              Text(
                _formatTimestamp(entry.timestamp),
                style: config.reviewTitleTextStyle.copyWith(
                  fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _timestampSizeRatio,
                  color: config.themeColors.primary.withValues(alpha: 0.4),
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.normal,
                ),
              ),
              // 跳转按钮
              if (widget.onJumpToEntry != null) ...[
                SizedBox(width: 12 * uiScale),
                _buildJumpButton(entry, uiScale, textScale, config),
              ],
            ],
          ),
          SizedBox(height: 6 * uiScale),
          
          // 对话内容
          Container(
            padding: EdgeInsets.only(left: entry.speaker != null ? 0 : 16 * uiScale),
            child: Text(
              RichTextParser.cleanText(entry.dialogue),
              style: config.reviewTitleTextStyle.copyWith(
                fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _dialogueSizeRatio,
                color: config.themeColors.onSurface,
                height: 1.6,
                letterSpacing: 0.3,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJumpButton(DialogueHistoryEntry entry, double uiScale, double textScale, SakiEngineConfig config) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onJumpToEntry?.call(entry);
        },
        borderRadius: BorderRadius.circular(0 * uiScale),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8 * uiScale, vertical: 4 * uiScale),
          child: Text(
            _localization.t('review.jumpTo'),
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale * _jumpButtonSizeRatio,
              color: config.themeColors.primary.withValues(alpha: 0.7),
              decoration: TextDecoration.underline,
              decorationColor: config.themeColors.primary.withValues(alpha: 0.5),
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return _localization.t('review.time.now');
    } else if (difference.inHours < 1) {
      return _localization.t('review.time.minutesAgo', params: {'count': difference.inMinutes.toString()});
    } else if (difference.inDays < 1) {
      return _localization.t('review.time.hoursAgo', params: {'count': difference.inHours.toString()});
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}
