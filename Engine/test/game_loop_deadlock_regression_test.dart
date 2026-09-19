import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/effects/scene_transition_effects.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/widgets/common/black_screen_transition.dart';
import 'package:sakiengine/src/widgets/typewriter_animation_manager.dart';

/// 回归测试：修复"剧情永久卡住 / 文字不显示 / 点击无反应"这一类锁死问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fast-forward', () {
    testWidgets('resumes the story after a timed movie node', (tester) async {
      // 快进时遇到带 timer 的视频节点：旧实现只启动计时器却没有举起等待锁，
      // 计时器回调因此直接失效，剧情永远停在视频节点上——画面没有对白，
      // 点击也推进不了（正是玩家反馈的"快进卡死"）。
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        ScriptNode([
          SayNode(dialogue: '视频之前'),
          MovieNode('opening.mkv', timer: 0.1),
          SayNode(dialogue: '视频之后'),
        ]),
      );
      expect(manager.currentState.dialogue, '视频之前');

      manager.setFastForwardMode(true);
      manager.next();
      await tester.pump();

      expect(manager.currentState.movieFile, 'opening.mkv');
      // 必须先把索引推进到视频之后，等待才有意义。
      expect(manager.currentScriptIndex, 2);

      await tester.pump(const Duration(milliseconds: 200));

      expect(manager.currentState.dialogue, '视频之后');
      expect(manager.currentScriptIndex, 3);
    });
  });

  group('transitions', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      return hostContext;
    }

    testWidgets('a request during an active transition still commits', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      final manager = SceneTransitionEffectManager.instance;
      var firstMid = 0;
      var secondMid = 0;

      final first = manager.transition(
        context: context,
        transitionType: TransitionType.fade,
        duration: const Duration(milliseconds: 200),
        onMidTransition: () => firstMid++,
      );
      await tester.pump();
      expect(manager.isTransitioning, isTrue);

      // 旧实现直接 return：既不提交场景切换，也不让调用方的 Future 完成，
      // 于是 await 它的剧情执行器会永远挂起。
      final second = manager.transition(
        context: context,
        transitionType: TransitionType.fade,
        duration: const Duration(milliseconds: 200),
        onMidTransition: () => secondMid++,
      );
      await tester.pump();
      await second;
      expect(secondMid, 1);

      await tester.pumpAndSettle();
      await first;
      expect(firstMid, 1);
      expect(manager.isTransitioning, isFalse);
    });

    testWidgets('a failing frame capture still completes the transition', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      final manager = SceneTransitionEffectManager.instance;
      var midTransitions = 0;

      // 旧实现里 _isTransitioning 在捕获帧之前就被置真，捕获抛异常后它永远
      // 停在 true：此后所有转场都会被静默丢弃，剧情再也无法恢复。
      final pending = manager.transition(
        context: context,
        transitionType: TransitionType.pixel,
        duration: const Duration(milliseconds: 100),
        captureFrame: () async => throw StateError('capture failed'),
        onMidTransition: () => midTransitions++,
      );

      await tester.pump();
      await pending;

      expect(midTransitions, 1);
      expect(manager.isTransitioning, isFalse);
    });

    testWidgets('movie transition manager commits while one is running', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      final manager = TransitionOverlayManager.instance;
      var firstMid = 0;
      var secondMid = 0;

      final first = manager.transition(
        context: context,
        duration: const Duration(milliseconds: 200),
        onMidTransition: () => firstMid++,
      );
      await tester.pump();

      final second = manager.transition(
        context: context,
        duration: const Duration(milliseconds: 200),
        onMidTransition: () => secondMid++,
      );
      await tester.pump();
      await second;

      // 视频播放结束时靠这个回调清掉 movie 状态并恢复脚本；被丢弃就意味着
      // 视频状态永远清不掉、剧情再也走不下去。
      expect(secondMid, 1);

      await tester.pumpAndSettle();
      await first;
      expect(firstMid, 1);
      expect(manager.isTransitioning, isFalse);
    });
  });

  group('typewriter', () {
    testWidgets('TypewriterText follows a swapped controller', (tester) async {
      // NVL 每换一行都会传入新的 controller，并把旧的 dispose。旧实现只在
      // text 变化时更新，界面会继续渲染那个已经被丢弃的 controller（永远空白），
      // 而推进管理器里注册的却是新 controller（一直 isTyping）——"文字不显示
      // + 点击毫无反应"。
      final first = TypewriterAnimationManager();
      final second = TypewriterAnimationManager();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget host(String text, TypewriterAnimationManager controller) {
        return MaterialApp(
          home: Scaffold(
            body: TypewriterText(text: text, controller: controller),
          ),
        );
      }

      await tester.pumpWidget(host('第一行', first));
      await tester.pump();
      expect(first.displayedText, '第一行');

      await tester.pumpWidget(host('第二行', second));
      await tester.pump();

      // 新 controller 必须被真正使用；旧实现下它始终是空字符串。
      expect(second.displayedText, '第二行');
    });

    testWidgets('startTyping still shows text without a ticker', (
      tester,
    ) async {
      // 没有 initialize()（拿不到 Ticker）时不能停在 typing 状态：否则这一行
      // 永远不显示，玩家点击也只会被"跳字"吞掉。
      final controller = TypewriterAnimationManager();
      addTearDown(controller.dispose);

      controller.startTyping('没有 ticker 也要显示');

      expect(controller.isTyping, isFalse);
      expect(controller.displayedText, '没有 ticker 也要显示');
    });
  });
}
