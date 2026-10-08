import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/localization/script_localization_editing.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';

void main() {
  test('documented full-width closers preserve size, wait and instant text', () {
    const source =
        '/zhs [size=1.2]诶？[w=1][／size][pass]是谁？[／pass]/ '
        '/en [size=1.2]Huh?[w=1][／size][pass]Who?[／pass]/ '
        '/ko [size=1.2]어?[w=1][／size][pass]누구야?[／pass]/';
    for (final (language, start, ending) in [
      (SupportedLanguage.zhHans, '诶？', '是谁？'),
      (SupportedLanguage.en, 'Huh?', 'Who?'),
      (SupportedLanguage.ko, '어?', '누구야?'),
    ]) {
      final value = ScriptTextLocalizer.resolve(source, language: language);
      final segments = RichTextParser.parseTextSegments(value);
      expect(segments, hasLength(3));
      expect(segments[0].text, start);
      expect(segments[0].sizeMultiplier, 1.2);
      expect(segments[1].waitSeconds, 1);
      expect(segments[2].text, ending);
      expect(segments[2].isInstantDisplay, isTrue);
      expect(RichTextParser.cleanText(value), '$start$ending');
    }
  });

  test('editing a formatted translation retains all other language spans', () {
    const source =
        '/zhs [pass]原文[／pass]/ /en [pass]Original[／pass]/ '
        '/jp [pass]原文[／pass]/ /ko [pass]원문[／pass]/';
    final edited = EditableLocalizedText(source).setValue(
      'ko',
      '[size=0.8]번역[w=0.5][／size]',
    );
    for (final tag in ['zhs', 'en', 'jp']) {
      expect(
        EditableLocalizedText(edited).value(tag),
        EditableLocalizedText(source).value(tag),
      );
    }
    final resolved = ScriptTextLocalizer.resolve(
      edited,
      language: SupportedLanguage.ko,
    );
    final segments = RichTextParser.parseTextSegments(resolved);
    expect(segments.first.text, '번역');
    expect(segments.first.sizeMultiplier, 0.8);
    expect(segments.last.waitSeconds, 0.5);
  });

  test('legacy ASCII closers and ordinary full-width slashes stay valid', () {
    const original = '[size=1.3]Big[/size][w=0.5][pass]Now[/pass] A／B';
    expect(RichTextParser.cleanText(original), 'BigNow A／B');
    final segments = RichTextParser.parseTextSegments(original);
    expect(segments[0].sizeMultiplier, 1.3);
    expect(segments[1].waitSeconds, 0.5);
    expect(segments[2].isInstantDisplay, isTrue);
    expect(segments.last.text, ' A／B');
  });
}
