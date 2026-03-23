import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/gestures.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';

class GameStyleScrollView extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const GameStyleScrollView({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  State<GameStyleScrollView> createState() => _GameStyleScrollViewState();
}

class _GameStyleScrollViewState extends State<GameStyleScrollView>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showScrollbar = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final bool shouldShow = _scrollController.hasClients && 
        _scrollController.position.maxScrollExtent > 0;
    
    if (shouldShow != _showScrollbar) {
      setState(() {
        _showScrollbar = shouldShow;
      });
      
      if (_showScrollbar) {
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return CustomScrollView(
      controller: _scrollController,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      physics: widget.physics ?? const BouncingScrollPhysics(),
      shrinkWrap: widget.shrinkWrap,
      slivers: [
        SliverPadding(
          padding: widget.padding ?? EdgeInsets.zero,
          sliver: SliverToBoxAdapter(
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

// 自定义滚动条主题
class GameStyleScrollbarTheme extends StatelessWidget {
  final Widget child;
  
  const GameStyleScrollbarTheme({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return ScrollbarTheme(
      data: ScrollbarThemeData(
        // 滚动条轨道样式
        trackColor: WidgetStateProperty.all(
          config.themeColors.surface.withOpacity(0.3),
        ),
        trackBorderColor: WidgetStateProperty.all(
          config.themeColors.primary.withOpacity(0.2),
        ),
        trackVisibility: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) || 
              states.contains(WidgetState.dragged)) {
            return true;
          }
          return false;
        }),
        
        // 滚动条滑块样式
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return config.themeColors.primary.withOpacity(0.9);
          } else if (states.contains(WidgetState.hovered)) {
            return config.themeColors.primary.withOpacity(0.7);
          }
          return config.themeColors.primary.withOpacity(0.5);
        }),
        
        // 滚动条尺寸和位置
        thickness: WidgetStateProperty.all(6 * scale), // 减小厚度
        radius: Radius.circular(3 * scale),
        
        // 滚动条边距 - 增加右侧边距避免遮挡内容
        crossAxisMargin: -32 * scale, // 增加边距
        mainAxisMargin: 12 * scale,
        
        // 最小滑块长度
        minThumbLength: 48 * scale,
        
        // 交互反馈
        interactive: true,
        
        // 滚动条位置
        thumbVisibility: WidgetStateProperty.resolveWith((states) {
          // 只在悬停或拖拽时显示
          return states.contains(WidgetState.hovered) || 
                 states.contains(WidgetState.dragged);
        }),
      ),
      child: child,
    );
  }
}

// 带有游戏风格滚动条的SingleChildScrollView
class GameStyleSingleChildScrollView extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final DragStartBehavior dragStartBehavior;

  const GameStyleSingleChildScrollView({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.dragStartBehavior = DragStartBehavior.start,
  });

  @override
  State<GameStyleSingleChildScrollView> createState() => _GameStyleSingleChildScrollViewState();
}

class _GameStyleSingleChildScrollViewState extends State<GameStyleSingleChildScrollView>
    with TickerProviderStateMixin {
  late ScrollController _controller;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));

    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _glowController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isScrolling) {
      setState(() {
        _isScrolling = true;
      });
      _glowController.forward();
      
      // 停止滚动后淡出发光效果
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _isScrolling) {
          setState(() {
            _isScrolling = false;
          });
          _glowController.reverse();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: _glowAnimation.value > 0 ? [
              BoxShadow(
                color: config.themeColors.primary.withOpacity(
                  _glowAnimation.value * 0.1,
                ),
                blurRadius: 8 * scale * _glowAnimation.value,
                spreadRadius: 2 * scale * _glowAnimation.value,
              ),
            ] : null,
          ),
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: widget.scrollDirection,
            reverse: widget.reverse,
            padding: widget.padding,
            primary: widget.primary,
            physics: widget.physics ?? const BouncingScrollPhysics(),
            dragStartBehavior: widget.dragStartBehavior,
            child: widget.child,
          ),
        );
      },
    );
  }
}

// 便捷的扩展方法
extension GameStyleScrollExtension on Widget {
  Widget withGameStyleScroll({
    ScrollController? controller,
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    EdgeInsetsGeometry? padding,
    bool? primary,
    ScrollPhysics? physics,
  }) {
    return GameStyleSingleChildScrollView(
      controller: controller,
      scrollDirection: scrollDirection,
      reverse: reverse,
      padding: padding,
      primary: primary,
      physics: physics,
      child: this,
    );
  }
}