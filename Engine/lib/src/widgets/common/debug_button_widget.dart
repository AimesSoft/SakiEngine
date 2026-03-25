import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

class DebugButtonWidget extends StatefulWidget {
  final VoidCallback onPressed;
  final double scale;
  final SakiEngineConfig config;

  const DebugButtonWidget({
    super.key,
    required this.onPressed,
    required this.scale,
    required this.config,
  });

  @override
  State<DebugButtonWidget> createState() => _DebugButtonWidgetState();
}

class _DebugButtonWidgetState extends State<DebugButtonWidget> {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Positioned(
      bottom: screenSize.height * 0.05,
      left: screenSize.width * 0.02,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovering) => setState(() {}),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * widget.scale,
              vertical: 12 * widget.scale,
            ),
            decoration: BoxDecoration(
              color: widget.config.themeColors.background.withOpacity(0.85),
              border: Border.all(
                color: widget.config.themeColors.primary.withOpacity(0.6),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_applications,
                  color: widget.config.themeColors.primary,
                  size: 20 * widget.scale,
                ),
                SizedBox(width: 8 * widget.scale),
                Text(
                  '调试',
                  style: TextStyle(
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 16 * widget.scale,
                    color: widget.config.themeColors.primary,
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