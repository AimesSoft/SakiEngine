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
        child: Align(
          alignment: Alignment.topLeft,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 18 * widget.scale,
                top: 14 * widget.scale,
              ),
              child: Container(
                constraints: BoxConstraints(maxWidth: 560 * widget.scale),
                padding: EdgeInsets.symmetric(
                    horizontal: 16 * widget.scale, vertical: 10 * widget.scale),
                decoration: BoxDecoration(
                  color: config.themeColors.background.withValues(alpha: 0.9),
                  borderRadius:
                      BorderRadius.circular(config.baseWindowBorder * 0.7),
                  border: Border.all(
                      color:
                          config.themeColors.primary.withValues(alpha: 0.42)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 8 * widget.scale,
                      offset: Offset(0, 2 * widget.scale),
                    ),
                  ],
                ),
                child: Text(
                  _message,
                  style: config.reviewTitleTextStyle.copyWith(
                    fontSize: config.reviewTitleTextStyle.fontSize! *
                        widget.scale *
                        0.52,
                    color: config.themeColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
