/// Desktop showcase builds read game media and scripts from Game/<project>.
/// Keep Flutter's font/shader declarations and other application assets intact.
String prepareShowcasePubspec(String source) {
  final newline = source.contains('\r\n') ? '\r\n' : '\n';
  final lines = source.split(newline);
  final start = lines.indexWhere(
    (line) => RegExp(r'^  assets:\s*$').hasMatch(line),
  );
  if (start < 0) {
    throw const FormatException('pubspec.yaml 未找到 flutter/assets 段');
  }
  var end = start + 1;
  while (end < lines.length &&
      (lines[end].trim().isEmpty || lines[end].startsWith('    '))) {
    end++;
  }
  final kept = <String>[];
  for (final line in lines.sublist(start + 1, end)) {
    final match = RegExp(r'^    -\s+(.+)$').firstMatch(line);
    if (match == null) {
      if (line.trim().isNotEmpty && !line.trim().startsWith('#')) {
        throw const FormatException('演出资源清单仅支持字符串路径');
      }
      kept.add(line);
      continue;
    }
    var path = match.group(1)!.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1);
    }
    path = path.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
    final lower = path.toLowerCase();
    final isShader = lower.startsWith('assets/shaders/');
    final isExternal =
        lower == 'assets/' ||
        lower.startsWith('assets/') && !isShader ||
        RegExp(r'^gamescript(?:_|/|$)').hasMatch(lower) ||
        lower == '.saki_cache/' ||
        lower.endsWith('.sakipak');
    if (!isExternal) kept.add(line);
  }
  final hasEntries = kept.any((line) => RegExp(r'^    -\s+').hasMatch(line));
  return [
    ...lines.take(start),
    hasEntries ? lines[start] : '  assets: []',
    ...kept,
    ...lines.skip(end),
  ].join(newline);
}
