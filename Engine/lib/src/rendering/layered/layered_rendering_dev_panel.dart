/// 层叠渲染系统开发者工具
/// 
/// 提供渲染系统调试、性能监控和测试功能
library layered_rendering_dev_tools;

import 'dart:async';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/rendering/rendering_system_integration.dart';
import 'package:sakiengine/src/rendering/layered/rendering_performance_test.dart';
import 'package:sakiengine/src/rendering/layered/layer_types.dart';

/// 层叠渲染开发者面板
class LayeredRenderingDevPanel extends StatefulWidget {
  final GameManager gameManager;
  final VoidCallback? onClose;

  const LayeredRenderingDevPanel({
    super.key,
    required this.gameManager,
    this.onClose,
  });

  @override
  State<LayeredRenderingDevPanel> createState() => _LayeredRenderingDevPanelState();
}

class _LayeredRenderingDevPanelState extends State<LayeredRenderingDevPanel>
    with TickerProviderStateMixin {
  
  late final TabController _tabController;
  final RenderingSystemManager _renderingSystem = RenderingSystemManager();
  final RenderingPerformanceTester _performanceTester = RenderingPerformanceTester();
  
  Timer? _statsTimer;
  Map<String, dynamic> _currentStats = {};
  bool _isRunningTest = false;
  String _testStatus = '';
  double _testProgress = 0.0;
  Map<RenderingSystemType, PerformanceTestResult>? _lastTestResults;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _startStatsMonitoring();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _stopStatsMonitoring();
    super.dispose();
  }

  void _startStatsMonitoring() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentStats = _renderingSystem.getPerformanceStats();
        });
      }
    });
  }

  void _stopStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: Container(
        width: 800,
        height: 600,
        child: Column(
          children: [
            // 标题栏
            _buildTitleBar(),
            
            // 标签栏
            TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(text: '系统状态'),
                Tab(text: '性能测试'),
                Tab(text: '缓存管理'),
                Tab(text: '调试信息'),
              ],
            ),
            
            // 内容区域
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSystemStatusTab(),
                  _buildPerformanceTestTab(),
                  _buildCacheManagementTab(),
                  _buildDebugInfoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildTitleBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Colors.white24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Colors.blue, size: 24),
          const SizedBox(width: 8),
          const Text(
            '层叠渲染开发者工具',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 构建系统状态标签页
  Widget _buildSystemStatusTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 渲染系统选择
          _buildSystemSelector(),
          const SizedBox(height: 16),
          
          // 实时性能指标
          _buildPerformanceMetrics(),
          const SizedBox(height: 16),
          
          // 系统控制按钮
          _buildSystemControls(),
        ],
      ),
    );
  }

  /// 构建系统选择器
  Widget _buildSystemSelector() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '渲染系统',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RenderingSystemType>(
              value: _renderingSystem.currentSystem,
              dropdownColor: Colors.grey[800],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                fillColor: Colors.black26,
                filled: true,
              ),
              items: RenderingSystemType.values.map((system) {
                String description;
                switch (system) {
                  case RenderingSystemType.composite:
                    description = '预合成渲染 (兼容模式)';
                    break;
                  case RenderingSystemType.layered:
                    description = '层叠渲染 (高性能模式)';
                    break;
                  case RenderingSystemType.auto:
                    description = '自动选择 (智能切换)';
                    break;
                }
                return DropdownMenuItem(
                  value: system,
                  child: Text(description),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _renderingSystem.setRenderingSystem(value);
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建性能指标显示
  Widget _buildPerformanceMetrics() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '实时性能指标',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildMetricRow('当前系统', _renderingSystem.currentSystem.name),
            _buildMetricRow('平均渲染时间', '${(_currentStats['avg_render_time_ms'] ?? 0).toStringAsFixed(1)}ms'),
            _buildMetricRow('估计FPS', '${(_currentStats['estimated_fps'] ?? 0).toStringAsFixed(1)}'),
            _buildMetricRow('渲染样本', '${_currentStats['render_sample_count'] ?? 0}'),
            if (_currentStats['layered_system'] != null) ...[
              const Divider(color: Colors.white24),
              const Text(
                '层叠系统专项指标',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildMetricRow('活跃图层', '${_currentStats['layered_system']['active_layers'] ?? 0}'),
              _buildMetricRow('缓存命中率', '${((_currentStats['layered_system']['cache_hit_rate'] ?? 0) * 100).toStringAsFixed(1)}%'),
              _buildMetricRow('GPU内存', '${((_currentStats['layered_system']['gpu_memory_usage'] ?? 0) / 1024 / 1024).toStringAsFixed(1)}MB'),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建指标行
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 构建系统控制按钮
  Widget _buildSystemControls() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '系统控制',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _renderingSystem.clearAllCache();
                    _showSnackBar('已清除所有缓存');
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('清除缓存'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _renderingSystem.performMaintenance();
                    _showSnackBar('系统维护完成');
                  },
                  icon: const Icon(Icons.build),
                  label: const Text('系统维护'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentStats = _renderingSystem.getPerformanceStats();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新状态'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建性能测试标签页
  Widget _buildPerformanceTestTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 测试控制
          _buildTestControls(),
          const SizedBox(height: 16),
          
          // 测试进度
          if (_isRunningTest) _buildTestProgress(),
          
          // 测试结果
          if (_lastTestResults != null) _buildTestResults(),
        ],
      ),
    );
  }

  /// 构建测试控制
  Widget _buildTestControls() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '性能基准测试',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '对比不同渲染系统的性能表现，包括快进场景的压力测试。',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRunningTest ? null : _runPerformanceTest,
              icon: _isRunningTest 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              label: Text(_isRunningTest ? '测试进行中...' : '开始性能测试'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建测试进度
  Widget _buildTestProgress() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '测试进度',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_testStatus, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _testProgress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建测试结果
  Widget _buildTestResults() {
    return Expanded(
      child: Card(
        color: Colors.grey[900],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '测试结果',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _performanceTester.generateComparisonReport(_lastTestResults!),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建缓存管理标签页
  Widget _buildCacheManagementTab() {
    return const Center(
      child: Text(
        '缓存管理功能开发中...',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  /// 构建调试信息标签页
  Widget _buildDebugInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '系统详细信息',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatDebugInfo(_renderingSystem.getDetailedSystemInfo()),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 运行性能测试
  Future<void> _runPerformanceTest() async {
    setState(() {
      _isRunningTest = true;
      _testProgress = 0.0;
      _testStatus = '准备测试...';
      _lastTestResults = null;
    });

    _performanceTester.onProgressUpdate = (status, progress) {
      if (mounted) {
        setState(() {
          _testStatus = status;
          _testProgress = progress;
        });
      }
    };

    try {
      final results = await _performanceTester.runFullTestSuite(
        context: context,
        gameManager: widget.gameManager,
      );

      if (mounted) {
        setState(() {
          _lastTestResults = results;
          _isRunningTest = false;
        });
      }

      _showSnackBar('性能测试完成！');

    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunningTest = false;
          _testStatus = '测试失败: $e';
        });
      }
      
      _showSnackBar('测试失败: $e');
    }
  }

  /// 格式化调试信息
  String _formatDebugInfo(Map<String, dynamic> info) {
    return info.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
  }

  /// 显示通知
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }
}