import 'package:sakiengine/src/localization/localization_manager.dart';

/// 提供脚本目录的多语言解析与回退能力。
class GameScriptLocalization {
  static const String _baseDirectory = 'GameScript';
  static const String _assetPrefix = 'assets/';
  static const String _baseAssetPrefix = 'assets/GameScript';

  static const Map<SupportedLanguage, String> _languageDirectories = {
    SupportedLanguage.zhHans: _baseDirectory,
    SupportedLanguage.zhHant: 'GameScript_zh-Hant',
    SupportedLanguage.en: 'GameScript_en',
    SupportedLanguage.ja: 'GameScript_ja',
  };

  static final Set<String> _variantDirectories = _languageDirectories.values
      .where((value) => value != _baseDirectory)
      .toSet();

  /// 返回指定语言对应的脚本目录名称。
  static String directoryFor(SupportedLanguage language) {
    return _languageDirectories[language] ?? _baseDirectory;
  }

  /// 根据当前语言返回候选目录，首选当前语言，其次回退到默认目录。
  static List<String> candidateDirectories({SupportedLanguage? language}) {
    final lang = language ?? LocalizationManager().currentLanguage;
    final resolved = directoryFor(lang);
    if (resolved == _baseDirectory) {
      return const [_baseDirectory];
    }
    return [resolved, _baseDirectory];
  }

  /// 判断路径是否已经指向了变体目录，避免重复转换。
  static bool _isVariantPath(String path) {
    for (final variant in _variantDirectories) {
      if (path.startsWith('$_assetPrefix$variant')) {
        return true;
      }
    }
    return false;
  }

  /// 解析资源文件路径，返回按照语言优先级排列的候选路径列表。
  static List<String> resolveAssetPaths(String originalPath,
      {SupportedLanguage? language}) {
    if (!originalPath.startsWith(_baseAssetPrefix) ||
        _isVariantPath(originalPath)) {
      return [originalPath];
    }

    final suffix = originalPath.substring(_baseAssetPrefix.length);
    final candidates = <String>[];
    final seen = <String>{};
    for (final directory in candidateDirectories(language: language)) {
      final candidate = '$_assetPrefix$directory$suffix';
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  /// 解析资源目录路径，返回按照语言优先级排列的候选目录列表。
  static List<String> resolveAssetDirectories(String originalDirectory,
      {SupportedLanguage? language}) {
    final normalizedOriginal = originalDirectory.replaceAll('\\', '/');
    // 仅 GameScript 目录需要本地化回退；图片/音频等目录应保持原路径。
    if (!normalizedOriginal.startsWith(_baseAssetPrefix) ||
        _isVariantPath(normalizedOriginal)) {
      return [originalDirectory];
    }

    final suffix = normalizedOriginal.substring(_baseAssetPrefix.length);
    final candidates = <String>[];
    final seen = <String>{};
    for (final directory in candidateDirectories(language: language)) {
      final candidate = '$_assetPrefix$directory$suffix';
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  /// 将 `assets/` 前缀去掉，用于文件系统路径解析。
  static String stripAssetsPrefix(String path) {
    if (path.startsWith(_assetPrefix)) {
      return path.substring(_assetPrefix.length);
    }
    return path;
  }
}
