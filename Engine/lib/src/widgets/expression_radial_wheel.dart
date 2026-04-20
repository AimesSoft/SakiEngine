import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Debug差分快捷轮盘（按住Command弹出）
class ExpressionRadialWheel extends StatefulWidget {
  final String characterName;
  final String currentExpression;
  final List<String> expressions;
  final Offset center;
  final ValueChanged<String> onHighlightedExpressionChanged;

  const ExpressionRadialWheel({
    super.key,
    required this.characterName,
    required this.currentExpression,
    required this.expressions,
    required this.center,
    required this.onHighlightedExpressionChanged,
  });

  @override
  State<ExpressionRadialWheel> createState() => _ExpressionRadialWheelState();
}

class _ExpressionRadialWheelState extends State<ExpressionRadialWheel> {
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    final currentIndex = widget.expressions.indexOf(widget.currentExpression);
    _highlightedIndex = currentIndex >= 0 ? currentIndex : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.expressions.isEmpty) {
        return;
      }
      widget.onHighlightedExpressionChanged(
        widget.expressions[_highlightedIndex],
      );
    });
  }

  @override
  void didUpdateWidget(covariant ExpressionRadialWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expressions.isEmpty) {
      return;
    }
    if (widget.expressions != oldWidget.expressions ||
        widget.currentExpression != oldWidget.currentExpression) {
      final currentIndex = widget.expressions.indexOf(widget.currentExpression);
      final fallbackIndex = _highlightedIndex.clamp(
        0,
        widget.expressions.length - 1,
      );
      _highlightedIndex = currentIndex >= 0 ? currentIndex : fallbackIndex;
      widget.onHighlightedExpressionChanged(
          widget.expressions[_highlightedIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expressions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final center = Offset(
            widget.center.dx.clamp(0.0, size.width),
            widget.center.dy.clamp(0.0, size.height),
          );
          final maxRadiusByEdges = [
            center.dx,
            center.dy,
            size.width - center.dx,
            size.height - center.dy,
          ].reduce(math.min);
          final outerRadius =
              math.max(90.0, math.min(maxRadiusByEdges - 12, 220.0));
          final innerRadius = outerRadius * 0.45;

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) =>
                _updateHighlightFromPointer(event.localPosition, center),
            onPointerMove: (event) =>
                _updateHighlightFromPointer(event.localPosition, center),
            onPointerHover: (event) =>
                _updateHighlightFromPointer(event.localPosition, center),
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _ExpressionRadialWheelPainter(
                    center: center,
                    outerRadius: outerRadius,
                    innerRadius: innerRadius,
                    segmentCount: widget.expressions.length,
                    highlightedIndex: _highlightedIndex,
                  ),
                ),
                ..._buildSegmentLabels(
                  center: center,
                  outerRadius: outerRadius,
                  innerRadius: innerRadius,
                ),
                _buildCenterLabel(center: center, innerRadius: innerRadius),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSegmentLabels({
    required Offset center,
    required double outerRadius,
    required double innerRadius,
  }) {
    final widgets = <Widget>[];
    final count = widget.expressions.length;
    final labelRadius = (outerRadius + innerRadius) * 0.52;
    final step = (math.pi * 2) / count;
    const startAngle = -math.pi / 2;

    for (var i = 0; i < count; i++) {
      final angle = startAngle + (i + 0.5) * step;
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
      final isSelected = i == _highlightedIndex;
      final expression = widget.expressions[i];

      widgets.add(
        Positioned(
          left: position.dx - 56,
          top: position.dy - 12,
          width: 112,
          child: IgnorePointer(
            child: Text(
              expression,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFF0A6) : Colors.white,
                fontSize: isSelected ? 14 : 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                shadows: const [
                  Shadow(
                    blurRadius: 6,
                    color: Colors.black54,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildCenterLabel({
    required Offset center,
    required double innerRadius,
  }) {
    final selectedExpression = widget.expressions[_highlightedIndex];
    return Positioned(
      left: center.dx - innerRadius * 0.9,
      top: center.dy - innerRadius * 0.9,
      width: innerRadius * 1.8,
      height: innerRadius * 1.8,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.24),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.characterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selectedExpression,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Release Command To Apply',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateHighlightFromPointer(Offset localPosition, Offset center) {
    if (widget.expressions.isEmpty) {
      return;
    }

    final offset = localPosition - center;
    final angle = math.atan2(offset.dy, offset.dx);
    final normalized = (angle + math.pi / 2 + math.pi * 2) % (math.pi * 2);
    final step = (math.pi * 2) / widget.expressions.length;
    final index = (normalized ~/ step).clamp(0, widget.expressions.length - 1);
    if (index == _highlightedIndex) {
      return;
    }

    setState(() {
      _highlightedIndex = index;
    });
    widget.onHighlightedExpressionChanged(widget.expressions[index]);
  }
}

class _ExpressionRadialWheelPainter extends CustomPainter {
  final Offset center;
  final double outerRadius;
  final double innerRadius;
  final int segmentCount;
  final int highlightedIndex;

  const _ExpressionRadialWheelPainter({
    required this.center,
    required this.outerRadius,
    required this.innerRadius,
    required this.segmentCount,
    required this.highlightedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segmentCount <= 0) {
      return;
    }

    final sweep = (math.pi * 2) / segmentCount;
    const startAngle = -math.pi / 2;
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    for (var i = 0; i < segmentCount; i++) {
      final from = startAngle + i * sweep;
      final isSelected = i == highlightedIndex;
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? const Color(0xFFDA9D2B).withOpacity(0.78)
            : const Color(0xFF262626).withOpacity(0.82);

      final path = Path()
        ..arcTo(outerRect, from, sweep, false)
        ..arcTo(innerRect, from + sweep, -sweep, false)
        ..close();
      canvas.drawPath(path, fillPaint);
    }

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withOpacity(0.24);
    canvas.drawCircle(center, outerRadius, strokePaint);
    canvas.drawCircle(center, innerRadius, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _ExpressionRadialWheelPainter oldDelegate) {
    return oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.segmentCount != segmentCount ||
        oldDelegate.center != center ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.innerRadius != innerRadius;
  }
}
