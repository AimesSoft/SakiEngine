import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/core/game_module.dart';
import 'package:sakiengine/src/core/project_module_loader.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

/// 对话框中提示下一句话的箭头组件
class DialogueNextArrow extends StatefulWidget {
  final bool visible;
  final double fontSize;
  final Color? color;
  final String? speaker;
  final String? speakerAlias; // 新增：角色简写
  
  const DialogueNextArrow({
    super.key,
    required this.visible,
    required this.fontSize,
    this.color,
    this.speaker,
    this.speakerAlias, // 新增：角色简写参数
  });

  @override
  State<DialogueNextArrow> createState() => _DialogueNextArrowState();
}

class _DialogueNextArrowState extends State<DialogueNextArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2400), // 改为2.4秒，让每个90度旋转约600ms
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    final config = SakiEngineConfig();
    // 深色模式下使用亮色，浅色模式下使用深色
    final defaultColor = SettingsManager().currentDarkMode 
        ? Colors.white.withValues(alpha: 0.8)  // 深色模式用白色
        : config.themeColors.primary.withValues(alpha: 0.7);  // 浅色模式用主题色
    final effectiveColor = widget.color ?? defaultColor;
    final size = widget.fontSize*1.6;

    return FutureBuilder<GameModule>(
      future: moduleLoader.getCurrentModule(),
      builder: (context, snapshot) {
        // 默认显示箭头，避免闪烁
        if (!snapshot.hasData) {
          return _buildArrow(effectiveColor, size);
        }
        final module = snapshot.data!;
        final shouldShowUnderscore = module.shouldUseUnderscoreNextArrow(
          speaker: widget.speaker,
          speakerAlias: widget.speakerAlias,
        );

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            if (shouldShowUnderscore) {
              return _buildUnderscore(effectiveColor, size);
            } else {
              return _buildArrow(effectiveColor, size);
            }
          },
        );
      },
    );
  }

  /// 构建下划线（改为循环箭头）
  Widget _buildUnderscore(Color effectiveColor, double size) {
    // 计算旋转角度 - 每个周期分为4个90度旋转，每次旋转后停顿
    final double cycleValue = _animationController.value * 4; // 0-4的范围，对应4个90度旋转
    final int stepIndex = cycleValue.floor(); // 当前在第几个步骤 (0,1,2,3)
    final double stepProgress = cycleValue - stepIndex; // 当前步骤内的进度 (0.0-1.0)
    
    // 发条式动画：前60%时间快速旋转，后40%时间停顿
    double rotationProgress;
    double scaleProgress;
    
    if (stepProgress < 0.4) {
      // 旋转阶段：使用easeOutCubic让旋转有冲劲然后减速
      final double t = stepProgress / 0.6;
      rotationProgress = 1 - (1 - t) * (1 - t) * (1 - t);
      
      // 缩放动画：开始膨胀，然后压缩，最后弹回
      if (t < 0.3) {
        // 前30%：膨胀阶段 (1.0 -> 1.2)
        scaleProgress = 1.0 + (t / 0.3) * 0.2;
      } else if (t < 0.7) {
        // 中40%：压缩阶段 (1.2 -> 0.85)
        final double compressT = (t - 0.3) / 0.4;
        scaleProgress = 1.2 - compressT * 0.35;
      } else {
        // 后30%：弹回阶段 (0.85 -> 1.0)
        final double bounceT = (t - 0.7) / 0.3;
        // 使用弹性缓动
        final double elasticBounce = 1 - (1 - bounceT) * (1 - bounceT) * (1 - bounceT);
        scaleProgress = 0.85 + elasticBounce * 0.15;
      }
    } else {
      // 停顿阶段：保持完成状态
      rotationProgress = 1.0;
      scaleProgress = 1.0;
    }
        
    // 计算实际旋转角度（每次旋转90度）
    final double rotation = (stepIndex + rotationProgress) * 90 * (pi / 180);
    
    return Transform.scale(
      scale: scaleProgress,
      child: Transform.rotate(
        angle: rotation,
        child: Icon(
          Icons.autorenew_rounded,
          color: effectiveColor,
          size: size*0.75, // 稍微小一点以匹配原来的下划线大小
        ),
      ),
    );
  }

  /// 构建箭头
  Widget _buildArrow(Color effectiveColor, double size) {
    final breathOffset = sin(_animationController.value * 2.0 * pi) * 4.0; // 左右移动4像素
    return Transform.translate(
      offset: Offset(breathOffset, 0),
      child: Icon(
        Icons.keyboard_arrow_right_rounded,
        color: effectiveColor,
        size: size,
      ),
    );
  }
}
