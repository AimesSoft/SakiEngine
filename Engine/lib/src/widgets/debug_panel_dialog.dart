import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';

class DebugPanelDialog extends StatefulWidget {
  final VoidCallback onClose;

  const DebugPanelDialog({
    super.key,
    required this.onClose,
  });

  @override
  State<DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<DebugPanelDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _logScrollController = ScrollController();
  String _engineVersion = '加载中...';
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEngineVersion();
    
    // 自动滚动到日志底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  Future<void> _loadEngineVersion() async {
    try {
      final pubspecContent = await rootBundle.loadString('pubspec.yaml');
      // 简单的字符串解析，查找 "version: " 行
      final lines = pubspecContent.split('\n');
      for (final line in lines) {
        if (line.trim().startsWith('version:')) {
          final version = line.split(':')[1].trim();
          setState(() {
            _engineVersion = version;
          });
          return;
        }
      }
      setState(() {
        _engineVersion = '未找到';
      });
    } catch (e) {
      setState(() {
        _engineVersion = '读取失败: $e';
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return OverlayScaffold(
      title: '调试面板',
      onClose: (_) => widget.onClose(),
      content: Column(
        children: [
          // 标签页
          _buildTabBar(config, scale),
          
          // 内容区域
          Expanded(
            child: Focus(
              canRequestFocus: false,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSystemTab(config, scale),
                  _buildLogTab(config, scale),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(SakiEngineConfig config, double scale) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: config.themeColors.primary,
        labelColor: config.themeColors.primary,
        unselectedLabelColor: config.themeColors.primary.withOpacity(0.6),
        labelStyle: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: 16 * scale,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: '系统信息'),
          Tab(text: '调试日志'),
        ],
      ),
    );
  }

  Widget _buildSystemTab(SakiEngineConfig config, double scale) {
    return Padding(
      padding: EdgeInsets.all(20 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSystemInfoCard(config, scale),
          SizedBox(height: 16 * scale),
          _buildQuickActionsCard(config, scale),
        ],
      ),
    );
  }

  Widget _buildSystemInfoCard(SakiEngineConfig config, double scale) {
    return Expanded(
      flex: 3,
      child: Container(
        padding: EdgeInsets.all(16 * scale),
        decoration: BoxDecoration(
          color: config.themeColors.primaryDark.withOpacity(0.05),
          border: Border.all(
            color: config.themeColors.primary.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '系统信息',
              style: TextStyle(
                fontFamily: 'SourceHanSansCN',
                fontSize: 16 * scale,
                color: config.themeColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12 * scale),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('引擎版本', _engineVersion, config, scale),
                    _buildInfoRow('平台', Platform.operatingSystem, config, scale),
                    _buildInfoRow('操作系统版本', Platform.operatingSystemVersion, config, scale),
                    _buildInfoRow('CPU 架构', _getCpuArchitecture(), config, scale),
                    _buildInfoRow('Dart 版本', Platform.version.split(' ')[0], config, scale),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(SakiEngineConfig config, double scale) {
    return Expanded(
      flex: 2,
      child: Container(
        padding: EdgeInsets.all(16 * scale),
        decoration: BoxDecoration(
          color: config.themeColors.primaryDark.withOpacity(0.05),
          border: Border.all(
            color: config.themeColors.primary.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速操作',
              style: TextStyle(
                fontFamily: 'SourceHanSansCN',
                fontSize: 16 * scale,
                color: config.themeColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12 * scale),
            Expanded(
              child: Column(
                children: [
                  _buildActionButton(
                    '打开存档文件夹',
                    Icons.folder_open,
                    _openSaveDirectory,
                    config,
                    scale,
                  ),
                  SizedBox(height: 8 * scale),
                  _buildActionButton(
                    '清理日志记录',
                    Icons.clear_all,
                    _clearLogs,
                    config,
                    scale,
                  ),
                  SizedBox(height: 8 * scale),
                  _buildActionButton(
                    '复制系统信息',
                    Icons.copy,
                    _copySystemInfo,
                    config,
                    scale,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogTab(SakiEngineConfig config, double scale) {
    return Container(
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        children: [
          // 日志控制栏
          Row(
            children: [
              Text(
                '调试日志',
                style: TextStyle(
                  fontFamily: 'SourceHanSansCN',
                  fontSize: 16 * scale,
                  color: config.themeColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyLogs,
                icon: Icon(
                  Icons.copy,
                  size: 16 * scale,
                  color: config.themeColors.primary,
                ),
                label: Text(
                  '复制日志',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    color: config.themeColors.primary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _generateTestLogs,
                icon: Icon(
                  Icons.bug_report,
                  size: 16 * scale,
                  color: config.themeColors.primary,
                ),
                label: Text(
                  '测试日志',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    color: config.themeColors.primary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _clearLogs,
                icon: Icon(
                  Icons.clear_all,
                  size: 16 * scale,
                  color: config.themeColors.primary,
                ),
                label: Text(
                  '清空',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    color: config.themeColors.primary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _scrollToBottom,
                icon: Icon(
                  Icons.arrow_downward,
                  size: 16 * scale,
                  color: config.themeColors.primary,
                ),
                label: Text(
                  '底部',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    color: config.themeColors.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          
          // 日志内容区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                border: Border.all(
                  color: config.themeColors.primary.withOpacity(0.3),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildLogContent(config, scale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogContent(SakiEngineConfig config, double scale) {
    return StreamBuilder<List<String>>(
      stream: DebugLogger.instance.logStream,
      initialData: DebugLogger.instance.logs, // 添加初始数据
      builder: (context, snapshot) {
        final logs = snapshot.data ?? DebugLogger.instance.logs;
        
        // 在数据更新时自动滚动到底部
        if (logs.isNotEmpty && snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScrollController.hasClients) {
              _logScrollController.animateTo(
                _logScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          });
        }
        
        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48 * scale,
                  color: Colors.grey,
                ),
                SizedBox(height: 12 * scale),
                Text(
                  '暂无日志记录',
                  style: TextStyle(
                    fontSize: 16 * scale,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  '应用运行时的调试信息会显示在这里',
                  style: TextStyle(
                    fontSize: 12 * scale,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _logScrollController,
          padding: EdgeInsets.all(12 * scale),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return Container(
              margin: EdgeInsets.only(bottom: 2 * scale),
              padding: EdgeInsets.symmetric(
                horizontal: 8 * scale,
                vertical: 4 * scale,
              ),
              decoration: BoxDecoration(
                color: _getLogBackgroundColor(log).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4 * scale),
                border: Border.all(
                  color: _getLogColor(log).withOpacity(0.2),
                  width: 0.5,
                ),
              ),
              child: SelectableText(
                log,
                style: TextStyle(
                  fontFamily: 'Monaco',
                  fontSize: 12 * scale,
                  color: _getLogColor(log),
                  height: 1.3,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, SakiEngineConfig config, double scale) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100 * scale,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14 * scale,
                color: config.themeColors.primary.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14 * scale,
                color: config.themeColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    VoidCallback onPressed,
    SakiEngineConfig config,
    double scale,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16 * scale),
        label: Text(
          text,
          style: TextStyle(fontSize: 14 * scale),
        ),
        style: ElevatedButton.styleFrom(
          foregroundColor: config.themeColors.background,
          backgroundColor: config.themeColors.primary.withOpacity(0.8),
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scale,
            vertical: 8 * scale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('[ERROR]')) return Colors.red[300]!;
    if (log.contains('[WARN]')) return Colors.orange[300]!;
    if (log.contains('[INFO]')) return Colors.blue[300]!;
    if (log.contains('[DEBUG]')) return Colors.grey[400]!;
    return Colors.green[300]!;
  }

  Color _getLogBackgroundColor(String log) {
    if (log.contains('[ERROR]')) return Colors.red;
    if (log.contains('[WARN]')) return Colors.orange;
    if (log.contains('[INFO]')) return Colors.blue;
    if (log.contains('[DEBUG]')) return Colors.grey;
    return Colors.green;
  }

  String _getCpuArchitecture() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'Unknown';
    }
  }

  void _generateTestLogs() {
    DebugLogger.instance.log("生成测试日志开始");
    DebugLogger.instance.log("[INFO] 这是一条信息级别的日志");
    DebugLogger.instance.log("[WARN] 这是一条警告级别的日志");
    DebugLogger.instance.log("[ERROR] 这是一条错误级别的日志");
    DebugLogger.instance.log("[DEBUG] 这是一条调试级别的日志");
    DebugLogger.instance.log("普通日志消息");
    
    // 也通过print函数测试
    print("通过print函数输出的测试日志");
    print("[INFO] 通过print输出的信息日志");
    
    DebugLogger.instance.log("测试日志生成完成");
  }

  void _scrollToBottom() {
    if (_logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearLogs() {
    DebugLogger.instance.clear();
  }

  Future<void> _copyLogs() async {
    final logs = DebugLogger.instance.logs;
    if (logs.isEmpty) {
      DebugLogger.instance.log('暂无日志可复制');
      return;
    }
    
    final logText = logs.join('\n');
    await Clipboard.setData(ClipboardData(text: logText));
    DebugLogger.instance.log('已复制 ${logs.length} 条日志到剪贴板');
  }

  Future<void> _openSaveDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savesBaseDir = '${directory.path}/SakiEngine/Saves';
      
      if (Platform.isMacOS) {
        await Process.run('open', [savesBaseDir]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [savesBaseDir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [savesBaseDir]);
      }
      
      DebugLogger.instance.log('已打开存档文件夹: $savesBaseDir');
    } catch (e) {
      DebugLogger.instance.log('[ERROR] 打开存档文件夹失败: $e');
    }
  }

  Future<void> _copySystemInfo() async {
    final info = '''
引擎版本: $_engineVersion
平台: ${Platform.operatingSystem}
操作系统版本: ${Platform.operatingSystemVersion}
CPU 架构: ${_getCpuArchitecture()}
Dart 版本: ${Platform.version.split(' ')[0]}
''';
    
    await Clipboard.setData(ClipboardData(text: info));
    DebugLogger.instance.log('系统信息已复制到剪贴板');
  }
}
