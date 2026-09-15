import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

typedef DownloadsDirectoryResolver = Future<Directory?> Function();

/// Persists the developer file-log preference and mirrors the engine's live
/// debug log into a crash-resilient file in the Downloads directory.
class GameFileLogger extends ChangeNotifier {
  static final GameFileLogger _instance = GameFileLogger._();

  factory GameFileLogger() => _instance;

  GameFileLogger._({
    bool? isSupportedOverride,
    DownloadsDirectoryResolver? downloadsDirectoryResolver,
    bool persistPreference = true,
    String projectName = 'SakiEngine',
  }) : _isSupportedOverride = isSupportedOverride,
       _downloadsDirectoryResolver =
           downloadsDirectoryResolver ?? getDownloadsDirectory,
       _persistPreference = persistPreference,
       _projectName = projectName;

  @visibleForTesting
  factory GameFileLogger.forTesting({
    required Directory downloadsDirectory,
    String projectName = 'SakiEngine',
    bool isSupported = true,
    bool persistPreference = false,
    DownloadsDirectoryResolver? downloadsDirectoryResolver,
  }) {
    return GameFileLogger._(
      isSupportedOverride: isSupported,
      downloadsDirectoryResolver:
          downloadsDirectoryResolver ?? () async => downloadsDirectory,
      persistPreference: persistPreference,
      projectName: projectName,
    );
  }

  static const bool defaultEnabled = false;
  static const String _preferenceKey = 'sakiengine.developer.fileLogging';

  final bool? _isSupportedOverride;
  final DownloadsDirectoryResolver _downloadsDirectoryResolver;
  final bool _persistPreference;

  final UnifiedGameDataManager _dataManager = UnifiedGameDataManager();

  String _projectName;
  Future<void> _pendingOperation = Future<void>.value();
  Future<void>? _initialization;
  RandomAccessFile? _output;
  final List<String> _consoleLinesPendingDebugEntry = [];
  bool _enabled = defaultEnabled;
  bool _globalErrorHandlersInstalled = false;
  String? _currentLogFilePath;
  Object? _lastStartError;

  bool get isEnabled => _enabled;
  bool get isSupported =>
      _isSupportedOverride ??
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  bool get isWriting => _output != null;
  String? get currentLogFilePath => _currentLogFilePath;
  Object? get lastStartError => _lastStartError;

  Future<void> initialize({List<String> legacyPreferenceKeys = const []}) {
    return _initialization ??= _initialize(legacyPreferenceKeys);
  }

