import '../../widgets/dialogue_box.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../../core/game_module.dart';
import '../../screens/game_play_screen.dart';
import '../../widgets/common/virtual_game_canvas.dart';
import '../../game/game_manager.dart';
import '../../utils/binary_serializer.dart';
import '../../sks_parser/sks_ast.dart';
import '../../utils/dialogue_progression_manager.dart';
import 'yuyu_package.dart';
import 'yuyu_resource_server.dart';
import 'yuyu_story_bridge.dart';
import 'yuyu_webview.dart';

/// One player module for all packages; games supply data, never Dart plugins.
class YuyuGameModule extends DefaultGameModule {
  final YuyuPackage package;
  YuyuGameModule(this.package);
  YuyuStoryBridge? _bridge;
  YuyuStoryBridge get bridge =>
      _bridge ??= YuyuStoryBridge(nvl: package.nvlMapping);

  @override
  String get initialScript => 'start';
  @override
  Future<String> getAppTitle() async => package.gameName;
  @override
  String get defaultSceneTransitionType => 'none';
  @override
  bool get enableDebugFeatures => false;
  @override
  bool get enableHiddenUiSceneZoom => false;
  @override
  bool get enableCharacterTransitions => false;
  @override
  bool get enableDialogueSwitcherAnimation => false;
  @override
  bool get enableDialogueSwitcherSlideAnimation => false;
  @override
  Offset get mouseParallaxMaxOffset => const Offset(24, 16);
  @override
  Curve get mouseParallaxResetCurve => const _YuyuReturnCurve();
  @override
  bool get mouseParallaxResetOnPointerUp => false;
  @override
  ValueListenable<Offset?>? get mouseParallaxExternalPointer =>
      package.webEntry == null ? null : bridge.pointer;
  @override
  bool get showQuickMenu => package.webEntry == null;

  @override
  Widget createGamePlayScreen({
    Key? key,
    SaveSlot? saveSlotToLoad,
    VoidCallback? onReturnToMenu,
    Function(SaveSlot)? onLoadGame,
  }) => SakiVirtualGameCanvas(
    contain: true,
    child: GamePlayScreen(
      key: key,
      saveSlotToLoad: saveSlotToLoad,
      onReturnToMenu: onReturnToMenu,
      onLoadGame: onLoadGame,
      gameModule: this,
    ),
  );

  @override
  Widget createMainMenuScreen({
    required VoidCallback onNewGame,
    required VoidCallback onLoadGame,
    Function(SaveSlot)? onLoadGameWithSave,
    VoidCallback? onContinueGame,
    bool skipMusicDelay = false,
  }) {
    if (package.webEntry == null) {
      return super.createMainMenuScreen(
        onNewGame: onNewGame,
        onLoadGame: onLoadGame,
        onLoadGameWithSave: onLoadGameWithSave,
        onContinueGame: onContinueGame,
        skipMusicDelay: skipMusicDelay,
      );
    }
    return _YuyuOverlay(package: package, onStart: onNewGame);
  }

  Color? _speakerColor(String? alias) {
    final value = (package.speakerMapping[alias] as Map?)?['color'] as String?;
    if (value == null) return null;
    final rgb = value.substring(1, 7);
    final alpha = value.length == 9 ? value.substring(7) : 'ff';
    return Color(int.parse(alpha + rgb, radix: 16));
  }

  @override
  Widget createDialogueBox({
    Key? key,
    String? speaker,
    String? speakerAlias,
    String? dialogueTag,
    required String dialogue,
    DialogueProgressionManager? progressionManager,
    required bool isFastForwarding,
    required int scriptIndex,
    VoidCallback? onToggleSettings,
    VoidCallback? onToggleReview,
  }) {
    if (package.webEntry == null) {
      return DialogueBox(
        speakerColor: _speakerColor(speakerAlias),
        key: key,
        speaker: speaker,
        speakerAlias: speakerAlias,
        dialogueTag: dialogueTag,
        dialogue: dialogue,
        progressionManager: progressionManager,
        isFastForwarding: isFastForwarding,
        scriptIndex: scriptIndex,
      );
    }
    return _YuyuBinding(
      key: key,
      onBind: () => bridge.presentDialogue(
        text: dialogue,
        speaker: speaker,
        scriptIndex: scriptIndex,
        progressionManager: progressionManager,
        fast: isFastForwarding,
      ),
    );
  }

