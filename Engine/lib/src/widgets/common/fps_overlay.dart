import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';

class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  static const String _tooltipAssetName = 'gui/tooltips.png';
  static const double _tooltipBaseWidth = 88.0;
  static const double _tooltipBaseHeight = 34.0;
  static const double _titleBarHeightBase = 39.0;
  static const double _titleBarHeightScale = 0.84;

  int? _lastVsyncUs;
  int _sampleCount = 0;
  int _intervalSumUs = 0;
  DateTime _lastCommitAt = DateTime.now();
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    bool hasNewSample = false;
    for (final timing in timings) {
      final vsyncUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_lastVsyncUs != null) {
        final intervalUs = vsyncUs - _lastVsyncUs!;
        if (intervalUs > 0) {
          _sampleCount++;
          _intervalSumUs += intervalUs;
          hasNewSample = true;
        }
      }
      _lastVsyncUs = vsyncUs;
    }

    if (!hasNewSample || _sampleCount < 10) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastCommitAt) < const Duration(milliseconds: 500)) {
      return;
    }

    final nextFps = (_sampleCount * 1000000.0) / _intervalSumUs;
    _sampleCount = 0;
    _intervalSumUs = 0;
    _lastCommitAt = now;

    if (!mounted) {
      return;
    }

    setState(() {
      _fps = nextFps;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final tooltipHeight =
        (_tooltipBaseHeight * uiScale).clamp(22.0, 50.0).toDouble();
    final tooltipWidth = tooltipHeight * (_tooltipBaseWidth / _tooltipBaseHeight);
    final rightInset = (12.0 * uiScale).clamp(6.0, 24.0).toDouble();
    final topGap = (8.0 * uiScale).clamp(4.0, 16.0).toDouble();
    final topInset = (12.0 * uiScale).clamp(6.0, 24.0).toDouble();
    final safeTop = MediaQuery.paddingOf(context).top;
    final titleBarHeight =
        (_titleBarHeightBase * uiScale * _titleBarHeightScale)
            .clamp(30.0, 58.0)
            .toDouble();
    final topOffset = safeTop +
        (SettingsManager().currentIsFullscreen
            ? topInset
            : titleBarHeight + topGap);

    return Positioned(
      top: topOffset,
      right: rightInset,
      child: IgnorePointer(
        child: SizedBox(
          width: tooltipWidth,
          height: tooltipHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartAssetImage(
                assetName: _tooltipAssetName,
                fit: BoxFit.contain,
                errorWidget: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6 * uiScale),
                  ),
                ),
              ),
              Center(
                child: Text(
                  _fps > 0 ? 'FPS ${_fps.toStringAsFixed(1)}' : 'FPS --',
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: (tooltipHeight * 0.4).clamp(9.0, 18.0).toDouble(),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF6F2FF),
                    height: 1,
                    shadows: const [
                      Shadow(
                        color: Color(0x99000000),
                        offset: Offset(1, 1),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
