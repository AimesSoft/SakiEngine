import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sakiengine/src/localization/script_localization_editing.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

class LocalizationSourceFile {
  final String path;
  String original;
  final List<String> lines;
  LocalizationSourceFile(this.path, this.original)
    : lines = original.split('\n');
  String get content => lines.join('\n');
  bool get isDirty => content != original;
}

class LocalizationTextEntry {
  final LocalizationSourceFile file;
  final int lineIndex;
  final String? speaker;
  final String defaultTag;
  LocalizationTextEntry(
    this.file,
    this.lineIndex,
    this.speaker,
    this.defaultTag,
  );

  ScriptQuotedRange get _range =>
      scriptQuotedRanges(file.lines[lineIndex]).first;
  EditableLocalizedText get text {
    final range = _range;
    return EditableLocalizedText(
      file.lines[lineIndex].substring(range.start, range.end),
      defaultTag: defaultTag,
    );
  }

  void setValue(String language, String value) {
    final range = _range;
    final replacement = text.setValue(language, value);
    file.lines[lineIndex] = file.lines[lineIndex].replaceRange(
      range.start,
      range.end,
      replacement,
    );
  }
}

/// Source-backed workspace. Keeps drafts for every file; only files changed by
/// the user are written, with a conflict check before any write.
class ScriptLocalizationWorkspace {
  final String root;
  final List<LocalizationSourceFile> files;
  final List<LocalizationTextEntry> dialogue;
  final Map<String, LocalizationTextEntry> speakers;
  final Set<String> languages;

  ScriptLocalizationWorkspace._(
    this.root,
    this.files,
    this.dialogue,
    this.speakers,
    this.languages,
  );

  static Future<ScriptLocalizationWorkspace> load(String gamePath) async {
    final root = p.join(gamePath, 'GameScript');
    if (!await Directory(root).exists()) {
      throw FileSystemException('找不到 GameScript 目录', root);
    }
    final files = <LocalizationSourceFile>[];
    final dialogue = <LocalizationTextEntry>[];
    final speakers = <String, LocalizationTextEntry>{};
    final defaultTag = ScriptTextLocalizer.currentDefaultLanguageTag();
    final languages = <String>{defaultTag};
    final paths = <String>[];
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path) == '.sks') {
        paths.add(entity.path);
      }
    }
    paths.sort();
    for (final path in paths) {
      final relative = p.relative(path, from: root);
      final isCharacters = relative == p.join('configs', 'characters.sks');
      if (!isCharacters && p.split(relative).contains('configs')) continue;
      final file = LocalizationSourceFile(
        path,
        await File(path).readAsString(),
      );
      files.add(file);
      if (isCharacters) {
        for (var i = 0; i < file.lines.length; i++) {
          final match = RegExp(
            r'^\s*([^/:]+?)\s*:\s*"',
          ).firstMatch(file.lines[i]);
          if (match == null || scriptQuotedRanges(file.lines[i]).isEmpty) {
            continue;
          }
          final id = match.group(1)!.trim();
          final entry = LocalizationTextEntry(file, i, id, defaultTag);
          speakers[id] = entry;
          languages.addAll(entry.text.languages);
        }
        continue;
      }
      final nodes = SksParser().parse(file.original).children;
      for (final node in nodes) {
        final (line, speaker) = switch (node) {
          SayNode() => (node.sourceLine, node.character),
          ConditionalSayNode() => (node.sourceLine, node.character),
          _ => (null, null),
        };
        if (line == null || scriptQuotedRanges(file.lines[line - 1]).isEmpty) {
          continue;
        }
        final entry = LocalizationTextEntry(
          file,
          line - 1,
          speaker,
          defaultTag,
        );
        dialogue.add(entry);
        languages.addAll(entry.text.languages);
      }
    }
    return ScriptLocalizationWorkspace._(
      root,
      files,
      dialogue,
      speakers,
      languages,
    );
  }

  bool get isDirty => files.any((file) => file.isDirty);
  List<LocalizationSourceFile> get storyFiles =>
      files.where((file) => dialogue.any((row) => row.file == file)).toList();

  void addLanguage(String tag) {
    if (languages.contains(tag)) return;
    // Explicitly requested empty slots persist across editor sessions. Existing
    // commands, formatting and translations remain byte-for-byte unchanged.
    for (final entry in [...dialogue, ...speakers.values]) {
      if (!entry.text.languages.contains(tag)) entry.setValue(tag, '');
    }
    languages.add(tag);
  }

  Future<int> save() async {
    final changed = files.where((file) => file.isDirty).toList();
    for (final file in changed) {
      if (await File(file.path).readAsString() != file.original) {
        throw FileSystemException('文件已被其他编辑器修改，请保留当前草稿并解决冲突', file.path);
      }
    }
    final staged = <LocalizationSourceFile, File>{};
    final written = <LocalizationSourceFile>[];
    try {
      for (final file in changed) {
        final temp = File(
          '${file.path}.localization_${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        staged[file] = temp;
        await temp.writeAsString(file.content, flush: true);
      }
      for (final file in changed) {
        await staged[file]!.rename(file.path);
        written.add(file);
      }
    } catch (_) {
      // Keep dialogue and shared speaker names consistent on a partial failure.
      for (final file in written.reversed) {
        await File(file.path).writeAsString(file.original, flush: true);
      }
      rethrow;
    } finally {
      for (final temp in staged.values) {
        if (await temp.exists()) await temp.delete();
      }
    }
    for (final file in changed) {
      file.original = file.content;
    }
    return changed.length;
  }
}
