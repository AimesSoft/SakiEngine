import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

/// Engine-level hard frame limiter.
///
/// It throttles frame requests at SchedulerBinding level by gating
/// [scheduleFrame], so frame timing/FPS overlay reflects the configured cap.
class SakiEngineFrameRateBinding extends WidgetsFlutterBinding {
  static SakiEngineFrameRateBinding? _instance;

  static SakiEngineFrameRateBinding ensureInitialized() {
    if (_instance == null) {
      SakiEngineFrameRateBinding();
    }
    return _instance!;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  final SettingsManager _settingsManager = SettingsManager();

  bool _settingsListenerAttached = false;
  Timer? _deferredFrameTimer;
  bool _hasDeferredFrameRequest = false;
  int _frameRateLimit = SettingsManager.defaultFrameRateLimit;
  int _nextAllowedFrameAtUs = 0;
  final Stopwatch _clock = Stopwatch()..start();

  int _normalizeFrameRateLimit(int value) {
    switch (value) {
      case 0:
      case 10:
      case 20:
      case 30:
      case 60:
        return value;
      default:
        return SettingsManager.defaultFrameRateLimit;
    }
  }

  int _frameIntervalUs(int fps) {
    final interval = (1000000 / fps).round();
    if (interval < 1000) {
      return 1000;
    }
    return interval;
  }

  int _nowUs() => _clock.elapsedMicroseconds;

  void attachSettingsSync() {
    if (_settingsListenerAttached) {
      _applyFrameRateLimit(_settingsManager.currentFrameRateLimit);
      return;
    }
    _settingsListenerAttached = true;
    _settingsManager.addListener(_handleSettingsChanged);
    _applyFrameRateLimit(_settingsManager.currentFrameRateLimit);
  }

  void _handleSettingsChanged() {
    _applyFrameRateLimit(_settingsManager.currentFrameRateLimit);
  }

  void _applyFrameRateLimit(int value) {
    final normalized = _normalizeFrameRateLimit(value);
    if (_frameRateLimit == normalized) {
      return;
    }
    _frameRateLimit = normalized;
    _nextAllowedFrameAtUs = 0;
    _hasDeferredFrameRequest = false;
    _deferredFrameTimer?.cancel();
    _deferredFrameTimer = null;
    super.scheduleFrame();
  }

  @override
  void scheduleFrame() {
    if (_frameRateLimit <= 0) {
      super.scheduleFrame();
      return;
    }

    final nowUs = _nowUs();
    if (nowUs >= _nextAllowedFrameAtUs) {
      _nextAllowedFrameAtUs = nowUs + _frameIntervalUs(_frameRateLimit);
      _hasDeferredFrameRequest = false;
      _deferredFrameTimer?.cancel();
      _deferredFrameTimer = null;
      super.scheduleFrame();
      return;
    }

    _hasDeferredFrameRequest = true;
    _scheduleDeferredFrameAt(_nextAllowedFrameAtUs - nowUs);
  }

  void _scheduleDeferredFrameAt(int remainingUs) {
    if (_deferredFrameTimer != null && _deferredFrameTimer!.isActive) {
      return;
    }

    final delay = remainingUs <= 0
        ? const Duration(milliseconds: 1)
        : Duration(microseconds: remainingUs);
    _deferredFrameTimer = Timer(delay, _flushDeferredFrame);
  }

  void _flushDeferredFrame() {
    _deferredFrameTimer = null;
    if (!_hasDeferredFrameRequest) {
      return;
    }

    if (_frameRateLimit <= 0) {
      _hasDeferredFrameRequest = false;
      super.scheduleFrame();
      return;
    }

    final nowUs = _nowUs();
    if (nowUs < _nextAllowedFrameAtUs) {
      _scheduleDeferredFrameAt(_nextAllowedFrameAtUs - nowUs);
      return;
    }

    _hasDeferredFrameRequest = false;
    _nextAllowedFrameAtUs = nowUs + _frameIntervalUs(_frameRateLimit);
    super.scheduleFrame();
  }
}
