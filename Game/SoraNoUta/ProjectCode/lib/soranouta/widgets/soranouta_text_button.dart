import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class SoranoutaTextButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double scale;

  const SoranoutaTextButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.scale,
  });

  @override
  State<SoranoutaTextButton> createState() => _SoranoutaTextButtonState();
}

class _SoranoutaTextButtonState extends State<SoranoutaTextButton> {
  bool _isHovered = false;
  bool _isPressed = false; // 添加按下状态
  final _uiSoundManager = UISoundManager();

  @override
  Widget build(BuildContext context) {
    final isDarkMode = SettingsManager().currentDarkMode;
    final normalColor = isDarkMode ? Colors.black : Colors.white;
    final hoverColor = isDarkMode ? Colors.white : Colors.black;

    return Container(
      // 增大容器，避免放大时被裁剪（1.15倍需要额外15%空间）
      padding: EdgeInsets.only(
        left: 50 * widget.scale, // 仅左侧预留20单位
        right:20 * widget.scale,
      ),
      child: AnimatedScale(
        scale: _isHovered ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        alignment: Alignment.bottomRight, // 放大锚点设置为右侧
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _isHovered = true);
            _uiSoundManager.playButtonHover();
          },
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) {
              setState(() => _isPressed = false);
              _uiSoundManager.playButtonClick();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: widget.onPressed,
            child: Text(
              widget.text,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'ChillJinshuSongPro_Soft',
                fontSize: 55 * widget.scale,
                color: (_isHovered || _isPressed) ? hoverColor : normalColor,
                fontWeight: FontWeight.normal,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
