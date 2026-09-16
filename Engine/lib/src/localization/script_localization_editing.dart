import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

const scriptEditorLanguages = <String, String>{
  'zhs': '简体中文',
  'zhc': '繁體中文',
  'jp': '日本語',
  'en': 'English',
};

String? canonicalScriptLanguage(String tag) =>
    switch (ScriptTextLocalizer.normalizeTag(tag)) {
      'zhs' || 'zhhans' || 'zhcn' => 'zhs',
      'zhc' || 'zht' || 'zhhant' || 'zhtw' || 'zhtc' => 'zhc',
      'jp' || 'ja' => 'jp',
      'en' => 'en',
      _ => null,
    };

class _LanguageSpan {
  final int start, end, textStart;
  final String tag;
  const _LanguageSpan(this.start, this.end, this.textStart, this.tag);
}

/// Lossless editing of inline language payloads. Other languages and SKS
/// commands are never regenerated from the displayed text.
class EditableLocalizedText {
  final String source;
  final String defaultTag;
  final List<_LanguageSpan> _spans = [];

  EditableLocalizedText(this.source, {String? defaultTag})
    : defaultTag =
          defaultTag ?? ScriptTextLocalizer.currentDefaultLanguageTag() {
    var cursor = 0;
    final tagChar = RegExp(r'[A-Za-z0-9_-]');
    while (cursor < source.length) {
      final start = source.indexOf('/', cursor);
      if (start < 0) break;
      var tagEnd = start + 1;
      while (tagEnd < source.length && tagChar.hasMatch(source[tagEnd])) {
        tagEnd++;
      }
      final tag = canonicalScriptLanguage(source.substring(start + 1, tagEnd));
      final close = source.indexOf('/', tagEnd);
      if (tag == null || close < 0) {
        cursor = start + 1;
        continue;
      }
      var textStart = tagEnd;
      while (textStart < close && source[textStart].trim().isEmpty) {
        textStart++;
      }
      _spans.add(_LanguageSpan(start, close + 1, textStart, tag));
      cursor = close + 1;
    }
  }

  String get _plain {
    var cursor = 0;
    final result = StringBuffer();
    for (final span in _spans) {
      result.write(source.substring(cursor, span.start));
      cursor = span.end;
    }
    result.write(source.substring(cursor));
    return result.toString();
  }

  Set<String> get languages => {
    if (_spans.isEmpty || _plain.trim().isNotEmpty) defaultTag,
    ..._spans.map((span) => span.tag),
  };

  /// Missing translations stay empty in an editor, rather than showing the
  /// runtime fallback as if it had been translated.
  String value(String tag) {
    final spans = _spans.where((span) => span.tag == tag);
    if (spans.isNotEmpty) {
      return spans
          .map((span) => source.substring(span.textStart, span.end - 1))
          .join();
    }
    return tag == defaultTag ? _plain : '';
  }

  String setValue(String tag, String value) {
    if (!scriptEditorLanguages.containsKey(tag)) {
      throw ArgumentError.value(tag, 'tag');
    }
    if (value.contains('\n') || value.contains('\r') || value.contains('"')) {
      throw const FormatException('请使用中文引号或「」，换行请填写字面量 \\n。');
    }
    final matching = _spans.where((span) => span.tag == tag).toList();
    if (value == this.value(tag) && languages.contains(tag)) return source;
    if (matching.isNotEmpty) {
      if (value.contains('/')) {
        throw const FormatException('行内翻译不能包含半角 /，请使用全角 ／。');
      }
      var result = source;
      for (final span in matching.reversed) {
        result = result.replaceRange(
          span.textStart,
          span.end - 1,
          span == matching.first ? value : '',
        );
      }
      return result;
    }
    if (tag == defaultTag) {
      // Retain language spans verbatim, including their original order.
      if (_spans.isEmpty) return value;
      return value +
          _spans.map((span) => source.substring(span.start, span.end)).join();
    }
    if (value.contains('/')) {
      throw const FormatException('行内翻译不能包含半角 /，请使用全角 ／。');
    }
    return '$source/$tag $value/';
  }
}

