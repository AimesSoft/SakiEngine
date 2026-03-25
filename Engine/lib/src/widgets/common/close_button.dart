import 'dart:io';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class CommonCloseButton extends StatefulWidget {
  final VoidCallback onClose;
  final double scale;

  const CommonCloseButton({
    super.key,
    required this.onClose,
    required this.scale,
  });

  @override
  State<CommonCloseButton> createState() => _CommonCloseButtonState();
}

class _CommonCloseButtonState extends State<CommonCloseButton> {
  final _uiSoundManager = UISoundManager();

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();

    // 移动端按钮尺寸加大
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    final buttonSize = isMobile ? 56.0 : 36.0;
    final iconSize = isMobile ? 32.0 : 20.0;

    return MouseRegion(
      onEnter: (_) => _uiSoundManager.playButtonHover(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _uiSoundManager.playButtonClick();
            widget.onClose();
          },
          borderRadius: BorderRadius.circular(buttonSize * widget.scale / 2),
          child: Container(
            width: buttonSize * widget.scale,
            height: buttonSize * widget.scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.themeColors.primary.withValues(alpha: 0.1),
              border: Border.all(
                color: config.themeColors.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.close,
              color: config.themeColors.primary.withValues(alpha: 0.8),
              size: iconSize * widget.scale,
            ),
          ),
        ),
      ),
    );
  }
}





