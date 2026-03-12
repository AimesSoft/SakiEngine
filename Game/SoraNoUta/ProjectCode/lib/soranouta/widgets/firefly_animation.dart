import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;

class FireflyAnimation extends StatefulWidget {
  final int fireflyCount;
  final double maxRadius;
  final double minRadius;
  final double maxSpeed;
  final double minSpeed;

  const FireflyAnimation({
    super.key,
    this.fireflyCount = 15,
    this.maxRadius = 3.0,
    this.minRadius = 1.5,
    this.maxSpeed = 0.5,
    this.minSpeed = 0.2,
  });

  @override
  State<FireflyAnimation> createState() => _FireflyAnimationState();
}

class _FireflyAnimationState extends State<FireflyAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<Firefly> fireflies;
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

    // 初始化萤火虫
    fireflies = List.generate(widget.fireflyCount, (index) {
      // 创建更多样的大小分布
      final sizeVariation = random.nextDouble();
      double radius;
      if (sizeVariation < 0.3) {
        // 30% 小萤火虫
        radius = widget.minRadius + (widget.maxRadius - widget.minRadius) * 0.2;
      } else if (sizeVariation < 0.7) {
        // 40% 中等萤火虫  
        radius = widget.minRadius + (widget.maxRadius - widget.minRadius) * 0.5;
      } else {
        // 30% 大萤火虫
        radius = widget.minRadius + (widget.maxRadius - widget.minRadius) * (0.7 + random.nextDouble() * 0.3);
      }
      
      return Firefly(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: radius,
        speed: widget.minSpeed + random.nextDouble() * (widget.maxSpeed - widget.minSpeed),
        direction: random.nextDouble() * 2 * pi,
        opacity: 0.4 + random.nextDouble() * 0.6, // 增加亮度变化范围
        pulsePhase: random.nextDouble() * 2 * pi,
      );
    });

    _controller.addListener(() {
      setState(() {
        _updateFireflies();
      });
    });
  }

  void _updateFireflies() {
    for (var firefly in fireflies) {
      // 更新位置 - 更慢的移动
      firefly.x += cos(firefly.direction) * firefly.speed * 0.005; // 减少移动步长
      firefly.y += sin(firefly.direction) * firefly.speed * 0.005;

      // 边界处理 - 循环移动
      if (firefly.x > 1.0) firefly.x = 0.0;
      if (firefly.x < 0.0) firefly.x = 1.0;
      if (firefly.y > 1.0) firefly.y = 0.0;
      if (firefly.y < 0.0) firefly.y = 1.0;

      // 随机改变方向 - 大幅减少方向变化频率
      if (random.nextDouble() < 0.005) { // 从0.02降到0.005
        firefly.direction += (random.nextDouble() - 0.5) * 0.3; // 减少变化幅度
      }

      // 脉冲效果 - 更慢的闪烁
      firefly.pulsePhase += 0.03; // 从0.1降到0.03
      firefly.currentOpacity = firefly.opacity * (0.2 + 0.8 * sin(firefly.pulsePhase).abs());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FireflyPainter(fireflies),
      child: Container(),
    );
  }
}

class Firefly {
  double x;
  double y;
  double radius;
  double speed;
  double direction;
  double opacity;
  double pulsePhase;
  double currentOpacity = 1.0;

  Firefly({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.direction,
    required this.opacity,
    required this.pulsePhase,
  });
}

class FireflyPainter extends CustomPainter {
  final List<Firefly> fireflies;

  FireflyPainter(this.fireflies);

  @override
  void paint(Canvas canvas, Size size) {
    for (var firefly in fireflies) {
      final center = Offset(firefly.x * size.width, firefly.y * size.height);
      
      // 根据萤火虫大小调整光晕范围
      final haloRadius = firefly.radius * (3.0 + firefly.radius * 0.8); // 大萤火虫有更大光晕
      
      // 创建径向渐变画笔
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          haloRadius,
          [
            Colors.white.withOpacity(firefly.currentOpacity * 0.8),
            Colors.white.withOpacity(firefly.currentOpacity * 0.6),
            Colors.white.withOpacity(firefly.currentOpacity * 0.3),
            Colors.transparent,
          ],
          [0.0, 0.3, 0.7, 1.0],
        );

      // 绘制光晕
      canvas.drawCircle(center, haloRadius, paint);

      // 绘制核心光点 - 大小也相应调整
      final corePaint = Paint()
        ..color = Colors.white.withOpacity(firefly.currentOpacity * 0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, firefly.radius * 0.8);
      
      canvas.drawCircle(center, firefly.radius * 0.8, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}