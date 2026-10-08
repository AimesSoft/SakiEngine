import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/save_load_manager.dart';
import 'package:sakiengine/src/game/nvl_state_manager.dart';
import 'package:sakiengine/src/game/script_merger.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'support/settings_test_environment.dart';

Map<String, CharacterConfig> _names(String name) => {
  'x': CharacterConfig(id: 'x', name: name, resourceId: 'narrator'),
};
ScriptNode _adv(String text, String choice) => ScriptNode([
  SayNode(character: 'x', dialogue: '[size=0.8]$text[/size]'),
  MenuNode([ChoiceOptionNode(choice, 'next')]),
  LabelNode('next'),
  SayNode(dialogue: 'next'),
]);
ScriptNode _nvl(String first, String second) => ScriptNode([
  NvlMovieNode(),
  SayNode(character: 'x', dialogue: first),
  JumpNode('played'),
  SayNode(dialogue: 'unvisited branch'),
  LabelNode('played'),
  SayNode(dialogue: second, tailCharacter: 'x'),
  EndNvlMovieNode(),
  SayNode(dialogue: 'not displayed'),
]);
Future<void> _advance(GameManager manager, int expectedIndex) async {
  manager.next();
  for (var i = 0; i < 100 && manager.currentScriptIndex != expectedIndex; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(manager.currentScriptIndex, expectedIndex);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeSettingsTestEnvironment();
  });
  test(
    'ADV and choices translate without replaying or changing history snapshots',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        _adv('原文', '继续'),
        characterConfigs: _names('夏悠'),
      );
      final before = manager.saveStateSnapshot();
      final history = manager.getDialogueHistory().single;
      expect(before.scriptIndex, 1);
      for (final text in ['English', '日本語', '한국어']) {
        manager.refreshLocalizedScriptForTesting(
          _adv(text, '$text choice'),
          characterConfigs: _names('$text name'),
        );
        expect(manager.currentState.dialogue, '[size=0.8]$text[/size]');
        expect(manager.currentState.speaker, '$text name');
        expect(manager.currentScriptIndex, before.scriptIndex);
        final menu = manager.currentState.currentNode! as MenuNode;
        expect(menu.choices.single.text, '$text choice');
        expect(menu.choices.single.targetLabel, 'next');
        final updated = manager.getDialogueHistory().single;
        expect(updated.dialogue, text);
        expect(updated.speaker, '$text name');
        expect(updated.scriptIndex, history.scriptIndex);
        expect(updated.timestamp, history.timestamp);
        expect(
          updated.serializedStateSnapshot,
          history.serializedStateSnapshot,
        );
      }
    },
  );
  test(
    'NVLM uses played nodes across jumps and keeps page length and timestamps',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        _nvl('第一句', '第二句'),
        characterConfigs: _names('夏悠'),
      );
      await _advance(manager, 6);
      final before = manager.saveStateSnapshot();
      final times = manager.currentState.nvlDialogues
          .map((line) => line.timestamp)
          .toList();
      manager.refreshLocalizedScriptForTesting(
        _nvl('First', 'Second'),
        characterConfigs: _names('Xia You'),
      );
      expect(manager.currentState.nvlDialogues.map((line) => line.dialogue), [
        'First',
        'Second',
      ]);
      expect(manager.currentState.nvlDialogues.map((line) => line.speaker), [
        'Xia You',
        null,
      ]);
      expect(manager.currentState.nvlDialogues.last.speakerAlias, 'x');
      expect(
        manager.currentState.nvlDialogues.map((line) => line.timestamp),
        times,
      );
      expect(manager.currentState.isNvlMovieMode, before.isNvlMovieMode);
      expect(
        manager.currentState.isNvlOverlayVisible,
        before.isNvlOverlayVisible,
      );
      expect(manager.currentScriptIndex, before.scriptIndex);
      expect(manager.getDialogueHistory().map((entry) => entry.dialogue), [
        'First',
        'Second',
      ]);
      expect(manager.getDialogueHistory().map((entry) => entry.scriptIndex), [
        1,
        5,
      ]);
    },
  );
  test(
    'serialized saves refresh ADV and NVL in the current language without changing progress',
    () async {
      for (final nvl in [false, true]) {
        final manager = GameManager();
        addTearDown(manager.dispose);
        await manager.startTestScript(
          nvl ? _nvl('第一句', '第二句') : _adv('原文', '继续'),
          characterConfigs: _names('夏悠'),
        );
        if (nvl) await _advance(manager, 6);
        final oldSave = BinarySerializer.deserializeGameStateSnapshot(
          BinarySerializer.serializeGameStateSnapshot(
            manager.saveStateSnapshot(),
          ),
        );
        manager.refreshLocalizedScriptForTesting(
          nvl ? _nvl('First', 'Second') : _adv('English', 'Continue'),
          characterConfigs: _names('Xia You'),
          loadedSnapshot: oldSave,
        );
        expect(manager.currentScriptIndex, oldSave.scriptIndex);
        expect(
          manager.getDialogueHistory().length,
          oldSave.dialogueHistory.length,
        );
        expect(
          manager.getDialogueHistory().last.dialogue,
          nvl ? 'Second' : 'English',
        );
        if (nvl) {
          expect(
            manager.currentState.nvlDialogues.map((line) => line.dialogue),
            ['First', 'Second'],
          );
        } else {
          expect(manager.currentState.dialogue, '[size=0.8]English[/size]');
          expect(manager.currentState.speaker, 'Xia You');
        }
      }
    },
  );
  test(
    'legacy NVL restore stays on displayed lines and does not guess across branches',
    () {
      final time = DateTime(2020);
      final old = [
        NvlDialogue(dialogue: 'old first', timestamp: time),
        NvlDialogue(dialogue: 'old second', timestamp: time),
      ];
      final snapshot = GameStateSnapshot(
        scriptIndex: 3,
        currentState: GameState(),
        isNvlMode: true,
        nvlDialogues: old,
      );
      final restored = NvlStateManager.restoreNvlDialogues(
        snapshot: snapshot,
        script: ScriptNode([
          NvlNode(),
          SayNode(dialogue: 'First'),
          SayNode(dialogue: 'Second'),
          SayNode(dialogue: 'Future'),
        ]),
        characterConfigs: {},
        scriptIndex: 3,
      )!;
      expect(restored.map((line) => line.dialogue), ['First', 'Second']);
      final conservative = NvlStateManager.restoreNvlDialogues(
        snapshot: snapshot,
        script: ScriptNode([
          SayNode(dialogue: 'Unvisited'),
          LabelNode('branch'),
          SayNode(dialogue: 'Second'),
        ]),
        characterConfigs: {},
        scriptIndex: 3,
      )!;
      expect(conservative.map((line) => line.dialogue), [
        'old first',
        'Second',
      ]);
      expect(conservative.map((line) => line.timestamp), [time, time]);
    },
  );
  test(
    'conditional dialogue uses its played index and clears a removed speaker',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        ScriptNode([SayNode(character: 'x', dialogue: 'old')]),
        characterConfigs: _names('old name'),
      );
      manager.refreshLocalizedScriptForTesting(
        ScriptNode([
          ConditionalSayNode(
            dialogue: 'Translated',
            conditionVariable: 'never_set',
            conditionValue: true,
          ),
        ]),
        characterConfigs: _names('new name'),
      );
      expect(manager.currentState.dialogue, 'Translated');
      expect(manager.currentState.speaker, isNull);
      expect(manager.getDialogueHistory().single.dialogue, 'Translated');
      expect(manager.getDialogueHistory().single.speaker, isNull);
      expect(manager.currentScriptIndex, 1);
    },
  );
  test(
    'a suspended inline API commits current language once without replay',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final manager = GameManager(
        onScriptApiExecute:
            ({
              required apiName,
              required params,
              required gameState,
              required scriptIndex,
            }) async {
              calls++;
              entered.complete();
              await release.future;
              return const ScriptApiExecutionResult.unhandled();
            },
      );
      addTearDown(manager.dispose);
      final running = manager.startTestScript(
        ScriptNode([
          SayNode(character: 'x', dialogue: 'old', inlineApiToken: 'apihold'),
        ]),
        characterConfigs: _names('old name'),
      );
      await entered.future;
      manager.refreshLocalizedScriptForTesting(
        ScriptNode([
          SayNode(character: 'x', dialogue: 'New', inlineApiToken: 'apihold'),
        ]),
        characterConfigs: _names('New name'),
      );
      release.complete();
      await running;
      expect(calls, 1);
      expect(manager.currentState.dialogue, 'New');
      expect(manager.currentState.speaker, 'New name');
      expect(manager.getDialogueHistory().single.dialogue, 'New');
      expect(manager.getDialogueHistory().single.speaker, 'New name');
    },
  );
  test(
    'language changes preserve a blank chapter frame even with dialogue history',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        _adv('old', 'choice'),
        characterConfigs: _names('old'),
      );
      final saved = manager.saveStateSnapshot();
      manager.refreshLocalizedScriptForTesting(
        _adv('New', 'Continue'),
        characterConfigs: _names('new'),
        loadedSnapshot: GameStateSnapshot(
          scriptIndex: saved.scriptIndex,
          currentState: saved.currentState.copyWith(
            clearDialogueAndSpeaker: true,
            forceNullCurrentNode: true,
          ),
          dialogueHistory: saved.dialogueHistory,
        ),
      );
      expect(manager.currentState.dialogue, isNull);
      expect(manager.currentState.speaker, isNull);
      expect(manager.getDialogueHistory().single.dialogue, 'New');
    },
  );
  test(
    'rapid real language changes settle on the latest inline translation without replay',
    () async {
      final game = Directory.systemTemp.createTempSync('saki-language-reload-');
      Directory('${game.path}/Assets').createSync();
      final localization = LocalizationManager();
      await localization.switchLanguage(SupportedLanguage.zhHans);
      Directory('${game.path}/GameScript/labels').createSync(recursive: true);
      Directory('${game.path}/GameScript/configs').createSync(recursive: true);
      File('${game.path}/GameScript/labels/start.sks').writeAsStringSync(
        'label start\n'
        'jump cp1_entry\n',
      );
      File('${game.path}/GameScript/labels/cp1.sks').writeAsStringSync(
        'label cp1_entry\n'
        'x "/zhs 原文/ /zhc 原文繁體/ /en English/ /jp 日本語/ /ko 한국어/"\n'
        '"next"\n',
      );
      File('${game.path}/GameScript/configs/characters.sks').writeAsStringSync(
        'x : "/zhs 原文 name/ /zhc 原文繁體 name/ /en English name/ '
        '/jp 日本語 name/ /ko 한국어 name/" : narrator\n',
      );
      configureRuntimeProject(gamePath: game.path);
      GamePathResolver.clearCache();
      final merger = ScriptMerger()..clearCache();
      final manager = GameManager();
      addTearDown(() async {
        manager.dispose();
        merger.clearCache();
        clearRuntimeProjectConfig();
        GamePathResolver.clearCache();
        await localization.switchLanguage(SupportedLanguage.zhHans);
        game.deleteSync(recursive: true);
      });
      final initialDialogue = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == '原文',
      );
      await manager.startTestScript(
        await merger.getMergedScript(),
        characterConfigs: _names('原文 name'),
      );
      await initialDialogue.timeout(const Duration(seconds: 10));
      // Seed the manager through an actual source reload so its active source
      // map identifies the chapter, as it does after a normal game startup.
      final initialTraditional = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == '原文繁體',
      );
      await localization.switchLanguage(SupportedLanguage.zhHant);
      await initialTraditional.timeout(const Duration(seconds: 10));
      final initialChinese = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == '原文',
      );
      await localization.switchLanguage(SupportedLanguage.zhHans);
      await initialChinese.timeout(const Duration(seconds: 10));
      expect(manager.currentScriptFile, 'cp1');
      final before = manager.saveStateSnapshot();
      final beforeLoad = Completer<void>();
      final allowLoad = Completer<void>();
      final loaded = Completer<void>();
      final allowCommit = Completer<void>();
      var loads = 0;
      manager.languageScriptLoaderForTesting = (load) async {
        if (++loads != 1) return load();
        beforeLoad.complete();
        await allowLoad.future;
        final script = await load();
        loaded.complete();
        await allowCommit.future;
        return script;
      };
      final english = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == 'English',
      );
      await localization.switchLanguage(SupportedLanguage.en);
      await beforeLoad.future;
      expect(manager.currentScriptFile, 'cp1');
      await localization.switchLanguage(SupportedLanguage.ja);
      allowLoad.complete();
      await loaded.future;
      expect(manager.currentScriptFile, 'cp1');
      await localization.switchLanguage(SupportedLanguage.en);
      allowCommit.complete();
      await english.timeout(const Duration(seconds: 10));
      expect(loads, greaterThan(1));
      expect(manager.currentState.speaker, 'English name');
      expect(manager.currentScriptFile, 'cp1');
      final traditional = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == '原文繁體',
      );
      await localization.switchLanguage(SupportedLanguage.zhHant);
      await traditional.timeout(const Duration(seconds: 10));
      expect(manager.currentState.speaker, '原文繁體 name');
      final finalState = manager.gameStateStream.firstWhere(
        (state) => state.dialogue == '한국어',
      );
      await localization.switchLanguage(SupportedLanguage.ja);
      await localization.switchLanguage(SupportedLanguage.ko);
      await finalState.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(manager.currentState.dialogue, '한국어');
      expect(manager.currentState.speaker, '한국어 name');
      expect(manager.currentScriptIndex, before.scriptIndex);
      expect(manager.getDialogueHistory(), hasLength(1));
      expect(
        manager.getDialogueHistory().single.serializedStateSnapshot,
        before.dialogueHistory.single.serializedStateSnapshot,
      );
      // Captions resolve against the new script, not the next instruction or
      // old save's Chinese text; resolving leaves every byte of the save intact.
      final oldBytes = BinarySerializer.serializeGameStateSnapshot(before);
      expect(await SaveLoadManager.getDialoguePreview(before), '【한국어 name】한국어');
      expect(BinarySerializer.serializeGameStateSnapshot(before), oldBytes);
      expect(
        await SaveLoadManager.getDialoguePreview(
          GameStateSnapshot(
            scriptIndex: 999999,
            currentState: GameState(dialogue: 'stored fallback'),
          ),
        ),
        'stored fallback',
      );
      manager.dispose();
      await localization.switchLanguage(SupportedLanguage.ja);
      // Both a previously used merger and a fresh session must reject the
      // old shared cache after changing language outside a running game.
      final reused = await merger.getMergedScript();
      expect(
        ScriptTextLocalizer.resolve(
          reused.children.whereType<SayNode>().first.dialogue,
        ),
        '日本語',
      );
      final fresh = await ScriptMerger().getMergedScript();
      expect(
        ScriptTextLocalizer.resolve(
          fresh.children.whereType<SayNode>().first.dialogue,
        ),
        '日本語',
      );
      final newSession = GameManager();
      addTearDown(newSession.dispose);
      final newSessionDialogue = newSession.gameStateStream.firstWhere(
        (state) => state.dialogue == '日本語',
      );
      await newSession.startTestScript(
        fresh,
        characterConfigs: _names('日本語 name'),
      );
      await newSessionDialogue.timeout(const Duration(seconds: 10));
      expect(newSession.currentState.dialogue, '日本語');
      expect(await SaveLoadManager.getDialoguePreview(before), '【日本語 name】日本語');
    },
  );
}
