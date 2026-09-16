import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/localization/script_localization_editing.dart';
import 'package:sakiengine/src/localization/script_localization_workspace.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';

void main() {
  test('edits one language without changing other spellings or tags', () {
    const source = '原文 /ja こんにちは。/ /en  Hello!/';
    final text = EditableLocalizedText(source);
    expect(text.value('jp'), 'こんにちは。');
    expect(text.value('zhc'), '');
    expect(
      text.setValue('en', 'Good evening!'),
      '原文 /ja こんにちは。/ /en  Good evening!/',
    );
    expect(text.setValue('en', 'Hello!'), source);
    expect(text.setValue('zhs', '新原文'), '新原文/ja こんにちは。//en  Hello!/');
    expect(text.setValue('zhc', ''), '$source/zhc /');
    expect(
      EditableLocalizedText(text.setValue('zhc', '')).languages,
      contains('zhc'),
    );
  });

  test('matches runtime language aliases, repeated spans and fallback', () {
    const source = '/zh-CN 原文//ja 一//jp 二//en /';
    final text = EditableLocalizedText(source);
    expect(text.value('zhs'), '原文');
    expect(text.value('jp'), '一二');
    final edited = text.setValue('jp', '三');
    expect(
      ScriptTextLocalizer.resolve(edited, language: SupportedLanguage.ja),
      '三',
    );
    expect(
      ScriptTextLocalizer.resolve(edited, language: SupportedLanguage.en),
      '原文',
    );
    expect(EditableLocalizedText('我/她').value('zhs'), '我/她');
    expect(
      EditableLocalizedText('Hello', defaultTag: 'en').setValue('zhs', '你好'),
      'Hello/zhs 你好/',
    );
    expect(() => text.setValue('en', 'a/b'), throwsFormatException);
    expect(() => text.setValue('en', 'a"b'), throwsFormatException);
  });

  test(
    'single-language code edits preserve directing, comments, CRLF and hidden translations',
    () {
      const source =
          'label start\r\nvoice "clip.ogg"\r\n'
          '  aru pose happy at left an nod "你好。/jp こんにちは。//en Hello./" auto // keep\r\n';
      final view = LocalizedScriptProjection(source, 'en');
      expect(view.text, contains('voice "clip.ogg"'));
      expect(view.text, contains('"Hello." auto // keep'));
      expect(view.text, isNot(contains('こんにちは')));
      final before = view.text;
      view.edit(view.text.replaceFirst('Hello.', 'Hi!'));
      expect(view.source, source.replaceFirst('Hello.', 'Hi!'));
      view.edit(view.text.replaceFirst('happy', 'sad'));
      expect(
        view.source,
        source.replaceFirst('Hello.', 'Hi!').replaceFirst('happy', 'sad'),
      );
      view.edit(before);
      expect(view.source, source);
      final japanese = LocalizedScriptProjection(view.source, 'jp');
      japanese.edit(japanese.text.replaceFirst('こんにちは。', 'こんばんは。'));
      expect(japanese.source, source.replaceFirst('こんにちは。', 'こんばんは。'));
    },
  );

  test('adding and deleting whole code lines restores hidden text on undo', () {
    const source = 'label start\naru "你好/en Hello/" auto\n"再见/en Bye/"\n';
    final view = LocalizedScriptProjection(source, 'en');
    final before = view.text;
    view.edit(view.text.replaceFirst('aru "Hello" auto\n', ''));
    expect(view.source, 'label start\n"再见/en Bye/"\n');
    view.edit(before);
    expect(view.source, source);
    view.edit('${view.text}aru "Added"\n');
    expect(view.source, '${source}aru "/en Added/"\n');
  });

  test(
    'new dialogue typed character by character belongs to the selected language',
    () {
      final view = LocalizedScriptProjection('label start\n', 'en');
      var typed = view.text;
      for (final char in 'aru "Hello"\nvoice "sample.ogg"\n'.split('')) {
        typed += char;
        view.edit(typed);
        expect(view.text, typed);
      }
      expect(
        view.source,
        'label start\naru "/en Hello/"\nvoice "sample.ogg"\n',
      );
    },
  );

  test('menus and character names project; audio and comments stay literal', () {
    final view = LocalizedScriptProjection(
      'voice "voice_file"\n// "注释/en Comment/"\nmenu\n"原选项/en Choice/" next\nendmenu\n',
      'en',
    );
    expect(
      view.text,
      'voice "voice_file"\n// "注释/en Comment/"\nmenu\n"Choice" next\nendmenu\n',
    );
    final names = LocalizedScriptProjection(
      'aru : "鸦露露/en Aru/" : aru at pose slot:aru\n',
      'en',
    );
    names.edit(names.text.replaceFirst('Aru', 'Aruru'));
    expect(names.source, 'aru : "鸦露露/en Aruru/" : aru at pose slot:aru\n');
  });

  test('combined speaker and dialogue edits preserve hidden languages', () {
    const source = 'aru "原文/en Hello/" auto\n';
    final view = LocalizedScriptProjection(source, 'en');
    view.edit('miiro "Other" auto\n');
    expect(view.source, 'miiro "原文/en Other/" auto\n');
    expect(() => view.edit('miiro "Ot\nher" auto\n'), throwsFormatException);
    expect(view.source, 'miiro "原文/en Other/" auto\n');
  });

  group('source workspace', () {
    late Directory directory;
    late File story, names;
    const original =
        'label start\r\nscene room\r\naru pose happy "原文/en Hello/" auto // keep\r\n'
        '"旁白"\r\naru "条件句" if met true\r\nmenu\r\n"选项" next\r\nendmenu\r\n';
    setUp(() {
      directory = Directory.systemTemp.createTempSync('saki_localization_');
      Directory(
        '${directory.path}/GameScript/labels',
      ).createSync(recursive: true);
      Directory(
        '${directory.path}/GameScript/configs',
      ).createSync(recursive: true);
      story = File('${directory.path}/GameScript/labels/start.sks')
        ..writeAsStringSync(original);
      names = File('${directory.path}/GameScript/configs/characters.sks')
        ..writeAsStringSync(
          'aru : "鸦露露/en Aru/" : aru at pose slot:aru // keep\n',
        );
    });
    tearDown(() => directory.deleteSync(recursive: true));

    test(
      'only story appears, shared speaker edits target character configuration',
      () async {
        final workspace = await ScriptLocalizationWorkspace.load(
          directory.path,
        );
        expect(workspace.dialogue.length, 3);
        expect(workspace.dialogue.map((entry) => entry.lineIndex), [2, 3, 4]);
        workspace.dialogue.first.setValue('en', 'Hi');
        workspace.speakers['aru']!.setValue('en', 'Aruru');
        expect(await workspace.save(), 2);
        expect(story.readAsStringSync(), original.replaceFirst('Hello', 'Hi'));
        expect(
          names.readAsStringSync(),
          'aru : "鸦露露/en Aruru/" : aru at pose slot:aru // keep\n',
        );
        expect(workspace.isDirty, isFalse);
      },
    );

    test(
      'new language has empty slots on every sentence and persists',
      () async {
        final workspace = await ScriptLocalizationWorkspace.load(
          directory.path,
        );
        workspace.addLanguage('jp');
        for (final entry in workspace.dialogue) {
          expect(entry.text.languages, contains('jp'));
          expect(entry.text.value('jp'), '');
        }
        await workspace.save();
        final reopened = await ScriptLocalizationWorkspace.load(directory.path);
        expect(reopened.languages, contains('jp'));
        expect(
          story.readAsStringSync(),
          contains('menu\r\n"选项" next\r\nendmenu'),
        );
        expect(story.readAsStringSync(), contains('auto // keep\r\n'));
      },
    );

    test('external edits cause conflict before any file is written', () async {
      final workspace = await ScriptLocalizationWorkspace.load(directory.path);
      workspace.dialogue.first.setValue('en', 'Draft');
      workspace.speakers['aru']!.setValue('en', 'Draft name');
      names.writeAsStringSync('external edit');
      await expectLater(workspace.save(), throwsA(isA<FileSystemException>()));
      expect(story.readAsStringSync(), original);
      expect(names.readAsStringSync(), 'external edit');
      expect(workspace.isDirty, isTrue);
    });
  });
}
