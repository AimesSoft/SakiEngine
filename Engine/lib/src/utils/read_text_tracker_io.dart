import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 已读文本跟踪器
///
/// 记录哪些对话文本已经被用户阅读过，用于实现"跳过已读文本"功能
/// 与现有的Ctrl强制快进功能区分开来
class ReadTextTracker extends ChangeNotifier {
  static ReadTextTracker? _instance;
  static ReadTextTracker get instance => _instance ??= ReadTextTracker._();

  ReadTextTracker._();

  // 存储已读对话的标识符集合
  // 使用对话内容的哈希值作为唯一标识
  final Set<String> _readDialogues = <String>{};

  // 二进制文件配置
  static const String _fileName = 'saki.sakiread';
  static const String _magicNumber = 'SAKI';
  static const int _version = 1;

  /// 初始化，从二进制文件加载已读记录
  Future<void> initialize() async {
    //print('[ReadTextTracker] ========== 开始初始化 ==========');
    //print('[ReadTextTracker] 实例hashCode: $hashCode');
    //print('[ReadTextTracker] 初始化前已读数量: ${_readDialogues.length}');
    _readDialogues.clear(); // 确保清空任何现有数据
    //print('[ReadTextTracker] 清空后已读数量: ${_readDialogues.length}');
    await _loadFromStorage();
    //print('[ReadTextTracker] 初始化完成，最终已读数量: ${_readDialogues.length}');
    //print('[ReadTextTracker] ========== 初始化结束 ==========');
  }

  /// 标记对话为已读
  /// [speaker] 说话者名字（可选）
  /// [dialogue] 对话内容
  /// [scriptIndex] 脚本索引（用于更精确的标识）
  void markAsRead(String? speaker, String dialogue, int scriptIndex) {
    if (dialogue.trim().isEmpty) {
      //print('[ReadTextTracker] 跳过空对话');
      return;
    }

    // 创建唯一标识符，结合说话者、对话内容和脚本索引
    final identifier = _createIdentifier(speaker, dialogue, scriptIndex);
    //print('[ReadTextTracker] 生成标识符: $identifier');

    if (!_readDialogues.contains(identifier)) {
      _readDialogues.add(identifier);
      //print('[ReadTextTracker] 新增已读: $identifier (总数: ${_readDialogues.length})');
      //print('[ReadTextTracker] 当前实例hashCode: ${hashCode}');
      _saveToStorage();
      notifyListeners();
    } else {
      //print('[ReadTextTracker] 已存在，跳过: $identifier');
    }
  }

  /// 检查对话是否已读
  /// [speaker] 说话者名字（可选）
  /// [dialogue] 对话内容
  /// [scriptIndex] 脚本索引
  bool isRead(String? speaker, String dialogue, int scriptIndex) {
    if (dialogue.trim().isEmpty) return false;

    final identifier = _createIdentifier(speaker, dialogue, scriptIndex);
    final result = _readDialogues.contains(identifier);
    //print('[ReadTextTracker] 检查是否已读: "$identifier" = $result (实例${hashCode}, 总数${_readDialogues.length})');
    return result;
  }

  /// 创建对话的唯一标识符
  String _createIdentifier(String? speaker, String dialogue, int scriptIndex) {
    // 结合说话者、对话内容和脚本索引创建唯一标识
    final speakerPart = speaker ?? '';
    final content = '$speakerPart|$dialogue|$scriptIndex';

    // 使用简单的哈希算法减少存储空间
    return content.hashCode.toString();
  }

  /// 获取已读对话数量
  int get readCount => _readDialogues.length;

  /// 清除所有已读记录（删除.sakiread文件）
  Future<void> clearAllReadRecords() async {
    //print('[ReadTextTracker] 清除前: ${_readDialogues.length} 条已读记录');
    //print('[ReadTextTracker] 当前实例hashCode: ${hashCode}');

    try {
      final filePath = await _getReadFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        //print('[ReadTextTracker] 成功删除.sakiread文件: $filePath');
      } else {
        //print('[ReadTextTracker] .sakiread文件不存在，无需删除');
      }

      _readDialogues.clear();
      //print('[ReadTextTracker] 清除后: ${_readDialogues.length} 条已读记录');
      //print('[ReadTextTracker] 清除操作完成');
    } catch (e) {
      //print('[ReadTextTracker] 删除.sakiread文件失败: $e');
      // 即使删除文件失败，也清空内存中的数据
      _readDialogues.clear();
    }

