import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sakiengine/src/core/game_module.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';
import 'package:sakiengine/src/utils/music_manager.dart';
import 'package:sakiengine/src/widgets/common/configurable_menu_button.dart';
import 'widgets/soranouta_menu_buttons.dart';
import 'widgets/soranouta_dialogue_box.dart';
import 'screens/soranouta_startup_flow.dart';

/// SoraNoUta 项目的自定义模块
/// 这个示例展示了如何为特定项目创建自定义模块
class SoranoutaModule extends DefaultGameModule {
  
  @override
  Widget createMainMenuScreen({
    required VoidCallback onNewGame,
    required VoidCallback onLoadGame,
    Function(SaveSlot)? onLoadGameWithSave,
    VoidCallback? onContinueGame, // 新增：继续游戏回调
    bool skipMusicDelay = false,
  }) {
    // 使用专门的 SoraNoUta 主菜单，继承标题但使用专用按钮
    return SoraNoutaStartupFlow(
      onNewGame: onNewGame,
      onLoadGame: onLoadGame,
      onLoadGameWithSave: onLoadGameWithSave,
      onContinueGame: onContinueGame, // 新增：传递继续游戏回调
      skipMusicDelay: skipMusicDelay,
      skipIntro: skipMusicDelay,
    );
  }

  @override
  SakiEngineConfig? createCustomConfig() {
    // SoraNoUta 项目特定配置
    final config = SakiEngineConfig();
    // 可以在这里添加项目特定的配置
    return config;
  }

  @override
  bool get enableDebugFeatures => true; // SoraNoUta 启用调试功能

  @override
  Future<String> getAppTitle() async {
    return 'SoraNoUta';
  }

  @override
  Future<void> initialize() async {
    await MusicManager().initialize();
  }

  @override
  List<MenuButtonConfig> createMainMenuButtonConfigs({
    required VoidCallback onNewGame,
    VoidCallback? onContinueGame,
    required VoidCallback onLoadGame,
    required VoidCallback onSettings,
    required VoidCallback onExit,
    required SakiEngineConfig config,
    required double scale,
  }) {
    return SoranoutaMenuButtons.createConfigs(
      onNewGame: onNewGame,
      onLoadGame: onLoadGame,
      onSettings: onSettings,
      onExit: onExit,
      config: config,
      scale: scale,
    );
  }

  @override
  MenuButtonsLayoutConfig getMenuButtonsLayoutConfig() {
    return SoranoutaMenuButtons.getLayoutConfig();
  }

  @override
  Widget createDialogueBox({
    Key? key,
    String? speaker,
    String? speakerAlias, // 新增：角色简写参数
    required String dialogue,
    DialogueProgressionManager? progressionManager,
    required bool isFastForwarding,
    required int scriptIndex, // 新增：脚本索引参数
  }) {
    return SoranoUtaDialogueBox(
      key: key,
      speaker: speaker,
      speakerAlias: speakerAlias, // 传递角色简写
      dialogue: dialogue,
      progressionManager: progressionManager,
      isFastForwarding: isFastForwarding,
      scriptIndex: scriptIndex, // 传递脚本索引
    );
  }

  @override
  bool get showBottomBar => false;

  @override
  bool shouldUseUnderscoreNextArrow({String? speaker, String? speakerAlias}) {
    if (speaker == null || speaker.isEmpty) {
      return false;
    }
    return speakerAlias != 'l' &&
        speakerAlias != 'ls' &&
        speakerAlias != 'x2' &&
        speakerAlias != 'x2nan' &&
        speaker != '刘守真' &&
        speaker != '林澄' &&
        speakerAlias != 'nanshin';
  }
}

GameModule createProjectModule() => SoranoutaModule();
