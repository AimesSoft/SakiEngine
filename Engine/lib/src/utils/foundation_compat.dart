import 'package:flutter/foundation.dart' as foundation;

export 'package:flutter/foundation.dart';

/// 演出模式开关（编译期）：
/// flutter run/build ... --dart-define=SAKI_SHOW_MODE=1
const String _sakiShowModeRaw = String.fromEnvironment(
  'SAKI_SHOW_MODE',
  defaultValue: '',
);
const bool kSakiShowMode =
    _sakiShowModeRaw == '1' || _sakiShowModeRaw == 'true';

/// 引擎统一调试开关（编译期）：
/// - Flutter 原生 Debug 为 true
/// - 演出模式（release/profile）也会返回 true
const bool kEngineDebugMode = foundation.kDebugMode || kSakiShowMode;
