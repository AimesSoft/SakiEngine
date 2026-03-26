import 'package:sakiengine/src/localization/localization_manager.dart';

class ScriptTextLocalizer {
  ScriptTextLocalizer._();

  static const String defaultLanguageTag = 'zhs';

  static final Map<String, SupportedLanguage> _tagToLanguage = {
    'zhs': SupportedLanguage.zhHans,
    'zhhans': SupportedLanguage.zhHans,
    'zhcn': SupportedLanguage.zhHans,
    'zhc': SupportedLanguage.zhHant,
    'zht': SupportedLanguage.zhHant,
    'zhhant': SupportedLanguage.zhHant,
    'zhtw': SupportedLanguage.zhHant,
    'zhtc': SupportedLanguage.zhHant,
    'en': SupportedLanguage.en,
    'jp': SupportedLanguage.ja,
    'ja': SupportedLanguage.ja,
  };

  static final Map<SupportedLanguage, String> _languageToPrimaryTag = {
    SupportedLanguage.zhHans: 'zhs',
    SupportedLanguage.zhHant: 'zhc',
    SupportedLanguage.en: 'en',
    SupportedLanguage.ja: 'jp',
  };

  static String _defaultScriptLanguageTag = defaultLanguageTag;

  static String currentDefaultLanguageTag() => _defaultScriptLanguageTag;

  static String? normalizeTag(String? rawTag) {
    if (rawTag == null) {
      return null;
    }
    final normalized =
        rawTag.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static bool setDefaultLanguageTag(String? rawTag) {
    final normalized = normalizeTag(rawTag);
    if (normalized == null) {
      _defaultScriptLanguageTag = defaultLanguageTag;
      return false;
    }
    if (!_tagToLanguage.containsKey(normalized)) {
      _defaultScriptLanguageTag = defaultLanguageTag;
      return false;
    }
    _defaultScriptLanguageTag = _canonicalTagFor(normalized);
    return true;
  }

  static String _canonicalTagFor(String normalizedTag) {
    final language = _tagToLanguage[normalizedTag];
    if (language == null) {
      return normalizedTag;
    }
    return _languageToPrimaryTag[language] ?? normalizedTag;
  }

  static String _tagForLanguage(SupportedLanguage language) {
    return _languageToPrimaryTag[language] ?? defaultLanguageTag;
  }

  static bool _isTagChar(String char) {
    return RegExp(r'[A-Za-z0-9_-]').hasMatch(char);
  }

  static String resolve(
    String text, {
    SupportedLanguage? language,
  }) {
    if (text.isEmpty || !text.contains('/')) {
      return text;
    }

    final segments = <_ScriptTextSegment>[];
    final taggedTexts = <String, StringBuffer>{};
    var hasTaggedSegment = false;

    var cursor = 0;
    while (cursor < text.length) {
      final slashIndex = text.indexOf('/', cursor);
      if (slashIndex < 0) {
        if (cursor < text.length) {
          segments.add(_ScriptTextSegment.plain(text.substring(cursor)));
        }
        break;
      }

      if (slashIndex > cursor) {
        segments
            .add(_ScriptTextSegment.plain(text.substring(cursor, slashIndex)));
      }

      var tagEnd = slashIndex + 1;
      while (tagEnd < text.length && _isTagChar(text[tagEnd])) {
        tagEnd += 1;
      }

      if (tagEnd == slashIndex + 1) {
        segments.add(const _ScriptTextSegment.plain('/'));
        cursor = slashIndex + 1;
        continue;
      }

      final rawTag = text.substring(slashIndex + 1, tagEnd);
      final normalizedTag = normalizeTag(rawTag);
      if (normalizedTag == null || !_tagToLanguage.containsKey(normalizedTag)) {
        segments.add(const _ScriptTextSegment.plain('/'));
        cursor = slashIndex + 1;
        continue;
      }

      final closeSlashIndex = text.indexOf('/', tagEnd);
      if (closeSlashIndex < 0) {
        segments.add(_ScriptTextSegment.plain(text.substring(slashIndex)));
        cursor = text.length;
        break;
      }

      var taggedText = text.substring(tagEnd, closeSlashIndex);
      taggedText = taggedText.replaceFirst(RegExp(r'^\s+'), '');
      final canonicalTag = _canonicalTagFor(normalizedTag);
      segments
          .add(_ScriptTextSegment.tagged(tag: canonicalTag, text: taggedText));
      final bucket = taggedTexts.putIfAbsent(canonicalTag, StringBuffer.new);
      bucket.write(taggedText);
      hasTaggedSegment = true;
      cursor = closeSlashIndex + 1;
    }

    if (!hasTaggedSegment) {
      return text;
    }

    final selectedLanguage = language ?? LocalizationManager().currentLanguage;
    final selectedTag = _tagForLanguage(selectedLanguage);
    final defaultTag = _defaultScriptLanguageTag;
    final plainText = segments
        .where((segment) => !segment.isTagged)
        .map((segment) => segment.text)
        .join();

    String? taggedValue(String tag) {
      final value = taggedTexts[tag]?.toString();
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    }

    final selectedValue = taggedValue(selectedTag);
    if (selectedValue != null) {
      return selectedValue;
    }

    final plainHasContent = plainText.trim().isNotEmpty;
    if (selectedTag == defaultTag && plainHasContent) {
      return plainText;
    }

    final defaultValue = taggedValue(defaultTag);
    if (defaultValue != null) {
      return defaultValue;
    }

    if (plainHasContent) {
      return plainText;
    }

    if (taggedTexts.isNotEmpty) {
      return taggedTexts.values.first.toString();
    }

    return text;
  }

  static String localizeQuotedText(
    String line, {
    SupportedLanguage? language,
  }) {
    if (line.isEmpty || !line.contains('"')) {
      return line;
    }

    final output = StringBuffer();
    final quotedBuffer = StringBuffer();
    var inQuotes = false;
    var inEscaped = false;

    for (final codeUnit in line.codeUnits) {
      final char = String.fromCharCode(codeUnit);

      if (inQuotes) {
        if (inEscaped) {
          quotedBuffer.write(char);
          inEscaped = false;
          continue;
        }

        if (char == r'\') {
          quotedBuffer.write(char);
          inEscaped = true;
          continue;
        }

        if (char == '"') {
          output.write(resolve(quotedBuffer.toString(), language: language));
          output.write(char);
          quotedBuffer.clear();
          inQuotes = false;
          continue;
        }

        quotedBuffer.write(char);
        continue;
      }

      output.write(char);
      if (char == '"') {
        inQuotes = true;
      }
    }

    if (inQuotes) {
      output.write(quotedBuffer.toString());
    }

    return output.toString();
  }
}

class _ScriptTextSegment {
  final bool isTagged;
  final String? tag;
  final String text;

  const _ScriptTextSegment._({
    required this.isTagged,
    required this.tag,
    required this.text,
  });

  const _ScriptTextSegment.plain(String text)
      : this._(isTagged: false, tag: null, text: text);

  const _ScriptTextSegment.tagged({
    required String tag,
    required String text,
  }) : this._(isTagged: true, tag: tag, text: text);
}
