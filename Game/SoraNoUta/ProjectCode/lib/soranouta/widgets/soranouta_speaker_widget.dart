import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

/// 说话人名字显示组件
class SoranoutaSpeakerWidget extends StatefulWidget {
  final String? speaker;
  final TextStyle speakerStyle;
  final double screenWidth;
  final double screenHeight;
  final double uiScale;
  final double speakerXPos;
  final double speakerYPos;
  final bool enableAnimation;
  final Animation<double>? wipeAnimation;

  const SoranoutaSpeakerWidget({
    super.key,
    required this.speaker,
    required this.speakerStyle,
    required this.screenWidth,
    required this.screenHeight,
    required this.uiScale,
    required this.speakerXPos,
    required this.speakerYPos,
    this.enableAnimation = false,
    this.wipeAnimation,
  });

  @override
  State<SoranoutaSpeakerWidget> createState() => _SoranoutaSpeakerWidgetState();
}

class _SoranoutaSpeakerWidgetState extends State<SoranoutaSpeakerWidget> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: (widget.screenWidth * 0.85) * widget.speakerXPos + 16 * widget.uiScale,
      bottom: 16 * widget.uiScale + 
          (widget.screenHeight * 0.35 / 1.5) * (1.0 - widget.speakerYPos),
      child: FractionalTranslation(
        translation: const Offset(0.0, 0.5),
        child: Opacity(
          opacity: (widget.speaker != null && widget.speaker!.isNotEmpty) ? 1.0 : 0.0,
          child: widget.enableAnimation && widget.wipeAnimation != null
              ? AnimatedBuilder(
                  animation: widget.wipeAnimation!,
                  builder: (context, child) {
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: (widget.speaker != null && widget.speaker!.isNotEmpty)
                            ? widget.wipeAnimation!.value
                            : 0.0,
                        child: Text(
                          widget.speaker ?? ' ',
                          style: widget.speakerStyle,
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : Text(
                  widget.speaker ?? ' ',
                  style: widget.speakerStyle,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                ),
        ),
      ),
    );
  }
}