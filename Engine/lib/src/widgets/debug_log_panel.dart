import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';

class DebugLogPanel extends StatefulWidget {
  const DebugLogPanel({super.key});

  @override
  State<DebugLogPanel> createState() => _DebugLogPanelState();
}

class _DebugLogPanelState extends State<DebugLogPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _copyAllLogs() {
    final allLogs = DebugLogger().getAllLogsAsString();
    Clipboard.setData(ClipboardData(text: allLogs));
    
    // 显示复制成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${DebugLogger().logs.length} 条日志到剪贴板'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              DebugLogger().clear();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 头部控制栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // 拖动指示器
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.bug_report,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '调试日志 (${DebugLogger().logs.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        // 自动滚动开关
                        Row(
                          children: [
                            const Text(
                              '自动滚动',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Switch(
                              value: _autoScroll,
                              onChanged: (value) {
                                setState(() {
                                  _autoScroll = value;
                                });
                              },
                              activeColor: Colors.blue,
                            ),
                          ],
                        ),
                        // 一键复制按钮
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white),
                          onPressed: _copyAllLogs,
                          tooltip: '复制所有日志',
                        ),
                        // 清空按钮
                        IconButton(
                          icon: const Icon(Icons.clear_all, color: Colors.white),
                          onPressed: _clearLogs,
                          tooltip: '清空日志',
                        ),
                        // 关闭按钮
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 日志列表
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DebugLogger().logs.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无日志\n尝试执行一些操作来生成日志',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: DebugLogger().logs.length,
                          itemBuilder: (context, index) {
                            final log = DebugLogger().logs[index];
                            final isError = log.contains('Error') || 
                                          log.contains('Exception') || 
                                          log.contains('Failed');
                            final isWarning = log.contains('Warning') || 
                                            log.contains('WARN');
                            final isDebug = log.contains('DEBUG:');
                            
                            // 在构建完成后滚动到底部
                            if (index == DebugLogger().logs.length - 1) {
                              _scrollToBottom();
                            }
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isError 
                                    ? Colors.red.withOpacity(0.1)
                                    : isWarning 
                                        ? Colors.orange.withOpacity(0.1)
                                        : isDebug
                                            ? Colors.blue.withOpacity(0.1)
                                            : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isError 
                                      ? Colors.red.withOpacity(0.3)
                                      : isWarning 
                                          ? Colors.orange.withOpacity(0.3)
                                          : isDebug
                                              ? Colors.blue.withOpacity(0.3)
                                              : Colors.transparent,
                                  width: 0.5,
                                ),
                              ),
                              child: SelectableText(
                                log,
                                style: TextStyle(
                                  color: isError 
                                      ? Colors.red[300]
                                      : isWarning 
                                          ? Colors.orange[300]
                                          : isDebug
                                              ? Colors.blue[300]
                                              : Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}