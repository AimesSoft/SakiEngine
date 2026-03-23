import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

class NotificationOverlay extends StatefulWidget {
  final double scale;

  const NotificationOverlay({
    super.key,
    required this.scale,
  });

  @override
  State<NotificationOverlay> createState() => NotificationOverlayState();
}

class NotificationOverlayState extends State<NotificationOverlay> {
  bool _show = false;
  String _message = '';
  Timer? _timer;

  final _fadeInOutDuration = const Duration(milliseconds: 50);
  final _displayDuration = const Duration(milliseconds: 500);

  void show(String message) {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
    }

    setState(() {
      _show = true;
      _message = message;
    });

    _timer = Timer(_displayDuration, () {
      setState(() {
        _show = false;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    return IgnorePointer(
      ignoring: !_show,
      child: AnimatedOpacity(
        opacity: _show ? 1.0 : 0.0,
        duration: _fadeInOutDuration,
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 48 * widget.scale, vertical: 32 * widget.scale),
              decoration: BoxDecoration(
                color: config.themeColors.background.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(config.baseWindowBorder * widget.scale),
                border: Border.all(
                    color: config.themeColors.primary.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15 * widget.scale,
                  ),
                ],
              ),
              child: Text(
                _message,
                style: config.reviewTitleTextStyle.copyWith(
                  fontSize:
                      config.reviewTitleTextStyle.fontSize! * widget.scale * 0.8,
                  color: config.themeColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
