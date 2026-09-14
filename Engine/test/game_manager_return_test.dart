import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'return blocks further input while the title transition is pending',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      var returns = 0;
      manager.onReturn = () => returns++;
      final script = SksParser().parse('''
return
label another_route
"wrong route"
return
''');
      await manager.startTestScript(script);
      expect(returns, 1);
      for (var click = 0; click < 6; click++) {
        manager.next();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(manager.currentState.dialogue, isNot('wrong route'));
      expect(returns, 1);
      expect(manager.currentScriptIndex, script.children.length);
    },
  );

  test('an explicit label jump can start a route after return', () async {
    final manager = GameManager();
    addTearDown(manager.dispose);
    await manager.startTestScript(
      SksParser().parse('''
return
label another_route
"new route"
'''),
    );
    await manager.jumpToLabel('another_route');
    expect(manager.currentState.dialogue, 'new route');
  });
}
