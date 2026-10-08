import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/script_dialogue_resolver.dart';
import 'package:sakiengine/src/game/script_merger.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';

/// Shared IO/web preview lookup. Save bytes and their screenshot remain intact;
/// only the displayed caption is resolved against the current script language.
class SaveDialoguePreview {
  static Future<(ScriptNode, Map<String, CharacterConfig>)>? _sources;
  static SupportedLanguage? _language;
  static int _revision = 0;
  static bool _listening = false;

  static void clearCache() {
    _revision++;
    _sources = null;
    _language = null;
  }

  static Future<(ScriptNode, Map<String, CharacterConfig>)> _load() async {
    final script = await ScriptMerger().getMergedScript();
    final characters = ConfigParser().parseCharacters(
      await AssetManager().loadString(
        'assets/GameScript/configs/characters.sks',
      ),
    );
    return (script, characters);
  }

  static Future<String> get(GameStateSnapshot snapshot) async {
    if (!_listening) {
      _listening = true;
      LocalizationManager().addListener(clearCache);
    }
    while (true) {
      final language = LocalizationManager().currentLanguage;
      if (_language != language) {
        clearCache();
        _language = language;
      }
      final revision = _revision;
      try {
        final (script, characters) = await (_sources ??= _load());
        if (revision != _revision ||
            language != LocalizationManager().currentLanguage) {
          continue;
        }
        final cursor = snapshot.scriptIndex;
        if (cursor >= 0 && cursor < script.children.length) {
          final node = script.children[cursor];
          if (node is MenuNode) return _menu(node);
        }
        final index = snapshot.dialogueHistory.isNotEmpty
            ? snapshot.dialogueHistory.last.scriptIndex
            : cursor - 1;
        final node = ScriptDialogueResolver.at(script, index);
        if (node != null) {
          return _text(
            node.character == null ? null : characters[node.character]?.name,
            ScriptTextLocalizer.resolve(node.dialogue, language: language),
          );
        }
      } catch (_) {
        if (revision != _revision ||
            language != LocalizationManager().currentLanguage) {
          continue;
        }
        // An unavailable or edited source must not erase the saved caption.
        _sources = null;
      }
      return _savedText(snapshot);
    }
  }

  static String _menu(MenuNode menu) {
    final choices = menu.choices
        .map((choice) => '[${ScriptTextLocalizer.resolve(choice.text)}]')
        .join('\n');
    return '${LocalizationManager().t('saveLoad.choiceMenu')}\n$choices';
  }

  static String _text(String? speaker, String dialogue) {
    final text = RichTextParser.cleanText(dialogue);
    return speaker != null && speaker.isNotEmpty ? '【$speaker】$text' : text;
  }

  static String _savedText(GameStateSnapshot snapshot) {
    final state = snapshot.currentState;
    final menu = state.currentNode;
    if (menu is MenuNode) return _menu(menu);
    final nvl = state.nvlDialogues.isNotEmpty
        ? state.nvlDialogues
        : snapshot.nvlDialogues;
    if ((state.isNvlMode || snapshot.isNvlMode) && nvl.isNotEmpty) {
      return _text(nvl.last.speaker, nvl.last.dialogue);
    }
    if (state.dialogue != null && state.dialogue!.isNotEmpty) {
      return _text(state.speaker, state.dialogue!);
    }
    if (snapshot.dialogueHistory.isNotEmpty) {
      final entry = snapshot.dialogueHistory.last;
      return _text(entry.speaker, entry.dialogue);
    }
    return '...';
  }
}
