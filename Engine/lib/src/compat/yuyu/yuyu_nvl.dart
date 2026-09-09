/// Data for the original Web overlay. Story execution and accumulation belong
/// to GameManager; the page continues to own typography and random placement.
class YuyuNvlMapping {
  static const modes = {'nvl', 'nvl2', 'nvl3', 'nvl4', 'nvl5', 'nvl6'};
  final Map<String, YuyuNvlBlock> blocks;
  const YuyuNvlMapping.empty() : blocks = const {};

  YuyuNvlMapping(Map<String, dynamic> data) : blocks = {} {
    if (data['version'] != 1 || data['blocks'] is! Map) {
      throw const FormatException('Invalid NVL mapping');
    }
    for (final entry in (data['blocks'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          !RegExp(r'^\w+$').hasMatch(entry.key) ||
          value is! Map ||
          !modes.contains(value['mode']) ||
          value['expectedLines'] is! List) {
        throw const FormatException('Invalid NVL block');
      }
      final mode = value['mode'] as String;
      final expected = <Map<String, String>>[];
      for (final line in value['expectedLines'] as List) {
        if (line is! Map ||
            line['who'] != '' ||
            line['what'] is! String ||
            line['text'] != lineText('', line['what'], mode)) {
          throw const FormatException('Invalid NVL expected line');
        }
        expected.add(
          Map<String, String>.unmodifiable({
            'who': '',
            'what': line['what'],
            'text': line['text'],
          }),
        );
      }
      if (expected.length > 1000 ||
          (!{'nvl2', 'nvl6'}.contains(mode) && expected.isNotEmpty)) {
        throw const FormatException('Invalid NVL layout lookahead');
      }
      blocks[entry.key] = YuyuNvlBlock(mode, List.unmodifiable(expected));
    }
  }

  static bool accumulates(String mode) =>
      !{'nvl3', 'nvl4', 'nvl5'}.contains(mode);

  // Mirrors web_overlay._clean_history_text, including the source UI's
  // intentional stripping of these markers; authored SKS text stays intact.
  static String cleanText(String value) => value
      .replaceAll(RegExp(r'//voice-\S+'), '')
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll('【', '')
      .replaceAll('】', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String lineText(String who, String what, String mode) =>
      switch (mode) {
        'nvl2' => '“$what”',
        'nvl6' => what,
        _ => who.isEmpty ? what : '$who：$what',
      };
}

class YuyuNvlBlock {
  final String mode;
  final List<Map<String, String>> expectedLines;
  const YuyuNvlBlock(this.mode, this.expectedLines);
}
