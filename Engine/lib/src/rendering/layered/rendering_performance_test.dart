/// 渲染性能测试和基准验证系统
/// 
/// 用于测试和比较不同渲染系统的性能表现
library rendering_performance_test;

import 'dart:async';
import 'dart:math' as math;
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/rendering/rendering_system_integration.dart';
import 'package:sakiengine/src/rendering/composite_cg_renderer.dart';
import 'package:sakiengine/src/rendering/layered_cg_renderer.dart';
import 'package:sakiengine/src/rendering/layered/layer_types.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';

/// 性能测试结果
class PerformanceTestResult {
  /// 测试名称
  final String testName;
  
  /// 渲染系统类型
  final RenderingSystemType systemType;
  
  /// 平均渲染时间（毫秒）
  final double averageRenderTime;
  
  /// 最小渲染时间（毫秒）
  final double minRenderTime;
  
  /// 最大渲染时间（毫秒）
  final double maxRenderTime;
  
  /// 估计FPS
  final double estimatedFps;
  
  /// 内存使用量（字节）
  final int memoryUsage;
  
  /// 缓存命中率
  final double cacheHitRate;
  
  /// 测试样本数量
  final int sampleCount;
  
  /// 测试持续时间（毫秒）
  final Duration testDuration;
  
  /// 错误数量
  final int errorCount;
  
  /// 测试时间戳
  final DateTime timestamp;

