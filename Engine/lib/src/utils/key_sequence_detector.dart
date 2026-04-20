import 'dart:async';
import 'dart:io';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/game/game_script_localization.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';

/// 按键序列检测器
/// 用于检测特定按键序列，如连续按下 c-o-n-s-o-l-e
class KeySequenceDetector {
  final List<LogicalKeyboardKey> _targetSequence;
  final VoidCallback _onSequenceComplete;
  final Duration _sequenceTimeout;

  bool _isListening = false;
  List<LogicalKeyboardKey> _currentSequence = [];
  Timer? _timeoutTimer;

  KeySequenceDetector({
    required List<LogicalKeyboardKey> sequence,
    required VoidCallback onSequenceComplete,
    Duration sequenceTimeout = const Duration(seconds: 3),
  })  : _targetSequence = sequence,
        _onSequenceComplete = onSequenceComplete,
        _sequenceTimeout = sequenceTimeout;

  /// 开始监听键盘事件
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    if (kEngineDebugMode) {
      final sequenceNames =
          _targetSequence.map((key) => key.debugName).join('-');
      print('按键序列检测器: 开始监听序列 $sequenceNames');
    }
  }

  /// 停止监听键盘事件
  void stopListening() {
    if (!_isListening) return;

    _isListening = false;
    _cancelTimeoutTimer();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _currentSequence.clear();

    if (kEngineDebugMode) {
      print('按键序列检测器: 停止监听');
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isListening) return false;

    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      // 检查是否是序列中的下一个键
      if (_currentSequence.length < _targetSequence.length &&
          key == _targetSequence[_currentSequence.length]) {
        _currentSequence.add(key);
        _resetTimeout();

        if (kEngineDebugMode) {
          print(
              '按键序列检测器: 按键 ${key.debugName} 匹配，当前序列长度: ${_currentSequence.length}/${_targetSequence.length}');
        }

        // 检查序列是否完成
        if (_currentSequence.length == _targetSequence.length) {
          if (kEngineDebugMode) {
            print('按键序列检测器: 序列完成！');
          }
          _onSequenceComplete();
          _resetSequence();
          return true;
        }

        return true;
      } else {
        // 按键不匹配，重置序列
        if (_currentSequence.isNotEmpty) {
          if (kEngineDebugMode) {
            print('按键序列检测器: 按键 ${key.debugName} 不匹配，重置序列');
          }
          _resetSequence();
        }
      }
    }

    return false;
  }

  void _resetTimeout() {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(_sequenceTimeout, () {
      if (kEngineDebugMode) {
        print('按键序列检测器: 序列超时，重置');
      }
      _resetSequence();
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _resetSequence() {
    _currentSequence.clear();
    _cancelTimeoutTimer();
  }

  void dispose() {
    stopListening();
  }
}

/// 长按键检测器
/// 用于检测特定按键的长按操作，如长按C键
class LongPressKeyDetector {
  final LogicalKeyboardKey _targetKey;
  final VoidCallback _onLongPress;
  final Duration _longPressDuration;

  bool _isListening = false;
  bool _isKeyPressed = false;
  Timer? _longPressTimer;

  LongPressKeyDetector({
    required LogicalKeyboardKey key,
    required VoidCallback onLongPress,
    Duration longPressDuration = const Duration(milliseconds: 800),
  })  : _targetKey = key,
        _onLongPress = onLongPress,
        _longPressDuration = longPressDuration;

  /// 开始监听键盘事件
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    if (kEngineDebugMode) {
      print('长按键检测器: 开始监听 ${_targetKey.debugName} 长按事件');
    }
  }

  /// 停止监听键盘事件
  void stopListening() {
    if (!_isListening) return;

    _isListening = false;
    _cancelLongPressTimer();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isKeyPressed = false;

    if (kEngineDebugMode) {
      print('长按键检测器: 停止监听');
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isListening) return false;

    if (event.logicalKey == _targetKey) {
      if (event is KeyDownEvent) {
        // 按键按下
        if (!_isKeyPressed) {
          _isKeyPressed = true;
          _startLongPressTimer();

          if (kEngineDebugMode) {
            print('长按键检测器: ${_targetKey.debugName} 按下，开始计时');
          }
        }
        return true;
      } else if (event is KeyUpEvent) {
        // 按键松开
        if (_isKeyPressed) {
          _isKeyPressed = false;
          _cancelLongPressTimer();

          if (kEngineDebugMode) {
            print('长按键检测器: ${_targetKey.debugName} 松开，取消计时');
          }
        }
        return true;
      }
    }

    return false;
  }

  void _startLongPressTimer() {
    _cancelLongPressTimer();
    _longPressTimer = Timer(_longPressDuration, () {
      if (_isKeyPressed && _isListening) {
        if (kEngineDebugMode) {
          print('长按键检测器: ${_targetKey.debugName} 长按触发');
        }
        _onLongPress();
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void dispose() {
    stopListening();
  }
}

/// 脚本内容修改器
/// 负责修改脚本文件中的对话行，添加或更新角色差分信息
class ScriptContentModifier {
  /// 修改脚本文件中的对话行，添加差分信息
  ///
  /// [scriptFilePath] 脚本文件的完整路径
  /// [targetDialogue] 目标对话文本
  /// [characterId] 角色ID
  /// [newExpression] 新的表情差分
  static Future<bool> modifyDialogueLine({
    required String scriptFilePath,
    required String targetDialogue,
    required String characterId,
    required String newExpression,
  }) async {
    try {
      final file = File(scriptFilePath);
      if (!await file.exists()) {
        if (kEngineDebugMode) {
          print('脚本修改器: 文件不存在 $scriptFilePath');
        }
        return false;
      }

      final content = await file.readAsString();
      final lines = content.split('\n');
      bool modified = false;

      for (int i = 0; i < lines.length; i++) {
        final originalLine = lines[i];
        final line = originalLine.trim();

        // 检查是否是包含目标对话的行，同时验证角色ID
        if (_isTargetDialogueLine(line, targetDialogue, characterId)) {
          final modifiedLine =
              _modifyDialogueLine(line, characterId, null, newExpression);
          if (modifiedLine != line) {
            lines[i] = originalLine.replaceFirst(line, modifiedLine);
            modified = true;

            if (kEngineDebugMode) {
              print('脚本修改器: 修改对话行');
              print('原始行: $line');
              print('修改后: $modifiedLine');
            }
            break; // 只修改第一个匹配的行
          }
        }
      }

      if (modified) {
        final modifiedContent = lines.join('\n');
        await _writeScriptFile(file, modifiedContent);

        if (kEngineDebugMode) {
          print('脚本修改器: 成功保存修改的脚本文件');
        }
        return true;
      } else {
        if (kEngineDebugMode) {
          print('脚本修改器: 未找到匹配的对话行');
        }
        return false;
      }
    } catch (e) {
      if (kEngineDebugMode) {
        print('脚本修改器: 修改脚本文件失败: $e');
      }
      return false;
    }
  }

  /// 检查是否是目标对话行
  static bool _isTargetDialogueLine(String line, String targetDialogue,
      [String? expectedCharacterId]) {
    // 去除前后空白
    final trimmedLine = line.trim();
    final trimmedDialogue = targetDialogue.trim();

    if (kEngineDebugMode && line.contains(targetDialogue.replaceAll('"', ''))) {
      print('ScriptModifier: 检查行匹配');
      print('ScriptModifier: 行内容: "$trimmedLine"');
      print('ScriptModifier: 目标对话: "$trimmedDialogue"');
      print('ScriptModifier: 期望角色ID: $expectedCharacterId');
    }

    // 标准化对话文本 - 统一引号类型和去除引号
    String normalizeDialogue(String text) {
      final localized = ScriptTextLocalizer.resolve(text);
      return localized
          .replaceAll('"', '')
          .replaceAll('「', '')
          .replaceAll('」', '')
          .trim();
    }

    // 检查不同的对话格式
    // 格式1: "对话内容" - 只有在没有指定expectedCharacterId时才匹配
    if (trimmedLine.startsWith('"') &&
        trimmedLine.endsWith('"') &&
        expectedCharacterId == null) {
      final dialogueContent = trimmedLine.substring(1, trimmedLine.length - 1);
      if (normalizeDialogue(dialogueContent) ==
          normalizeDialogue(trimmedDialogue)) {
        if (kEngineDebugMode) {
          print('ScriptModifier: 匹配格式1（纯对话）');
        }
        return true;
      }
    }

    // 格式2: character "对话内容"
    // 格式3: character expression "对话内容"
    if (trimmedLine.contains('"') && !trimmedLine.startsWith('"')) {
      final parts = trimmedLine.split(' ');
      if (parts.isNotEmpty) {
        final lineCharacterId = parts[0];

        if (kEngineDebugMode &&
            line.contains(targetDialogue.replaceAll('"', ''))) {
          print('ScriptModifier: 行角色ID: "$lineCharacterId"');
        }

        // 如果指定了expectedCharacterId，必须匹配
        if (!_isCharacterIdCompatible(
          lineCharacterId: lineCharacterId,
          expectedCharacterId: expectedCharacterId,
        )) {
          if (kEngineDebugMode &&
              line.contains(targetDialogue.replaceAll('"', ''))) {
            print(
                'ScriptModifier: 角色ID不匹配: "$lineCharacterId" !~ "$expectedCharacterId"');
          }
          return false;
        }

        final quoteStart = trimmedLine.indexOf('"');
        final quoteEnd = trimmedLine.lastIndexOf('"');
        if (quoteStart >= 0 && quoteEnd > quoteStart) {
          final dialogueContent =
              trimmedLine.substring(quoteStart + 1, quoteEnd);
          if (kEngineDebugMode &&
              line.contains(targetDialogue.replaceAll('"', ''))) {
            print('ScriptModifier: 提取的对话内容: "$dialogueContent"');
            print(
                'ScriptModifier: 标准化后的对话内容: "${normalizeDialogue(dialogueContent)}"');
            print(
                'ScriptModifier: 标准化后的目标对话: "${normalizeDialogue(trimmedDialogue)}"');
            print(
                'ScriptModifier: 是否匹配: ${normalizeDialogue(dialogueContent) == normalizeDialogue(trimmedDialogue)}');
          }

          // 使用标准化后的文本进行比较
          if (normalizeDialogue(dialogueContent) ==
              normalizeDialogue(trimmedDialogue)) {
            if (kEngineDebugMode) {
              print('ScriptModifier: 匹配格式2/3（角色+对话）');
            }
            return true;
          }
        }
      }
    }

    return false;
  }

  /// 角色ID兼容匹配：
  /// - 完全相等
  /// - expected 作为前缀，后缀首字符为字母或下划线（例如 q3 -> q3r / q3_alt）
  static bool _isCharacterIdCompatible({
    required String lineCharacterId,
    String? expectedCharacterId,
  }) {
    if (expectedCharacterId == null || expectedCharacterId.isEmpty) {
      return true;
    }
    if (lineCharacterId == expectedCharacterId) {
      return true;
    }
    if (!lineCharacterId.startsWith(expectedCharacterId)) {
      return false;
    }
    if (lineCharacterId.length == expectedCharacterId.length) {
      return true;
    }
    final nextChar = lineCharacterId[expectedCharacterId.length];
    return RegExp(r'[A-Za-z_]').hasMatch(nextChar);
  }

  /// 修改对话行，添加或更新pose和表情信息
  static String _modifyDialogueLine(
      String line, String characterId, String? newPose, String? newExpression) {
    final trimmedLine = line.trim();
    final parts = trimmedLine.split(' ');
    final lineCharacterId = trimmedLine.contains('"') &&
            !trimmedLine.startsWith('"') &&
            parts.isNotEmpty
        ? parts[0]
        : null;
    final writeCharacterId = (lineCharacterId != null &&
            _isCharacterIdCompatible(
              lineCharacterId: lineCharacterId,
              expectedCharacterId: characterId,
            ))
        ? lineCharacterId
        : characterId;

    // 如果已经包含该角色的信息，更新它
    if (lineCharacterId != null &&
        _isCharacterIdCompatible(
          lineCharacterId: lineCharacterId,
          expectedCharacterId: characterId,
        )) {
      // 识别不同格式
      if (parts.length >= 4 && parts[3].startsWith('"')) {
        // 格式: character pose expression "dialogue"
        if (newPose != null) parts[1] = newPose;
        if (newExpression != null) parts[2] = newExpression;
        parts[0] = writeCharacterId;
        return parts.join(' ');
      } else if (parts.length >= 3 && parts[2].startsWith('"')) {
        // 格式: character expression "dialogue" 或 character pose "dialogue"
        // 需要扩展为三段式
        final dialoguePart = parts.sublist(2).join(' ');
        final currentPose = newPose ?? 'pose1'; // 默认pose
        final currentExpression = newExpression ?? parts[1]; // 保持原有或使用新的
        return '$writeCharacterId $currentPose $currentExpression $dialoguePart';
      } else if (parts.length >= 2 && parts[1].startsWith('"')) {
        // 格式: character "dialogue"
        // 插入pose和表情
        final pose = newPose ?? 'pose1';
        final expression = newExpression ?? 'normal';
        return '$writeCharacterId $pose $expression ${parts.sublist(1).join(' ')}';
      }
    }

    // 如果是纯对话格式，添加角色、pose和表情信息
    if (trimmedLine.startsWith('"') && trimmedLine.endsWith('"')) {
      final pose = newPose ?? 'pose1';
      final expression = newExpression ?? 'normal';
      return '$writeCharacterId $pose $expression $trimmedLine';
    }

    // 其他情况，尝试智能添加
    if (trimmedLine.contains('"')) {
      final quoteIndex = trimmedLine.indexOf('"');
      final pose = newPose ?? 'pose1';
      final expression = newExpression ?? 'normal';
      return '${trimmedLine.substring(0, quoteIndex)}$writeCharacterId $pose $expression ${trimmedLine.substring(quoteIndex)}';
    }

    // 如果无法识别格式，返回原始行
    return line;
  }

  /// 修改指定对话行的pose和表情信息
  /// 支持同时修改pose和expression
  static Future<bool> modifyDialogueLineWithPose({
    required String scriptFilePath,
    required String targetDialogue,
    required String characterId,
    String? newPose,
    String? newExpression,
  }) async {
    try {
      if (kEngineDebugMode) {
        print('ScriptModifier: 开始修改对话行');
        print('ScriptModifier: 文件路径: $scriptFilePath');
        print('ScriptModifier: 目标对话: "$targetDialogue"');
        print('ScriptModifier: 角色ID: $characterId');
        print('ScriptModifier: 新pose: $newPose');
        print('ScriptModifier: 新expression: $newExpression');
      }

      final file = File(scriptFilePath);
      if (!await file.exists()) {
        if (kEngineDebugMode) {
          print('ScriptModifier: 文件不存在');
        }
        return false;
      }

      final content = await file.readAsString();
      final lines = content.split('\n');
      bool modified = false;

      if (kEngineDebugMode) {
        print('ScriptModifier: 读取到 ${lines.length} 行脚本');
      }

      for (int i = 0; i < lines.length; i++) {
        final originalLine = lines[i];
        final line = originalLine.trim();

        // 检查是否包含对话的关键部分（不含引号和特殊符号）
        final dialogueCore = targetDialogue
            .replaceAll('"', '')
            .replaceAll('「', '')
            .replaceAll('」', '');
        if (kEngineDebugMode && line.contains(dialogueCore)) {
          print('ScriptModifier: 找到包含关键词的行 $i: "$line"');
        }

        // 检查是否是包含目标对话的行，同时验证角色ID
        if (_isTargetDialogueLine(line, targetDialogue, characterId)) {
          if (kEngineDebugMode) {
            print('ScriptModifier: 确认匹配行 $i: "$line"');
          }

          final modifiedLine =
              _modifyDialogueLine(line, characterId, newPose, newExpression);
          if (modifiedLine != line) {
            lines[i] = originalLine.replaceFirst(line, modifiedLine);
            modified = true;

            if (kEngineDebugMode) {
              print('ScriptModifier: 修改对话行（pose+expression）');
              print('ScriptModifier: 原始行: $line');
              print('ScriptModifier: 修改后: $modifiedLine');
            }
            break; // 只修改第一个匹配的行
          } else {
            if (kEngineDebugMode) {
              print('ScriptModifier: 修改后的行与原始行相同，无需更改');
            }
          }
        }
      }

      if (modified) {
        final modifiedContent = lines.join('\n');
        await _writeScriptFile(file, modifiedContent);

        if (kEngineDebugMode) {
          print('ScriptModifier: 成功保存修改的脚本文件（pose+expression）');
        }
        return true;
      } else {
        if (kEngineDebugMode) {
          print('ScriptModifier: 未找到匹配的对话行或无需修改');
        }
      }

      return false;
    } catch (e) {
      if (kEngineDebugMode) {
        print('ScriptModifier: 修改对话行失败: $e');
      }
      return false;
    }
  }

  /// 写入脚本文件，使用多种方法确保成功
  static Future<void> _writeScriptFile(File file, String content) async {
    bool writeSuccess = false;
    String lastError = '';

    // 方法1: 直接文件写入
    try {
      await file.writeAsString(content);
      writeSuccess = true;
      if (kEngineDebugMode) {
        print('脚本修改器: 直接文件写入成功');
      }
    } catch (e) {
      lastError = '直接写入失败: $e';
      if (kEngineDebugMode) {
        print('脚本修改器: $lastError');
      }
    }

    if (!writeSuccess) {
      // 方法2: 使用临时文件 + 移动
      try {
        final tempFile = File('${file.path}.tmp');
        await tempFile.writeAsString(content);
        await tempFile.rename(file.path);
        writeSuccess = true;
        if (kEngineDebugMode) {
          print('脚本修改器: 临时文件写入成功');
        }
      } catch (e) {
        lastError += ', 临时文件写入失败: $e';
        if (kEngineDebugMode) {
          print('脚本修改器: 临时文件写入失败: $e');
        }
      }
    }

    if (!writeSuccess) {
      // 方法3: 使用命令行
      try {
        // 转义特殊字符
        final escapedContent = content
            .replaceAll('\\', '\\\\')
            .replaceAll('\$', '\\\$')
            .replaceAll('"', '\\"');

        final result = await Process.run('sh', [
          '-c',
          'printf "%s" "\$1" > "\$2"',
          '--',
          escapedContent,
          file.path,
        ]);

        if (result.exitCode == 0) {
          writeSuccess = true;
          if (kEngineDebugMode) {
            print('脚本修改器: 命令行写入成功');
          }
        } else {
          lastError += ', 命令行写入失败: ${result.stderr}';
        }
      } catch (e) {
        lastError += ', 命令行写入异常: $e';
      }
    }

    if (!writeSuccess) {
      throw Exception('所有写入方法均失败: $lastError');
    }
  }

  /// 获取当前脚本文件路径
  static Future<String?> getCurrentScriptFilePath(String scriptName) async {
    try {
      // 获取游戏路径
      final gamePath = await _getGamePathFromAssetManager();
      if (gamePath == null) return null;

      final candidateDirs = GameScriptLocalization.candidateDirectories();
      for (final dirName in candidateDirs) {
        final scriptPath =
            p.join(gamePath, dirName, 'labels', '$scriptName.sks');
        final scriptFile = File(scriptPath);

        if (await scriptFile.exists()) {
          return scriptPath;
        }
      }

      if (kEngineDebugMode) {
        print(
            '脚本修改器: 未找到脚本文件 $scriptName.sks (尝试目录: ${candidateDirs.join(', ')})');
      }
      return null;
    } catch (e) {
      if (kEngineDebugMode) {
        print('脚本修改器: 获取脚本文件路径失败: $e');
      }
      return null;
    }
  }

  /// 从AssetManager获取游戏路径
  static Future<String?> _getGamePathFromAssetManager() async {
    try {
      final gamePath = await GamePathResolver.resolveGamePath();
      if (gamePath != null && gamePath.isNotEmpty) {
        if (kEngineDebugMode) {
          print("脚本修改器: 解析到游戏路径: $gamePath");
        }
        return gamePath;
      }
    } catch (e) {
      if (kEngineDebugMode) {
        print('脚本修改器: 无法获取游戏路径: $e');
      }
    }
    return null;
  }
}