class ScriptQuotedRange {
  final int start, end;
  const ScriptQuotedRange(this.start, this.end);
}

/// Double quoted content only; comments and escaped quotes are respected.
List<ScriptQuotedRange> scriptQuotedRanges(String source) {
  final result = <ScriptQuotedRange>[];
  int? start;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (start == null &&
        char == '/' &&
        i + 1 < source.length &&
        source[i + 1] == '/') {
      final newline = source.indexOf('\n', i);
      if (newline < 0) break;
      i = newline;
      continue;
    }
    if (char == '\n') {
      start = null;
      escaped = false;
      continue;
    }
    if (char == '"' && !escaped) {
      if (start == null) {
        start = i + 1;
      } else {
        result.add(ScriptQuotedRange(start, i));
        start = null;
      }
    }
    escaped = char == r'\' && !escaped;
  }
  return result;
}

List<ScriptQuotedRange> localizableScriptRanges(String source) {
  final dialogueLines = <int>{};
  try {
    for (final node in SksParser().parse(source).children) {
      final line = switch (node) {
        SayNode() => node.sourceLine,
        ConditionalSayNode() => node.sourceLine,
        _ => null,
      };
      if (line != null) dialogueLines.add(line);
    }
  } catch (_) {
    // An unfinished command is normal while typing in the code editor.
  }
  final lines = source.split('\n');
  final menuLines = <int>{};
  var inMenu = false;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == 'menu') inMenu = true;
    if (lines[i].trim() == 'endmenu') inMenu = false;
    if (inMenu) menuLines.add(i + 1);
  }
  var line = 1;
  var cursor = 0;
  return scriptQuotedRanges(source).where((range) {
    line += '\n'.allMatches(source.substring(cursor, range.start)).length;
    cursor = range.start;
    return dialogueLines.contains(line) ||
        menuLines.contains(line) ||
        RegExp(r'^\s*[^/:]+:\s*"').hasMatch(lines[line - 1]) ||
        EditableLocalizedText(
          source.substring(range.start, range.end),
        ).languages.any(
          (tag) => tag != ScriptTextLocalizer.currentDefaultLanguageTag(),
        );
  }).toList();
}

class _ProjectedQuote {
  final ScriptQuotedRange raw;
  final int start, end;
  const _ProjectedQuote(this.raw, this.start, this.end);
}

/// A reversible single-language view for the code editor. History retains
/// full source snapshots, so undo of deleted lines also restores translations.
class LocalizedScriptProjection {
  String source;
  final String? language;
  final String defaultTag;
  String text = '';
  final List<_ProjectedQuote> _quotes = [];
  final Map<String, String> _history = {};

  LocalizedScriptProjection(this.source, this.language, {String? defaultTag})
    : defaultTag =
          defaultTag ?? ScriptTextLocalizer.currentDefaultLanguageTag() {
    _project();
  }

  void _project() {
    _quotes.clear();
    if (language == null) {
      text = source;
    } else {
      var cursor = 0;
      final output = StringBuffer();
      for (final range in localizableScriptRanges(source)) {
        output.write(source.substring(cursor, range.start));
        final start = output.length;
        output.write(
          EditableLocalizedText(
            source.substring(range.start, range.end),
            defaultTag: defaultTag,
          ).value(language!),
        );
        _quotes.add(_ProjectedQuote(range, start, output.length));
        cursor = range.end;
      }
      output.write(source.substring(cursor));
      text = output.toString();
    }
    _history[text] = source;
  }

