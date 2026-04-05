import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

class ConfiguredFrameRateLimiter extends StatefulWidget {
  final Widget child;

  const ConfiguredFrameRateLimiter({super.key, required this.child});

  @override
  State<ConfiguredFrameRateLimiter> createState() =>
      _ConfiguredFrameRateLimiterState();
}

class _ConfiguredFrameRateLimiterState
    extends State<ConfiguredFrameRateLimiter> {
  final SettingsManager _settingsManager = SettingsManager();
  int _frameRateLimit = SettingsManager.defaultFrameRateLimit;

  @override
  void initState() {
    super.initState();
    _settingsManager.addListener(_handleSettingsChanged);
    _loadInitialValue();
  }

  @override
  void dispose() {
    _settingsManager.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  Future<void> _loadInitialValue() async {
    await _settingsManager.init();
    if (!mounted) {
      return;
    }
    setState(() {
      _frameRateLimit = _settingsManager.currentFrameRateLimit;
    });
  }

  void _handleSettingsChanged() {
    if (!mounted) {
      return;
    }
    final next = _settingsManager.currentFrameRateLimit;
    if (next == _frameRateLimit) {
      return;
    }
    setState(() {
      _frameRateLimit = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FrameRateLimiter(
      frameRateLimit: _frameRateLimit,
      child: widget.child,
    );
  }
}

class FrameRateLimiter extends StatefulWidget {
  final int frameRateLimit;
  final Widget child;

  const FrameRateLimiter({
    super.key,
    required this.frameRateLimit,
    required this.child,
  });

  @override
  State<FrameRateLimiter> createState() => _FrameRateLimiterState();
}

class _FrameRateLimiterState extends State<FrameRateLimiter> {
  static const Duration _minimumInterval = Duration(milliseconds: 1);
  Timer? _frameTimer;
  int _activeFrameRateLimit = SettingsManager.defaultFrameRateLimit;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _applyFrameRateLimit(widget.frameRateLimit);
  }

  @override
  void didUpdateWidget(covariant FrameRateLimiter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frameRateLimit != widget.frameRateLimit) {
      _applyFrameRateLimit(widget.frameRateLimit);
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

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

  Duration _frameIntervalFor(int fps) {
    final micros = (1000000 / fps).round();
    final duration = Duration(microseconds: micros);
    if (duration < _minimumInterval) {
      return _minimumInterval;
    }
    return duration;
  }

  void _applyFrameRateLimit(int rawLimit) {
    final normalized = _normalizeFrameRateLimit(rawLimit);
    if (_activeFrameRateLimit == normalized) {
      return;
    }
    _activeFrameRateLimit = normalized;
    _frameTimer?.cancel();
    _frameTimer = null;

    if (normalized <= 0) {
      if (!_tickerEnabled && mounted) {
        setState(() {
          _tickerEnabled = true;
        });
      } else {
        _tickerEnabled = true;
      }
      return;
    }

    if (_tickerEnabled && mounted) {
      setState(() {
        _tickerEnabled = false;
      });
    } else {
      _tickerEnabled = false;
    }

    final interval = _frameIntervalFor(normalized);
    _frameTimer = Timer.periodic(interval, (_) {
      _unlockTickerForSingleFrame();
    });
    _unlockTickerForSingleFrame();
  }

  void _unlockTickerForSingleFrame() {
    if (!mounted || _activeFrameRateLimit <= 0 || _tickerEnabled) {
      return;
    }

    setState(() {
      _tickerEnabled = true;
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeFrameRateLimit <= 0 || !_tickerEnabled) {
        return;
      }
      setState(() {
        _tickerEnabled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: _tickerEnabled, child: widget.child);
  }
}