  PerformanceTestResult({
    required this.testName,
    required this.systemType,
    required this.averageRenderTime,
    required this.minRenderTime,
    required this.maxRenderTime,
    required this.estimatedFps,
    required this.memoryUsage,
    required this.cacheHitRate,
    required this.sampleCount,
    required this.testDuration,
    required this.errorCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 计算性能分数（0-100）
  double get performanceScore {
    // 基于多个指标计算综合分数
    final fpsScore = math.min(estimatedFps / 60.0, 1.0) * 40; // FPS权重40%
    final renderTimeScore = math.max(0, (20 - averageRenderTime) / 20.0) * 30; // 渲染时间权重30%
    final cacheScore = cacheHitRate * 20; // 缓存命中率权重20%
    final stabilityScore = errorCount == 0 ? 10 : math.max(0, 10 - errorCount); // 稳定性权重10%
    
    return fpsScore + renderTimeScore + cacheScore + stabilityScore;
  }

  @override
  String toString() {
    return 'PerformanceTestResult($testName: ${estimatedFps.toStringAsFixed(1)}FPS, ${averageRenderTime.toStringAsFixed(1)}ms, Score: ${performanceScore.toStringAsFixed(1)})';
  }
}

/// 性能基准测试器
class RenderingPerformanceTester {
  /// 测试结果历史
  final List<PerformanceTestResult> _testHistory = [];
  
  /// 当前测试进度回调
  void Function(String status, double progress)? onProgressUpdate;

  /// 运行完整的性能测试套件
  Future<Map<RenderingSystemType, PerformanceTestResult>> runFullTestSuite({
    required BuildContext context,
    required GameManager gameManager,
  }) async {
    final results = <RenderingSystemType, PerformanceTestResult>{};
    
    // 准备测试数据
    final testScenarios = _generateTestScenarios();
    
    onProgressUpdate?.call('初始化测试环境...', 0.1);
    
    // 测试预合成系统
    onProgressUpdate?.call('测试预合成渲染系统...', 0.2);
    final compositeResult = await _testRenderingSystem(
      RenderingSystemType.composite,
      testScenarios,
      context,
      gameManager,
    );
    results[RenderingSystemType.composite] = compositeResult;
    
    // 清理缓存，确保公平比较
    RenderingSystemManager().clearAllCache();
    await Future.delayed(const Duration(milliseconds: 100));
    
    onProgressUpdate?.call('测试层叠渲染系统...', 0.6);
    final layeredResult = await _testRenderingSystem(
      RenderingSystemType.layered,
      testScenarios,
      context,
      gameManager,
    );
    results[RenderingSystemType.layered] = layeredResult;
    
    onProgressUpdate?.call('生成测试报告...', 0.9);
    
    // 保存测试结果
    _testHistory.addAll(results.values);
    
    onProgressUpdate?.call('测试完成！', 1.0);
    
    return results;
  }

  /// 测试指定渲染系统的性能
  Future<PerformanceTestResult> _testRenderingSystem(
    RenderingSystemType systemType,
    List<Map<String, CharacterState>> testScenarios,
    BuildContext context,
    GameManager gameManager,
  ) async {
    final renderTimes = <double>[];
    int errorCount = 0;
    final startTime = DateTime.now();
    
    // 设置渲染系统
    RenderingSystemManager().setRenderingSystem(systemType);
    
    // 预热阶段
    await _warmupRenderingSystem(testScenarios.first, context, gameManager);
    
    // 执行测试
    for (int i = 0; i < testScenarios.length; i++) {
      final scenario = testScenarios[i];
      
      try {
        final renderTime = await _measureSingleRender(scenario, context, gameManager);
        renderTimes.add(renderTime);
        
        // 模拟快进场景的快速切换
        if (i % 5 == 0) {
          await _testFastForwardScenario(scenario, context, gameManager);
        }
        
      } catch (e) {
        errorCount++;
        if (kEngineDebugMode) {
          print('[PerformanceTester] Render error in $systemType: $e');
        }
      }
      
      // 小幅延迟避免过载
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    final testDuration = DateTime.now().difference(startTime);
    
    // 获取系统统计
    final systemStats = RenderingSystemManager().getPerformanceStats();
    final memoryUsage = systemStats['layered_system']?['gpu_memory_usage'] ?? 0;
    final cacheHitRate = systemStats['layered_system']?['cache_hit_rate'] ?? 0.0;
    
    // 计算统计数据
    final avgRenderTime = renderTimes.isNotEmpty 
        ? renderTimes.reduce((a, b) => a + b) / renderTimes.length 
        : 0.0;
    final minRenderTime = renderTimes.isNotEmpty 
        ? renderTimes.reduce((a, b) => math.min(a, b)) 
        : 0.0;
    final maxRenderTime = renderTimes.isNotEmpty 
        ? renderTimes.reduce((a, b) => math.max(a, b)) 
        : 0.0;
    final estimatedFps = avgRenderTime > 0 ? 1000.0 / avgRenderTime : 0.0;
    
    return PerformanceTestResult(
      testName: '${systemType.name}_full_test',
      systemType: systemType,
      averageRenderTime: avgRenderTime,
      minRenderTime: minRenderTime,
      maxRenderTime: maxRenderTime,
      estimatedFps: estimatedFps,
      memoryUsage: memoryUsage,
      cacheHitRate: cacheHitRate,
      sampleCount: renderTimes.length,
      testDuration: testDuration,
      errorCount: errorCount,
    );
  }

  /// 预热渲染系统
  Future<void> _warmupRenderingSystem(
    Map<String, CharacterState> scenario,
    BuildContext context,
    GameManager gameManager,
  ) async {
    // 预热3次渲染，确保缓存系统就绪
    for (int i = 0; i < 3; i++) {
      try {
        RenderingSystemManager().buildCgCharacters(context, scenario, gameManager);
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        // 忽略预热阶段的错误
      }
    }
  }

  /// 测量单次渲染时间
  Future<double> _measureSingleRender(
    Map<String, CharacterState> scenario,
    BuildContext context,
    GameManager gameManager,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    final widgets = RenderingSystemManager().buildCgCharacters(context, scenario, gameManager);
    
    // 等待潜在的异步操作完成
    await Future.delayed(const Duration(milliseconds: 1));
    
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  /// 测试快进场景
  Future<void> _testFastForwardScenario(
    Map<String, CharacterState> baseScenario,
    BuildContext context,
    GameManager gameManager,
  ) async {
    // 快速连续切换表情，模拟快进
    final expressions = ['happy', 'sad', 'angry', 'surprised', '1', '2', '3'];
    
    for (final expression in expressions) {
      final modifiedScenario = Map<String, CharacterState>.from(baseScenario);
      for (final entry in modifiedScenario.entries) {
        modifiedScenario[entry.key] = CharacterState(
          resourceId: entry.value.resourceId,
          pose: entry.value.pose,
          expression: expression,
        );
      }
      
      await _measureSingleRender(modifiedScenario, context, gameManager);
      
      // 快进时的极短延迟
      await Future.delayed(const Duration(microseconds: 500));
    }
  }

  /// 生成测试场景
  List<Map<String, CharacterState>> _generateTestScenarios() {
    final scenarios = <Map<String, CharacterState>>[];
    
    // 单角色场景
    scenarios.addAll(_generateSingleCharacterScenarios());
    
    // 多角色场景
    scenarios.addAll(_generateMultiCharacterScenarios());
    
    // 复杂切换场景
    scenarios.addAll(_generateComplexTransitionScenarios());
    
    return scenarios;
  }

  /// 生成单角色测试场景
  List<Map<String, CharacterState>> _generateSingleCharacterScenarios() {
    final scenarios = <Map<String, CharacterState>>[];
    final expressions = ['happy', 'sad', 'angry', 'surprised', '1', '2', '3', '4', '5'];
    
    for (final expression in expressions) {
      scenarios.add({
        'test_character': CharacterState(
          resourceId: 'yk',
          pose: 'pose1',
          expression: expression,
        ),
      });
    }
    
    return scenarios;
  }

  /// 生成多角色测试场景
  List<Map<String, CharacterState>> _generateMultiCharacterScenarios() {
    return [
      // 双角色场景
      {
        'char1': CharacterState(resourceId: 'yk', pose: 'pose1', expression: 'happy'),
        'char2': CharacterState(resourceId: 'alice', pose: 'pose2', expression: 'sad'),
      },
      // 三角色场景
      {
        'char1': CharacterState(resourceId: 'yk', pose: 'pose1', expression: 'happy'),
        'char2': CharacterState(resourceId: 'alice', pose: 'pose2', expression: 'sad'),
        'char3': CharacterState(resourceId: 'bob', pose: 'pose1', expression: 'angry'),
      },
    ];
  }

  /// 生成复杂切换场景
  List<Map<String, CharacterState>> _generateComplexTransitionScenarios() {
    final scenarios = <Map<String, CharacterState>>[];
    final random = math.Random(42); // 固定种子确保可重现
    
    // 生成20个随机场景用于压力测试
    for (int i = 0; i < 20; i++) {
      final characterCount = random.nextInt(3) + 1; // 1-3个角色
      final scenario = <String, CharacterState>{};
      
      for (int j = 0; j < characterCount; j++) {
        final resourceIds = ['yk', 'alice', 'bob'];
        final poses = ['pose1', 'pose2'];
        final expressions = ['happy', 'sad', 'angry', '1', '2', '3'];
        
        scenario['char_$j'] = CharacterState(
          resourceId: resourceIds[random.nextInt(resourceIds.length)],
          pose: poses[random.nextInt(poses.length)],
          expression: expressions[random.nextInt(expressions.length)],
        );
      }
      
      scenarios.add(scenario);
    }
    
    return scenarios;
  }

  /// 获取测试历史
  List<PerformanceTestResult> get testHistory => List.unmodifiable(_testHistory);

  /// 生成性能比较报告
  String generateComparisonReport(Map<RenderingSystemType, PerformanceTestResult> results) {
    final buffer = StringBuffer();
    buffer.writeln('=== SakiEngine 渲染性能测试报告 ===');
    buffer.writeln('测试时间: ${DateTime.now()}');
    buffer.writeln('');
    
    for (final entry in results.entries) {
      final result = entry.value;
      buffer.writeln('## ${entry.key.name.toUpperCase()} 渲染系统');
      buffer.writeln('- 平均渲染时间: ${result.averageRenderTime.toStringAsFixed(2)}ms');
      buffer.writeln('- 估计FPS: ${result.estimatedFps.toStringAsFixed(1)}');
      buffer.writeln('- 最小/最大渲染时间: ${result.minRenderTime.toStringAsFixed(2)}ms / ${result.maxRenderTime.toStringAsFixed(2)}ms');
      buffer.writeln('- 内存使用: ${(result.memoryUsage / 1024 / 1024).toStringAsFixed(1)}MB');
      buffer.writeln('- 缓存命中率: ${(result.cacheHitRate * 100).toStringAsFixed(1)}%');
      buffer.writeln('- 性能分数: ${result.performanceScore.toStringAsFixed(1)}/100');
      buffer.writeln('- 错误数量: ${result.errorCount}');
      buffer.writeln('- 测试样本: ${result.sampleCount}个');
      buffer.writeln('');
    }
    
    // 性能比较
    if (results.length > 1) {
      buffer.writeln('## 性能比较');
      final sortedResults = results.entries.toList()
        ..sort((a, b) => b.value.performanceScore.compareTo(a.value.performanceScore));
      
      buffer.writeln('性能排名:');
      for (int i = 0; i < sortedResults.length; i++) {
        final result = sortedResults[i].value;
        buffer.writeln('${i + 1}. ${sortedResults[i].key.name}: ${result.performanceScore.toStringAsFixed(1)}分');
      }
      
      if (sortedResults.length == 2) {
        final winner = sortedResults[0].value;
        final loser = sortedResults[1].value;
        final fpsImprovement = ((winner.estimatedFps - loser.estimatedFps) / loser.estimatedFps * 100);
        final renderTimeImprovement = ((loser.averageRenderTime - winner.averageRenderTime) / loser.averageRenderTime * 100);
        
        buffer.writeln('');
        buffer.writeln('${sortedResults[0].key.name} 相对于 ${sortedResults[1].key.name}:');
        buffer.writeln('- FPS提升: ${fpsImprovement.toStringAsFixed(1)}%');
        buffer.writeln('- 渲染时间减少: ${renderTimeImprovement.toStringAsFixed(1)}%');
      }
    }
    
    return buffer.toString();
  }

  /// 清除测试历史
  void clearHistory() {
    _testHistory.clear();
  }
}