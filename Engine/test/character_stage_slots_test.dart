import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/screens/game_play_screen.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameManager> stage(String config, String script) async {
    final manager = GameManager();
    addTearDown(manager.dispose);
    await manager.startTestScript(
      SksParser().parse(script),
      characterConfigs: ConfigParser().parseCharacters(config),
    );
    var reachedChoice = false;
    for (var attempt = 0; attempt < 20 && !reachedChoice; attempt++) {
      reachedChoice = await manager.jumpToNextChoice();
      if (!reachedChoice) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    expect(reachedChoice, isTrue);
    return manager;
  }

  test('independent slots sharing art all reach the stage renderer', () async {
    final manager = await stage(
      '''
a : "A" : actor slot:left
b : "B" : actor slot:middle
c : "C" : actor slot:right
''',
      '''
show a pose1 happy at pose
show b pose1 happy at pose
show c pose1 happy at pose
menu
"continue" end
endmenu
''',
    );
    final entries = characterStageEntries(manager.currentState.characters);
    expect(entries.map((entry) => entry.key), [
      'slot:left',
      'slot:middle',
      'slot:right',
    ]);
    expect(
      entries.map((entry) => characterCompositeRenderKey(entry.key)).toSet(),
      hasLength(3),
    );
  });

  test(
    'changing a shared slot body still renders only its newest body',
    () async {
      final manager = await stage(
        '''
a : "A" : actor slot:person
b : "A" : actor_side slot:person
''',
        '''
show a pose1 happy at pose
show b pose1 normal at pose
menu
"continue" end
endmenu
''',
      );
      final entries = characterStageEntries(manager.currentState.characters);
      expect(entries, hasLength(1));
      expect(entries.single.value.resourceId, 'actor_side');
    },
  );

  test(
    'legacy aliases sharing a resource remain a single rendered body',
    () async {
      final manager = await stage(
        '''
a : "A" : actor
b : "B" : actor
''',
        '''
show a pose1 happy at pose
show b pose1 normal at pose
menu
"continue" end
endmenu
''',
      );
      final entries = characterStageEntries(manager.currentState.characters);
      expect(entries, hasLength(1));
      expect(entries.single.key, 'actor');
      expect(entries.single.value.expression, 'normal');
    },
  );
}
