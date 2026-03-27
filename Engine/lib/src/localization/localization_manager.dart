import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/utils/engine_asset_loader.dart';

enum SupportedLanguage { zhHans, zhHant, en, ja }

extension SupportedLanguageX on SupportedLanguage {
  String get code {
    switch (this) {
      case SupportedLanguage.zhHans:
        return 'zh-Hans';
      case SupportedLanguage.zhHant:
        return 'zh-Hant';
      case SupportedLanguage.en:
        return 'en';
      case SupportedLanguage.ja:
        return 'ja';
    }
  }

  Locale get locale {
    switch (this) {
      case SupportedLanguage.zhHans:
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      case SupportedLanguage.zhHant:
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      case SupportedLanguage.en:
        return const Locale('en');
      case SupportedLanguage.ja:
        return const Locale('ja');
    }
  }

  String get englishName {
    switch (this) {
      case SupportedLanguage.zhHans:
        return 'Simplified Chinese';
      case SupportedLanguage.zhHant:
        return 'Traditional Chinese';
      case SupportedLanguage.en:
        return 'English';
      case SupportedLanguage.ja:
        return 'Japanese';
    }
  }
}

SupportedLanguage? supportedLanguageFromCode(String? code) {
  if (code == null) {
    return null;
  }
  for (final language in SupportedLanguage.values) {
    if (language.code == code) {
      return language;
    }
  }
  return null;
}

class LocalizationManager extends ChangeNotifier {
  static final LocalizationManager _instance = LocalizationManager._internal();
  factory LocalizationManager() => _instance;
  LocalizationManager._internal();

  static const String _translationsAsset = 'assets/i18n/strings.json';
  static const List<String> _translationBundleCandidates = <String>[
    'packages/sakiengine/assets/i18n/strings.json',
    'assets/packages/sakiengine/assets/i18n/strings.json',
    _translationsAsset,
    'i18n/strings.json',
  ];

  final Map<SupportedLanguage, Map<String, String>> _translations = {};
  final _dataManager = UnifiedGameDataManager();
  String? _projectName;
  SupportedLanguage _currentLanguage = SupportedLanguage.zhHans;
  SupportedLanguage _fallbackLanguage = SupportedLanguage.en;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    // 获取项目名称
    try {
      _projectName = await ProjectInfoManager().getAppName();
    } catch (e) {
      _projectName = 'SakiEngine';
    }

    // 初始化数据管理器
    await _dataManager.init(_projectName!);

    await _loadTranslations();

    // 从统一数据管理器读取语言设置
    final savedCode = _dataManager.getStringVariable('sakiengine.language');
    final saved = supportedLanguageFromCode(savedCode);

    if (saved != null && _translations.containsKey(saved)) {
      // 有保存的语言设置，使用保存的语言
      _currentLanguage = saved;
    } else {
      // 第一次启动，根据系统语言自动设置
      _currentLanguage = _detectSystemLanguage();
      // 保存自动检测的语言
      await _dataManager.setStringVariable(
          'sakiengine.language', _currentLanguage.code, _projectName!);
    }