  void edit(String next) {
    if (next == text) return;
    if (_history.containsKey(next)) {
      source = _history[next]!;
      _project();
      return;
    }
    if (language == null) {
      source = next;
      _project();
      return;
    }
    var start = 0;
    while (start < text.length &&
        start < next.length &&
        text[start] == next[start]) {
      start++;
    }
    var end = text.length;
    var nextEnd = next.length;
    while (end > start &&
        nextEnd > start &&
        text[end - 1] == next[nextEnd - 1]) {
      end--;
      nextEnd--;
    }
    final replacement = next.substring(start, nextEnd);
    for (final quote in _quotes) {
      if (start >= quote.start && end <= quote.end) {
        final value = text
            .substring(quote.start, quote.end)
            .replaceRange(start - quote.start, end - quote.start, replacement);
        final localized = EditableLocalizedText(
          source.substring(quote.raw.start, quote.raw.end),
          defaultTag: defaultTag,
        );
        source = source.replaceRange(
          quote.raw.start,
          quote.raw.end,
          localized.setValue(language!, value),
        );
        _project();
        return;
      }
    }
    // Multi-line paste or a simultaneous speaker/text edit: align unchanged
    // physical lines and retain each quoted payload's hidden language spans.
    final beforeLines = text.split('\n');
    final afterLines = next.split('\n');
    if (beforeLines.length == afterLines.length) {
      final rawLines = source.split('\n');
      var compatible = true;
      var rawLineOffset = 0;
      for (var i = 0; i < beforeLines.length; i++) {
        final originalLine = rawLines[i];
        if (beforeLines[i] != afterLines[i]) {
          final beforeQuotes = scriptQuotedRanges(beforeLines[i]);
          final afterQuotes = scriptQuotedRanges(afterLines[i]);
          final rawQuotes = scriptQuotedRanges(originalLine);
          if (beforeQuotes.length != afterQuotes.length ||
              rawQuotes.length != afterQuotes.length) {
            compatible = false;
            break;
          }
          var merged = afterLines[i];
          for (var j = afterQuotes.length - 1; j >= 0; j--) {
            final raw = rawQuotes[j];
            if (!_quotes.any(
              (quote) => quote.raw.start == rawLineOffset + raw.start,
            )) {
              continue;
            }
            final after = afterQuotes[j];
            final localized = EditableLocalizedText(
              originalLine.substring(raw.start, raw.end),
              defaultTag: defaultTag,
            );
            merged = merged.replaceRange(
              after.start,
              after.end,
              localized.setValue(
                language!,
                afterLines[i].substring(after.start, after.end),
              ),
            );
          }
          rawLines[i] = merged;
        }
        rawLineOffset += originalLine.length + 1;
      }
      if (compatible) {
        source = rawLines.join('\n');
        _project();
        return;
      }
    }
    // Complete source lines/commands can be inserted or removed. A selection
    // crossing half of a translated quote is ambiguous; keep the source intact.
    int rawOffset(int offset) {
      var delta = 0;
      for (final quote in _quotes) {
        if (offset >= quote.start && offset <= quote.end) {
          throw const FormatException('跨越部分对白的结构编辑，请切换到「完整源码」。');
        }
        if (offset >= quote.end) {
          delta += quote.raw.end - quote.raw.start - (quote.end - quote.start);
        }
      }
      return offset + delta;
    }

    final rawStart = rawOffset(start);
    final rawEnd = rawOffset(end);
    final delta = replacement.length - (rawEnd - rawStart);
    final retainedQuoteStarts = {
      for (final quote in _quotes)
        if (quote.raw.end < rawStart)
          quote.raw.start
        else if (quote.raw.start >= rawEnd)
          quote.raw.start + delta,
    };
    var updated = source.replaceRange(rawStart, rawEnd, replacement);
    if (language != defaultTag) {
      // This also catches a quote completed one keystroke at a time. Translate
      // new dialogue payloads, but never resource paths such as voice "x.ogg".
      for (final range in localizableScriptRanges(updated).reversed) {
        if (retainedQuoteStarts.contains(range.start)) continue;
        final value = updated.substring(range.start, range.end);
        updated = updated.replaceRange(
          range.start,
          range.end,
          EditableLocalizedText(
            '',
            defaultTag: defaultTag,
          ).setValue(language!, value),
        );
      }
    }
    source = updated;
    _project();
  }
}