  Future<void> _initialize(List<String> legacyPreferenceKeys) async {
    if (_persistPreference) {
      await SettingsManager().init();
      _projectName = await ProjectInfoManager().getAppName();
      final variables = _dataManager.getAllBoolVariables();
      if (!variables.containsKey(_preferenceKey)) {
        for (final key in legacyPreferenceKeys) {
          if (variables.containsKey(key)) {
            await _dataManager.setBoolVariable(
              _preferenceKey,
              variables[key]!,
              _projectName,
            );
            break;
          }
        }
      }
      _enabled = _dataManager.getBoolVariable(
        _preferenceKey,
        defaultValue: defaultEnabled,
      );
    }

    if (_enabled) {
      await _startWriting();
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) {
    final operation = _pendingOperation.then((_) => _setEnabled(enabled));
    _pendingOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _setEnabled(bool enabled) async {
    await initialize();
    if (_enabled == enabled && (enabled == isWriting || !isSupported)) {
      return;
    }

    _enabled = enabled;
    if (_persistPreference) {
      await _dataManager.setBoolVariable(_preferenceKey, enabled, _projectName);
    }

    if (!isSupported) {
      notifyListeners();
      return;
    }

    if (enabled) {
      await _startWriting();
    } else {
      _lastStartError = null;
      await _stopWriting();
    }
    notifyListeners();
  }

  /// Installs wrappers around Flutter's two global uncaught-error paths.
  /// Existing engine handlers are preserved so error presentation and process
  /// termination behavior remain unchanged.
  void installGlobalErrorHandlers() {
    if (_globalErrorHandlersInstalled) {
      return;
    }
    _globalErrorHandlersInstalled = true;

    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      recordUncaughtError(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'FlutterError',
      );
      if (previousFlutterErrorHandler != null) {
        previousFlutterErrorHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
          recordUncaughtError(error, stackTrace, source: 'PlatformDispatcher');
          return previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
        };
  }

  void recordUncaughtError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    if (!isWriting) {
      return;
    }
    _writeLine(
      '[${_formatEntryTimestamp(DateTime.now())}] '
      '[UNCAUGHT][$source] $error',
    );
    for (final line in stackTrace.toString().split(RegExp(r'\r?\n'))) {
      if (line.isNotEmpty) {
        _writeLine('    $line');
      }
    }
  }

  /// Compatibility hook for hosts mirroring console output themselves.
  /// The corresponding DebugLogger entry is skipped to avoid duplication.
  void recordConsoleLine(String line) {
    if (!isWriting) {
      return;
    }
    _consoleLinesPendingDebugEntry.add(line);
    if (_consoleLinesPendingDebugEntry.length > DebugLogger.maxLogs * 2) {
      _consoleLinesPendingDebugEntry.removeAt(0);
    }
    _writeLine('[${_formatEntryTimestamp(DateTime.now())}] $line');
  }

  Future<void> _startWriting() async {
    if (!isSupported || _output != null) {
      return;
    }

    try {
      final downloadsDirectory = await _downloadsDirectoryResolver();
      if (downloadsDirectory == null) {
        throw const FileSystemException('Downloads directory is unavailable');
      }
      await downloadsDirectory.create(recursive: true);

      final now = DateTime.now();
      final safeName = _projectName.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final file = File(
        '${downloadsDirectory.path}${Platform.pathSeparator}'
        '${safeName.isEmpty ? 'SakiEngine' : safeName}-log-${_formatFileTimestamp(now)}.log',
      );
      final output = file.openSync(mode: FileMode.writeOnlyAppend);
      _output = output;
      _currentLogFilePath = file.path;
      _lastStartError = null;

      if (output.lengthSync() == 0) {
        output.writeFromSync(utf8.encode('\ufeff'));
      }
      _writeLine('$_projectName live game log');
      _writeLine('Started: ${now.toIso8601String()}');
      _writeLine('Platform: ${Platform.operatingSystemVersion}');
      _writeLine('Every entry is flushed immediately for crash diagnosis.');
      _writeLine('');
      if (!isWriting) {
        return;
      }

      final debugLogger = DebugLogger.instance;
      debugLogger.addEntryListener(_handleDebugLogEntry);
      for (final entry in debugLogger.logs) {
        _writeLine(entry);
      }
    } catch (error) {
      _lastStartError = error;
      _currentLogFilePath = null;
      DebugLogger.instance.removeEntryListener(_handleDebugLogEntry);
      final output = _output;
      _output = null;
      if (output != null) {
        try {
          output.closeSync();
        } catch (_) {}
      }
    }
  }

  void _handleDebugLogEntry(String entry) {
    if (!isWriting) return;
    final pendingIndex = _consoleLinesPendingDebugEntry.indexOf(
      _debugEntryMessage(entry),
    );
    if (pendingIndex >= 0) {
      _consoleLinesPendingDebugEntry.removeAt(pendingIndex);
    } else {
      _writeLine(entry);
    }
  }

  String _debugEntryMessage(String entry) {
    final timestampEnd = entry.indexOf('] ');
    if (timestampEnd < 0) {
      return entry;
    }
    return entry.substring(timestampEnd + 2);
  }

  void _writeLine(String line) {
    final output = _output;
    if (output == null) {
      return;
    }
    try {
      output.writeFromSync(utf8.encode('$line\r\n'));
      output.flushSync();
    } catch (error) {
      _lastStartError = error;
      _output = null;
      _currentLogFilePath = null;
      DebugLogger.instance.removeEntryListener(_handleDebugLogEntry);
      _consoleLinesPendingDebugEntry.clear();
      try {
        output.closeSync();
      } catch (_) {}
      scheduleMicrotask(notifyListeners);
    }
  }

  Future<void> _stopWriting() async {
    DebugLogger.instance.removeEntryListener(_handleDebugLogEntry);

    final output = _output;
    if (output == null) {
      _currentLogFilePath = null;
      _consoleLinesPendingDebugEntry.clear();
      return;
    }
    _writeLine('');
    _writeLine('File logging disabled: ${DateTime.now().toIso8601String()}');
    _output = null;
    _currentLogFilePath = null;
    _consoleLinesPendingDebugEntry.clear();
    try {
      output.flushSync();
      output.closeSync();
    } catch (error) {
      _lastStartError = error;
    }
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _pendingOperation;
    _enabled = false;
    await _stopWriting();
  }

  String _formatFileTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}-'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}-'
        '${value.millisecond.toString().padLeft(3, '0')}'
        '${value.microsecond.toString().padLeft(3, '0')}';
  }

  String _formatEntryTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}.'
        '${value.millisecond.toString().padLeft(3, '0')}';
  }
}
