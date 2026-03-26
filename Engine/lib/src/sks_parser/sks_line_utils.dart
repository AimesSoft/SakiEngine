class SksLineUtils {
  static bool _isEscapedQuote(String line, int quoteIndex) {
    var backslashCount = 0;
    var cursor = quoteIndex - 1;
    while (cursor >= 0 && line[cursor] == r'\') {
      backslashCount += 1;
      cursor -= 1;
    }
    return backslashCount.isOdd;
  }

  /// 移除行内注释（`//`），但会保留双引号内的 `//` 内容。
  static String stripLineCommentOutsideQuotes(String line) {
    var inQuotes = false;
    for (var i = 0; i < line.length - 1; i += 1) {
      final current = line[i];
      if (current == '"' && !_isEscapedQuote(line, i)) {
        inQuotes = !inQuotes;
        continue;
      }

      if (!inQuotes && current == '/' && line[i + 1] == '/') {
        return line.substring(0, i).trimRight();
      }
    }
    return line;
  }
}
