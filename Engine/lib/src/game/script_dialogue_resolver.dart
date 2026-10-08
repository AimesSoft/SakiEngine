import 'package:sakiengine/src/sks_parser/sks_ast.dart';

/// Reads text at an already executed node without evaluating its condition or
/// replaying character, voice, API, or timing commands.
class ScriptDialogueResolver {
  static SayNode? at(ScriptNode script, int index) {
    if (index < 0 || index >= script.children.length) return null;
    final node = script.children[index];
    if (node is SayNode) return node;
    if (node is ConditionalSayNode) {
      return SayNode(
        dialogue: node.dialogue,
        character: node.character,
        dialogueTag: node.dialogueTag,
        tailCharacter: node.tailCharacter,
        sourceFile: node.sourceFile,
        sourceLine: node.sourceLine,
      );
    }
    return null;
  }
}