    notifyListeners();
  }

  /// 获取.sakiread文件路径
  Future<String> _getReadFilePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final projectName = await _getCurrentProjectName();
      final savesDir =
          Directory('${directory.path}/SakiEngine/Saves/$projectName');
      if (!await savesDir.exists()) {
        await savesDir.create(recursive: true);
      }
      return p.join(savesDir.path, _fileName);
    } catch (e) {
      //print('[ReadTextTracker] 获取文件路径失败: $e');
      rethrow;
    }
  }

  /// 获取当前项目名称（复制自SaveLoadManager逻辑）
  Future<String> _getCurrentProjectName() async {
    try {
      final projectName = await GamePathResolver.resolveProjectName();
      if (projectName != null && projectName.isNotEmpty) {
        return projectName;
      }

      return 'DefaultProject';
    } catch (e) {
      return 'DefaultProject';
    }
  }

  /// 从二进制文件加载已读记录
  Future<void> _loadFromStorage() async {
    try {
      final filePath = await _getReadFilePath();
      final file = File(filePath);

      //print('[ReadTextTracker] 尝试加载文件: $filePath');

      if (!await file.exists()) {
        //print('[ReadTextTracker] .sakiread文件不存在，无已读记录');
        return;
      }

      final bytes = await file.readAsBytes();
      //print('[ReadTextTracker] 读取到 ${bytes.length} 字节数据');

      if (bytes.length < 12) {
        // 至少需要魔法数字(4) + 版本(4) + 计数(4)
        //print('[ReadTextTracker] 文件太小，可能损坏');
        return;
      }

      final buffer = bytes.buffer.asByteData();
      int offset = 0;

      // 检查魔法数字
      final magic = String.fromCharCodes(bytes.sublist(0, 4));
      offset += 4;
      if (magic != _magicNumber) {
        //print('[ReadTextTracker] 魔法数字不匹配: $magic');
        return;
      }

      // 检查版本
      final version = buffer.getInt32(offset, Endian.little);
      offset += 4;
      if (version != _version) {
        //print('[ReadTextTracker] 版本不匹配: $version');
        return;
      }

      // 读取已读记录数量
      final count = buffer.getInt32(offset, Endian.little);
      offset += 4;
      //print('[ReadTextTracker] 准备加载 $count 条已读记录');

      _readDialogues.clear();

      // 读取每个哈希值
      for (int i = 0; i < count; i++) {
        if (offset + 4 > bytes.length) break;
        final hashCode = buffer.getInt32(offset, Endian.little);
        offset += 4;
        _readDialogues.add(hashCode.toString());
      }

      //print('[ReadTextTracker] 从二进制文件加载: ${_readDialogues.length} 条已读记录');
    } catch (e) {
      //print('[ReadTextTracker] 加载已读记录异常: $e');
      if (kEngineDebugMode) {
        print('加载已读记录失败: $e');
      }
    }
  }

  /// 保存已读记录到二进制文件
  Future<void> _saveToStorage() async {
    try {
      final filePath = await _getReadFilePath();
      final file = File(filePath);

      // 计算所需缓冲区大小
      final bufferSize =
          4 + 4 + 4 + (_readDialogues.length * 4); // 魔法数字 + 版本 + 计数 + 哈希值数组
      final buffer = Uint8List(bufferSize);
      final byteData = buffer.buffer.asByteData();

      int offset = 0;

      // 写入魔法数字
      for (int i = 0; i < _magicNumber.length; i++) {
        buffer[offset + i] = _magicNumber.codeUnitAt(i);
      }
      offset += 4;

      // 写入版本
      byteData.setInt32(offset, _version, Endian.little);
      offset += 4;

      // 写入已读记录数量
      byteData.setInt32(offset, _readDialogues.length, Endian.little);
      offset += 4;

      // 写入所有哈希值
      for (final hashString in _readDialogues) {
        final hashCode = int.parse(hashString);
        byteData.setInt32(offset, hashCode, Endian.little);
        offset += 4;
      }

      await file.writeAsBytes(buffer);
      //print('[ReadTextTracker] 保存到二进制文件: ${_readDialogues.length} 条已读记录 ($bufferSize 字节)');
      //print('[ReadTextTracker] 文件路径: $filePath');
    } catch (e) {
      //print('[ReadTextTracker] 保存已读记录失败: $e');
      if (kEngineDebugMode) {
        print('保存已读记录失败: $e');
      }
    }
  }

  /// 导出已读记录（备份.sakiread文件）
  Map<String, dynamic> exportReadRecords() {
    return {
      'version': _version,
      'readCount': _readDialogues.length,
      'readDialogues': _readDialogues.toList(),
      'exportTime': DateTime.now().toIso8601String(),
      'storageType': 'binary_file', // 标记存储类型
    };
  }

  /// 导入已读记录（从备份恢复并保存到.sakiread文件）
  Future<void> importReadRecords(Map<String, dynamic> data) async {
    try {
      final List<dynamic> readList = data['readDialogues'] ?? [];
      _readDialogues.clear();
      _readDialogues.addAll(readList.cast<String>());
      await _saveToStorage(); // 保存到二进制文件
      notifyListeners();
      //print('[ReadTextTracker] 成功导入 ${_readDialogues.length} 条已读记录');
    } catch (e) {
      //print('[ReadTextTracker] 导入已读记录失败: $e');
      if (kEngineDebugMode) {
        print('导入已读记录失败: $e');
      }
    }
  }
}
