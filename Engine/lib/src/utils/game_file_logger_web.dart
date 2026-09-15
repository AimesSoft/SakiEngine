import 'package:flutter/foundation.dart';

class GameFileLogger extends ChangeNotifier {
  static final GameFileLogger _instance = GameFileLogger._();

  factory GameFileLogger() => _instance;
  GameFileLogger._();

  static const bool defaultEnabled = false;

  bool get isEnabled => false;
  bool get isSupported => false;
  bool get isWriting => false;
  String? get currentLogFilePath => null;
  Object? get lastStartError => null;

  Future<void> initialize({
    List<String> legacyPreferenceKeys = const [],
  }) async {}
  Future<void> setEnabled(bool enabled) async {}
  void installGlobalErrorHandlers() {}
  void recordConsoleLine(String line) {}

  void recordUncaughtError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {}
}
