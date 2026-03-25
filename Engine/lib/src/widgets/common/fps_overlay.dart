import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';

class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
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
    final textScale = context.scaleFor(ComponentType.text);

    return Positioned(
      top: 12 * uiScale,
      right: 12 * uiScale,
      child: IgnorePointer(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * uiScale,
            vertical: 6 * uiScale,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6 * uiScale),
          ),
          child: Text(
            _fps > 0 ? 'FPS ${_fps.toStringAsFixed(1)}' : 'FPS --',
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: config.dialogueTextStyle.copyWith(
              fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.48,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