  @override
  Widget? createNvlPresentation({
    required GameState gameState,
    required DialogueProgressionManager progressionManager,
  }) {
    if (package.webEntry == null || gameState.nvlPresentation == null) {
      return null;
    }
    return _YuyuBinding(
      onBind: () {
        bridge.bindProgression(progressionManager);
      },
    );
  }

  @override
  Widget createChoiceMenu({
    Key? key,
    required MenuNode menuNode,
    required ValueChanged<String> onChoiceSelected,
    required bool isFastForwarding,
    String? leadingDialogue,
  }) {
    if (package.webEntry == null) {
      return super.createChoiceMenu(
        key: key,
        menuNode: menuNode,
        onChoiceSelected: onChoiceSelected,
        isFastForwarding: isFastForwarding,
        leadingDialogue: leadingDialogue,
      );
    }
    return _YuyuBinding(
      key: key ?? ObjectKey(menuNode),
      onBind: () => bridge.presentChoices(menuNode, onChoiceSelected),
      identity: menuNode,
    );
  }

  @override
  Widget? createStatusIndicatorLayer({
    required BuildContext context,
    required GameState gameState,
    required GameManager gameManager,
  }) {
    if (package.webEntry == null) return null;
    final currentBridge = bridge;
    currentBridge.attachManager(gameManager);
    return _YuyuOverlay(
      package: package,
      bridge: currentBridge,
      onClose: () {
        currentBridge.dispose();
        if (identical(_bridge, currentBridge)) _bridge = null;
      },
    );
  }
}

class _YuyuReturnCurve extends Curve {
  const _YuyuReturnCurve();
  @override
  double transformInternal(double t) => 1 - (1 - t) * (1 - t);
}

class _YuyuBinding extends StatefulWidget {
  final VoidCallback onBind;
  final Object? identity;
  const _YuyuBinding({super.key, required this.onBind, this.identity});
  @override
  State<_YuyuBinding> createState() => _YuyuBindingState();
}

class _YuyuBindingState extends State<_YuyuBinding> {
  void bind() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBind();
    });
  }

  @override
  void initState() {
    super.initState();
    bind();
  }

  @override
  void didUpdateWidget(_YuyuBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity == null ||
        !identical(oldWidget.identity, widget.identity)) {
      bind();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _YuyuOverlay extends StatefulWidget {
  final YuyuPackage package;
  final YuyuStoryBridge? bridge;
  final VoidCallback? onStart;
  final VoidCallback? onClose;
  const _YuyuOverlay({
    required this.package,
    this.bridge,
    this.onStart,
    this.onClose,
  });
  @override
  State<_YuyuOverlay> createState() => _YuyuOverlayState();
}

class _YuyuOverlayState extends State<_YuyuOverlay> {
  late final YuyuWebChannel channel =
      widget.bridge?.channel ?? YuyuWebChannel();
  late final Future<YuyuResourceServer> resources = YuyuResourceServer.start(
    widget.package,
  );
  late final YuyuMainMenuBridge menu = YuyuMainMenuBridge(
    channel: channel,
    onStart: widget.onStart ?? () {},
  );
  @override
  void initState() {
    super.initState();
    resources;
  }

  Future<void> handle(Map<String, dynamic> message) async {
    if (widget.bridge != null) {
      await widget.bridge!.handle(message);
      return;
    }
    await menu.handle(message);
  }

  @override
  void dispose() {
    if (widget.bridge == null) channel.dispose();
    widget.onClose?.call();
    unawaited(
      resources.then<void>((server) => server.close(), onError: (Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<YuyuResourceServer>(
    future: resources,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('YuYuball 资源服务失败：${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          widget.bridge?.viewport = constraints.biggest;
          return YuyuWebView(
            resources: snapshot.data!,
            channel: channel,
            onMessage: handle,
            onUnavailable: () {
              widget.bridge?.ready = false;
            },
            onReady: () {
              if (widget.bridge != null) {
                unawaited(widget.bridge!.pageReady());
              } else {
                unawaited(
                  channel.send({
                    'type': 'game:context',
                    'context': 'main_menu',
                    'screen': 'web',
                    'debugMode': false,
                  }),
                );
              }
            },
          );
        },
      );
    },
  );
}
