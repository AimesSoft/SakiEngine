import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/utils/key_sequence_detector.dart';

void main() {
  const dialogue =
      '她在我面前原地跳了一下，我想到，原来刚才她就是这样从楼梯上跳下来的。';

  Future<String> _rewriteSingleLine({
    required String line,
    required String characterId,
    String? writeCharacterId,
    String? newPose,
    String? newExpression,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'narration_tail_resource_alignment_test_',
    );
    try {
      final scriptFile = File('${tempDir.path}/story_01_part_02.sks');
      await scriptFile.writeAsString('$line\n');

      final ok = await ScriptContentModifier.modifyDialogueLineWithPose(
        scriptFilePath: scriptFile.path,
        targetDialogue: dialogue,
        characterId: characterId,
        writeCharacterId: writeCharacterId,
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

  test('narration tail for aru2 remains aru2 after wheel-like expression update',
      () async {
    final updated = await _rewriteSingleLine(
      line: '"$dialogue" fuzu aru2 pose1 happy an jump',
      characterId: 'aru2',
      newPose: 'pose1',
      newExpression: 'smile',
    );

    expect(updated, '"$dialogue" fuzu aru2 pose1 smile an jump');
    expect(updated.contains(' aru '), isFalse);
  });

  test(
      'tail rewrite can match alias ar but still write current on-stage resource aru2',
      () async {
    final updated = await _rewriteSingleLine(
      line: '"$dialogue" anxious ar pose1 happy',
      characterId: 'ar',
      writeCharacterId: 'aru2',
      newPose: 'pose1',
      newExpression: 'normal',
    );

    expect(updated, '"$dialogue" anxious aru2 pose1 normal');
    expect(updated.contains(' anxious ar pose1 normal'), isFalse);
  });
}
