import 'package:sakiengine/src/sks_parser/sks_ast.dart';

class CompiledSksBundle {
  final String? gameName;
  final Map<String, String> textByAssetPath;
  final Map<String, ScriptNode> labelScriptsByAssetPath;

  const CompiledSksBundle({
    this.gameName,
    required this.textByAssetPath,
    required this.labelScriptsByAssetPath,
  });

  bool get hasAnyData =>
      textByAssetPath.isNotEmpty || labelScriptsByAssetPath.isNotEmpty;

  bool get hasLabelScripts => labelScriptsByAssetPath.isNotEmpty;

  Iterable<String> get textAssetPaths => textByAssetPath.keys;

  Iterable<String> get labelAssetPaths => labelScriptsByAssetPath.keys;

  String? loadText(String assetPath) {
    return textByAssetPath[normalizeAssetPath(assetPath)];
  }

  ScriptNode? loadLabelScriptByAssetPath(String assetPath) {
    return labelScriptsByAssetPath[normalizeAssetPath(assetPath)];
  }

  static String normalizeAssetPath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith('assets/')) {
      normalized = 'assets/$normalized';
    }
    return normalized;
  }
}