    _initialized = true;
  }

  /// 根据系统语言自动检测并返回最匹配的支持语言
  SupportedLanguage _detectSystemLanguage() {
    // 获取系统语言列表
    final systemLocales = ui.PlatformDispatcher.instance.locales;

    // 遍历系统语言列表，找到第一个匹配的语言
    for (final locale in systemLocales) {
      final languageCode = locale.languageCode.toLowerCase();
      final scriptCode = locale.scriptCode?.toLowerCase();
      final countryCode = locale.countryCode?.toLowerCase();

      // 匹配中文（简体）
      if (languageCode == 'zh') {
        // 优先根据 scriptCode 判断
        if (scriptCode == 'hans' || scriptCode == 'cn') {
          if (_translations.containsKey(SupportedLanguage.zhHans)) {
            return SupportedLanguage.zhHans;
          }
        } else if (scriptCode == 'hant' ||
            scriptCode == 'tw' ||
            scriptCode == 'hk') {
          if (_translations.containsKey(SupportedLanguage.zhHant)) {
            return SupportedLanguage.zhHant;
          }
        }

        // 根据 countryCode 判断
        if (countryCode == 'cn' || countryCode == 'sg') {
          if (_translations.containsKey(SupportedLanguage.zhHans)) {
            return SupportedLanguage.zhHans;
          }
        } else if (countryCode == 'tw' ||
            countryCode == 'hk' ||
            countryCode == 'mo') {
          if (_translations.containsKey(SupportedLanguage.zhHant)) {
            return SupportedLanguage.zhHant;
          }
        }

        // 默认简体中文
        if (_translations.containsKey(SupportedLanguage.zhHans)) {
          return SupportedLanguage.zhHans;
        }
      }

      // 匹配英语
      if (languageCode == 'en') {
        if (_translations.containsKey(SupportedLanguage.en)) {
          return SupportedLanguage.en;
        }
      }

      // 匹配日语
      if (languageCode == 'ja') {
        if (_translations.containsKey(SupportedLanguage.ja)) {
          return SupportedLanguage.ja;
        }
      }
    }

    // 如果没有匹配到，使用默认语言（英语）
    if (_translations.containsKey(SupportedLanguage.en)) {
      return SupportedLanguage.en;
    }

    // 如果英语也不可用，尝试简体中文
    if (_translations.containsKey(SupportedLanguage.zhHans)) {
      return SupportedLanguage.zhHans;
    }

    // 最后返回第一个可用的语言
    if (_translations.isNotEmpty) {
      return _translations.keys.first;
    }

    // 最后的后备选项（理论上不会到达这里）
    return SupportedLanguage.en;
  }

  Future<void> _loadTranslations() async {
    Object? lastError;

    for (final candidate in _translationBundleCandidates) {
      try {
        final raw = await rootBundle.loadString(candidate, cache: false);
        if (_tryLoadTranslationsFromRaw(raw)) {
          _updateFallbackLanguage();
          return;
        }
      } catch (error) {
        lastError = error;
      }
    }

    try {
      final raw =
          await EngineAssetLoader.loadString(_translationsAsset, cache: false);
      if (_tryLoadTranslationsFromRaw(raw)) {
        _updateFallbackLanguage();
        return;
      }
    } catch (error) {
      lastError = error;
    }

    if (kEngineDebugMode) {
      print('[LocalizationManager] 加载多语言失败，最后错误: $lastError');
    }
    _translations.clear();
  }

  bool _tryLoadTranslationsFromRaw(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return false;
    }

    if (decoded is! Map) {
      return false;
    }

    final parsed = <SupportedLanguage, Map<String, String>>{};
    for (final entry in decoded.entries) {
      final key = entry.key?.toString();
      final language = supportedLanguageFromCode(key);
      if (language == null) {
        continue;
      }

      final value = entry.value;
      if (value is Map) {
        parsed[language] = value.map(
          (k, dynamic v) => MapEntry(k.toString(), v.toString()),
        );
      }
    }

    if (parsed.isEmpty) {
      return false;
    }

    _translations
      ..clear()
      ..addAll(parsed);
    return true;
  }

  void _updateFallbackLanguage() {
    if (_translations.containsKey(SupportedLanguage.en)) {
      _fallbackLanguage = SupportedLanguage.en;
    } else if (_translations.isNotEmpty) {
      _fallbackLanguage = _translations.keys.first;
    }
  }

  bool get isInitialized => _initialized;

  SupportedLanguage get currentLanguage => _currentLanguage;

  Locale get currentLocale => _currentLanguage.locale;

  List<Locale> get supportedLocales {
    final locales = SupportedLanguage.values
        .where((lang) => _translations.containsKey(lang))
        .map((lang) => lang.locale)
        .toList();
    if (locales.isEmpty) {
      locales.add(SupportedLanguage.zhHans.locale);
    }
    return locales;
  }

  List<SupportedLanguage> get loadedLanguages {
    final languages = SupportedLanguage.values
        .where((lang) => _translations.containsKey(lang))
        .toList();
    if (languages.isEmpty) {
      languages.add(SupportedLanguage.zhHans);
    }
    return languages;
  }

  Future<void> switchLanguage(SupportedLanguage language) async {
    if (language == _currentLanguage || !_translations.containsKey(language)) {
      return;
    }

    _currentLanguage = language;
    await _dataManager.setStringVariable(
        'sakiengine.language', language.code, _projectName!);
    notifyListeners();
  }

  String t(String key,
      {Map<String, String>? params, SupportedLanguage? language}) {
    final lang = language ?? _currentLanguage;
    String? value =
        _translations[lang]?[key] ?? _translations[_fallbackLanguage]?[key];

    value ??= key;

    if (params != null && params.isNotEmpty) {
      for (final entry in params.entries) {
        value = value?.replaceAll('{${entry.key}}', entry.value);
      }
    }

    return value ?? key;
  }

  String displayName(SupportedLanguage language) {
    final translated = t('language.${language.code}', language: language);
    if (translated != 'language.${language.code}') {
      return translated;
    }
    return language.englishName;
  }
}
