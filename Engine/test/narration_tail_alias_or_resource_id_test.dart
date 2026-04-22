import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/utils/key_sequence_detector.dart';

void main() {
  const dialogue = '她的手又戳到我的脸上。';

  Future<String> _rewriteSingleLine({
    required String line,
    required String characterId,
    String? newPose,
    String? newExpression,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'narration_tail_alias_or_resource_id_test_',
    );
    try {
      final scriptFile = File('${tempDir.path}/story_01_part_02.sks');
      await scriptFile.writeAsString('$line\n');

      final ok = await ScriptContentModifier.modifyDialogueLineWithPose(
        scriptFilePath: scriptFile.path,
        targetDialogue: dialogue,
        characterId: characterId,
        newPose: newPose,
        newExpression: newExpression,
        targetLineNumber: 1,
      );

      expect(ok, isTrue);
      return (await scriptFile.readAsString()).trim();
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  test('narration tail can target script alias ar and preserve an jump',
      () async {
    final updated = await _rewriteSingleLine(
      line: '"$dialogue" fuzu ar pose1 angry an jump',
      characterId: 'ar',
      newPose: 'pose1',
      newExpression: 'happy',
    );

    expect(updated, '"$dialogue" fuzu ar pose1 happy an jump');
  });

  test('narration tail with resource-like id aru still rewrites in place',
      () async {
    final updated = await _rewriteSingleLine(
      line: '"$dialogue" fuzu aru pose1 angry an jump',
      characterId: 'aru',
      newPose: 'pose1',
      newExpression: 'happy',
    );

    expect(updated, '"$dialogue" fuzu aru pose1 happy an jump');
  });
}
