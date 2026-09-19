import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';
import 'package:sakiengine/src/utils/read_text_skip_manager.dart';
import 'package:sakiengine/src/utils/read_text_tracker.dart';

/// 回归测试：快进（跳过已读文本）在"当前没有对白可推进"时必须保持有界。
///
/// 旧实现里，定时器每 100ms 触发一次 `_performSkipStep`，而"暂无对白"分支还会
/// 再排一个 50ms 的自递归回调。每次定时器 tick 都会拉起一条独立的递归链，链只
/// 在 `_isSkipping` 结束时才消失，于是调用频率随快进时长不断增长（总工作量呈
/// 平方级），最终把 UI 线程占满：画面不再刷新、点击毫无反应，只能强杀进程。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stalling without dialogue keeps skip steps bounded and stops', (
    tester,
  ) async {
    final gameManager = GameManager();
    addTearDown(gameManager.dispose);

    // 只有一个背景节点：执行结束后状态里没有任何对白，正好命中"暂无对白"分支。
    await gameManager.startTestScript(ScriptNode([BackgroundNode('sky')]));
    expect(gameManager.currentState.dialogue, isNull);
    expect(gameManager.currentState.nvlDialogues, isEmpty);

    var canSkipCalls = 0;
    final skipManager = ReadTextSkipManager(
      gameManager: gameManager,
      dialogueProgressionManager: DialogueProgressionManager(
        gameManager: gameManager,
      ),
      readTextTracker: ReadTextTracker.instance,
      canSkip: () {
        canSkipCalls++;
        return true;
      },
    );
    addTearDown(skipManager.dispose);

    skipManager.startSkipping();
    expect(skipManager.isSkipping, isTrue);

    await tester.pump(const Duration(seconds: 5));

    // 每 100ms 最多一次尝试：40 次空闲上限 + 启动时的一次，远小于允许上限。
    // 旧实现每次 tick 都会新增一条自递归链，同一时间窗里会产生数千次调用。
    expect(canSkipCalls, lessThan(120));
    // 长时间没有可推进的对白时主动停止，而不是继续空转烧掉 UI 线程。
    expect(skipManager.isSkipping, isFalse);
  });

  testWidgets('skip stops as soon as it reaches unread dialogue', (
    tester,
  ) async {
    final gameManager = GameManager();
    addTearDown(gameManager.dispose);
    await gameManager.startTestScript(
      ScriptNode([
        SayNode(dialogue: '从未读过的台词'),
        SayNode(dialogue: '下一句'),
      ]),
    );

    // 注意：不调用 ReadTextTracker.markAsRead，避免测试写入真实存档目录。
    final skipManager = ReadTextSkipManager(
      gameManager: gameManager,
      dialogueProgressionManager: DialogueProgressionManager(
        gameManager: gameManager,
      ),
      readTextTracker: ReadTextTracker.instance,
      canSkip: () => true,
    );
    addTearDown(skipManager.dispose);

    skipManager.startSkipping();
    await tester.pump(const Duration(milliseconds: 250));

    // 已读快进遇到未读文本必须停下，并停留在这一句上等待玩家点击。
    expect(skipManager.isSkipping, isFalse);
    expect(gameManager.currentState.dialogue, '从未读过的台词');
  });
}
