import 'package:flutter/material.dart';

/// Reveals [child] from its bottom edge while keeping that edge stationary.
class BottomUpReveal extends StatelessWidget {
  final double progress;
  final Widget child;

  const BottomUpReveal({
    super.key,
    required this.progress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
    return ClipRect(
      // Keep the same subtree when the reveal completes. At full height the
      // clip is disabled so rotations and other paint overflow stay visible.
      clipBehavior: normalizedProgress >= 1.0 ? Clip.none : Clip.hardEdge,
      child: Align(
        alignment: Alignment.bottomCenter,
        widthFactor: 1.0,
        heightFactor: normalizedProgress,
        child: child,
      ),
    );
  }
}
