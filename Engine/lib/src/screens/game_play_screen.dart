import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/screens/save_load_screen.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/widgets/choice_menu.dart';
import 'package:sakiengine/src/widgets/dialogue_box.dart';
import 'package:sakiengine/src/widgets/quick_menu.dart';
import 'package:sakiengine/src/screens/review_screen.dart';
import 'package:sakiengine/src/screens/main_menu_screen.dart';
import 'package:sakiengine/src/widgets/common/exit_confirmation_dialog.dart';
import 'package:sakiengine/src/widgets/confirm_dialog.dart';
import 'package:sakiengine/src/widgets/common/notification_overlay.dart';
import 'package:sakiengine/src/utils/image_loader.dart';
import 'package:sakiengine/src/widgets/nvl_screen.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/black_screen_transition.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';
import 'package:sakiengine/src/rendering/color_background_renderer.dart';
import 'package:sakiengine/src/effects/scene_filter.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/soranouta/widgets/soranouta_dialogue_box.dart';
import 'package:sakiengine/src/rendering/scene_layer.dart';
import 'package:sakiengine/src/widgets/animated_character_widget.dart';

class GamePlayScreen extends StatefulWidget {
  final SaveSlot? saveSlotToLoad;
  final VoidCallback? onReturnToMenu;
  final Function(SaveSlot)? onLoadGame;

  const GamePlayScreen({
    super.key,
    this.saveSlotToLoad,
    this.onReturnToMenu,
    this.onLoadGame,
  });

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  late final GameManager _gameManager;
  late final DialogueProgressionManager _dialogueProgressionManager;
  final _notificationOverlayKey = GlobalKey<NotificationOverlayState>();
  String _currentScript = 'start'; 
  bool _showReviewOverlay = false;
  bool _showSaveOverlay = false;
  bool _showLoadOverlay = false;
  bool _showSettings = false;
  bool _isShowingMenu = false;
  HotKey? _reloadHotKey;
  String? _projectName;

  @override
  void initState() {
    super.initState();
    _gameManager = GameManager(
      onReturn: _returnToMainMenu,
    );
    
    // 初始化对话推进管理器
    _dialogueProgressionManager = DialogueProgressionManager(
      gameManager: _gameManager,
    );

    // 获取项目名称
    _loadProjectName();

    // 注册系统级热键 Shift+R
    _setupHotkey();

    if (widget.saveSlotToLoad != null) {
      _currentScript = widget.saveSlotToLoad!.currentScript;
      //print('🎮 读取存档: currentScript = $_currentScript');
      //print('🎮 存档中的scriptIndex = ${widget.saveSlotToLoad!.snapshot.scriptIndex}');
      _gameManager.restoreFromSnapshot(
          _currentScript, widget.saveSlotToLoad!.snapshot, shouldReExecute: false);
      
      // 延迟显示读档成功通知，确保UI已经构建完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNotificationMessage('读档成功');
        // 设置context用于转场效果
        _gameManager.setContext(context);
      });
    } else {
      _gameManager.startGame(_currentScript);
      // 延迟设置context，确保组件已mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gameManager.setContext(context);
      });
    }
  }

  Future<void> _loadProjectName() async {
    try {
      _projectName = await ProjectInfoManager().getAppName();
      if (mounted) setState(() {});
    } catch (e) {
      _projectName = 'SakiEngine';
    }
  }

  void _returnToMainMenu() {
    // 停止所有音效，保留音乐
    _gameManager.stopAllSounds();
    
    if (mounted && widget.onReturnToMenu != null) {
      widget.onReturnToMenu!();
    } else if (mounted) {
      // 兼容性后退方案：使用传统的页面导航
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainMenuScreen(
            onNewGame: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const GamePlayScreen()),
            ),
            onLoadGame: () => setState(() => _showLoadOverlay = true),
          ),
        ),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _initializeModule() async {
    // 移除模块系统 - 直接加载项目名称即可
  }

  Widget _createDialogueBox({
    String? speaker,
    required String dialogue,
  }) {
    // 根据项目名称选择对话框
    if (_projectName == 'SoraNoUta') {
      return SoranoUtaDialogueBox(
        speaker: speaker,
        dialogue: dialogue,
        progressionManager: _dialogueProgressionManager,
      );
    }
    
    // 默认对话框
    return DialogueBox(
      speaker: speaker,
      dialogue: dialogue,
      progressionManager: _dialogueProgressionManager,
    );
  }

  void _handleQuickMenuBack() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmDialog(
          title: '返回主菜单',
          content: '确定要返回主菜单吗？未保存的游戏进度将会丢失。',
          onConfirm: _returnToMainMenu,
        );
      },
    );
  }

  void _handlePreviousDialogue() {
    final history = _gameManager.getDialogueHistory();
    
    // 如果当前显示选项，回到最后一句对话（选项出现前的对话）
    if (_isShowingMenu) {
      if (history.isNotEmpty) {
        final lastEntry = history.last;
        _jumpToHistoryEntryQuiet(lastEntry);
      }
    } 
    // 如果没有选项，正常回到上一句
    else if (history.length >= 2) {
      final previousEntry = history[history.length - 2];
      _jumpToHistoryEntryQuiet(previousEntry);
    }
  }

  @override
  void dispose() {
    // 取消注册系统热键
    if (_reloadHotKey != null) {
      hotKeyManager.unregister(_reloadHotKey!);
    }
    _gameManager.dispose();
    super.dispose();
  }

  // 设置系统级热键
  Future<void> _setupHotkey() async {
    _reloadHotKey = HotKey(
      key: PhysicalKeyboardKey.keyR,
      modifiers: [HotKeyModifier.shift],
      scope: HotKeyScope.inapp, // 先使用应用内热键，避免权限问题
    );
    
    try {
      await hotKeyManager.register(
        _reloadHotKey!,
        keyDownHandler: (hotKey) {
          print('热键触发: ${hotKey.toJson()}');
          if (mounted) {
            _handleHotReload();
          }
        },
      );
      print('快捷键 Shift+R 注册成功');
    } catch (e) {
      print('快捷键注册失败: $e');
      // 如果系统级热键失败，尝试应用内热键
      _reloadHotKey = HotKey(
        key: PhysicalKeyboardKey.keyR,
        modifiers: [HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      );
      try {
        await hotKeyManager.register(
          _reloadHotKey!,
          keyDownHandler: (hotKey) {
            print('应用内热键触发: ${hotKey.toJson()}');
            if (mounted) {
              _handleHotReload();
            }
          },
        );
        print('应用内快捷键 Shift+R 注册成功');
      } catch (e2) {
        print('应用内快捷键注册也失败: $e2');
      }
    }

    // 添加箭头键支持（替代滚轮）
    try {
      final nextHotKey = HotKey(
        key: PhysicalKeyboardKey.arrowDown,
        scope: HotKeyScope.inapp,
      );
      
      final prevHotKey = HotKey(
        key: PhysicalKeyboardKey.arrowUp,
        scope: HotKeyScope.inapp,
      );

      await hotKeyManager.register(
        nextHotKey,
        keyDownHandler: (hotKey) {
          //print('🎮 下箭头键 - 前进剧情');
          if (mounted && !_isShowingMenu) {
            _dialogueProgressionManager.progressDialogue();
          }
        },
      );

      await hotKeyManager.register(
        prevHotKey,
        keyDownHandler: (hotKey) {
          //print('🎮 上箭头键 - 回滚剧情');
          if (mounted) {
            _handlePreviousDialogue();
          }
        },
      );
      
      print('箭头键快捷键注册成功');
    } catch (e) {
      print('箭头键快捷键注册失败: $e');
    }
  }

  // 显示通知消息
  void _showNotificationMessage(String message) {
    _notificationOverlayKey.currentState?.show(message);
  }

  Future<void> _handleHotReload() async {
    await _gameManager.hotReload(_currentScript);
    _showNotificationMessage('重载完成');
  }

  Future<void> _jumpToHistoryEntry(DialogueHistoryEntry entry) async {
    setState(() => _showReviewOverlay = false);
    await _gameManager.jumpToHistoryEntry(entry, _currentScript);
    _showNotificationMessage('跳转成功');
  }

  Future<void> _jumpToHistoryEntryQuiet(DialogueHistoryEntry entry) async {
    await _gameManager.jumpToHistoryEntry(entry, _currentScript);
  }

  Future<bool> _onWillPop() async {
    return await ExitConfirmationDialog.showExitConfirmation(context, hasProgress: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          final shouldExit = await _onWillPop();
          if (shouldExit && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Focus(
        autofocus: false,
        child: Scaffold(
          body: StreamBuilder<GameState>(
          stream: _gameManager.gameStateStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final gameState = snapshot.data!;
            
            // 更新选项显示状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isShowingMenu = gameState.currentNode is MenuNode;
                });
              }
            });
            
            return Listener(
              onPointerSignal: (pointerSignal) {
                // 检查是否有弹窗或菜单显示
                final hasOverlayOpen = _isShowingMenu || 
                    _showSaveOverlay || 
                    _showLoadOverlay || 
                    _showReviewOverlay ||
                    _showSettings;
                
                // 处理标准的PointerScrollEvent（鼠标滚轮）
                if (pointerSignal is PointerScrollEvent) {
                  // 向上滚动: 前进剧情
                  if (pointerSignal.scrollDelta.dy < 0) {
                    if (!hasOverlayOpen) {
                      _dialogueProgressionManager.progressDialogue();
                    }
                  }
                  // 向下滚动: 回滚剧情
                  else if (pointerSignal.scrollDelta.dy > 0) {
                    if (!hasOverlayOpen) {
                      _handlePreviousDialogue();
                    }
                  }
                }
                // 处理macOS触控板事件
                else if (pointerSignal.toString().contains('Scroll')) {
                  // 触控板滚动事件，推进剧情
                  if (!hasOverlayOpen) {
                    _dialogueProgressionManager.progressDialogue();
                  }
                }
              },
              child: Stack(
              children: [
                GestureDetector(
                  onTap: gameState.currentNode is MenuNode ? null : () {
                    _dialogueProgressionManager.progressDialogue();
                  },
                  child: _buildSceneWithFilter(gameState),
                ),
                // NVL 模式覆盖层
                if (gameState.isNvlMode)
                  NvlScreen(
                    nvlDialogues: gameState.nvlDialogues,
                    isMovieMode: gameState.isNvlMovieMode,
                    progressionManager: _dialogueProgressionManager,
                  ),
                QuickMenu(
                  onSave: () => setState(() => _showSaveOverlay = true),
                  onLoad: () => setState(() => _showLoadOverlay = true),
                  onReview: () => setState(() => _showReviewOverlay = true),
                  onSettings: () => setState(() => _showSettings = true),
                  onBack: _handleQuickMenuBack,
                  onPreviousDialogue: _handlePreviousDialogue,
                ),
                if (_showReviewOverlay)
                  ReviewOverlay(
                    dialogueHistory: _gameManager.getDialogueHistory(),
                    onClose: () => setState(() => _showReviewOverlay = false),
                    onJumpToEntry: _jumpToHistoryEntry,
                  ),
                if (_showSaveOverlay)
                  SaveLoadScreen(
                    mode: SaveLoadMode.save,
                    gameManager: _gameManager,
                    onClose: () => setState(() => _showSaveOverlay = false),
                  ),
                if (_showLoadOverlay)
                  SaveLoadScreen(
                    mode: SaveLoadMode.load,
                    onClose: () => setState(() => _showLoadOverlay = false),
                    onLoadSlot: widget.onLoadGame ?? (saveSlot) {
                      // 如果没有回调，使用传统的导航方式（兼容性）
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => GamePlayScreen(saveSlotToLoad: saveSlot),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                if (_showSettings)
                  SettingsScreen(
                    onClose: () => setState(() => _showSettings = false),
                  ),
                NotificationOverlay(
                  key: _notificationOverlayKey,
                  scale: context.scaleFor(ComponentType.ui),
                ),
              ],
            ),
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _buildSceneWithFilter(GameState gameState) {
    return Stack(
      children: [
        if (gameState.background != null)
          _buildBackground(gameState.background!, gameState.sceneFilter, gameState.sceneLayers),
        ..._buildCharacters(context, gameState.characters, gameState.poseConfigs, gameState.everShownCharacters),
        if (gameState.dialogue != null && !gameState.isNvlMode)
          _createDialogueBox(
            speaker: gameState.speaker,
            dialogue: gameState.dialogue!,
          ),
        if (gameState.currentNode is MenuNode)
          ChoiceMenu(
            menuNode: gameState.currentNode as MenuNode,
            onChoiceSelected: (String targetLabel) {
              _gameManager.jumpToLabel(targetLabel);
            },
          ),
      ],
    );
  }

  /// 构建背景Widget - 支持图片背景和十六进制颜色背景，以及多图层场景
  Widget _buildBackground(String background, [SceneFilter? sceneFilter, List<String>? sceneLayers]) {
    // 如果有多图层数据，使用多图层渲染器
    if (sceneLayers != null && sceneLayers.isNotEmpty) {
      final layers = sceneLayers.map((layerString) => SceneLayer.fromString(layerString))
          .where((layer) => layer != null)
          .cast<SceneLayer>()
          .toList();
      
      if (layers.isNotEmpty) {
        final multiLayerWidget = MultiLayerRenderer.buildMultiLayerScene(
          layers: layers,
          screenSize: MediaQuery.of(context).size,
        );
        
        if (sceneFilter != null) {
          return _FilteredBackground(
            filter: sceneFilter,
            child: multiLayerWidget,
          );
        }
        return multiLayerWidget;
      }
    }
    
    // 单图层模式（原有逻辑）
    // 检查是否为十六进制颜色格式
    if (ColorBackgroundRenderer.isValidHexColor(background)) {
      final colorWidget = ColorBackgroundRenderer.createColorBackgroundWidget(background);
      if (sceneFilter != null) {
        return _FilteredBackground(
          filter: sceneFilter,
          child: colorWidget,
        );
      }
      return colorWidget;
    }
    
    // 处理图片背景
    return FutureBuilder<String?>(
      future: AssetManager().findAsset('backgrounds/${background.replaceAll(' ', '-')}'),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final imageWidget = Image.asset(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
          
          if (sceneFilter != null) {
            return _FilteredBackground(
              filter: sceneFilter,
              child: imageWidget,
            );
          }
          return imageWidget;
        }
        return Container(color: Colors.black);
      },
    );
  }

  List<Widget> _buildCharacters(BuildContext context, Map<String, CharacterState> characters, Map<String, PoseConfig> poseConfigs, Set<String> everShownCharacters) {
    return characters.entries.map((entry) {
      final characterId = entry.key;
      final characterState = entry.value;
      final poseConfig = poseConfigs[characterState.positionId] ?? PoseConfig(id: 'default');

      // 如果有动画，使用AnimatedCharacterWidget
      if (characterState.animation != null && characterState.animation!.isNotEmpty) {
        return FutureBuilder<List<CharacterLayerInfo>>(
          future: CharacterLayerParser.parseCharacterLayers(
            resourceId: characterState.resourceId,
            pose: characterState.pose ?? 'pose1',
            expression: characterState.expression ?? 'happy',
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }

            // 使用第一个图层作为主要图片路径（简化处理）
            final primaryImagePath = snapshot.data!.first.assetName;
            final screenSize = MediaQuery.of(context).size;
            
            // 计算角色尺寸
            double characterHeight = screenSize.height * (poseConfig.scale > 0 ? poseConfig.scale : 0.8);
            double characterWidth = characterHeight * 0.75; // 假设角色宽高比
            
            return AnimatedCharacterWidget(
              characterId: characterId,
              imagePath: primaryImagePath,
              width: characterWidth,
              height: characterHeight,
              x: poseConfig.xcenter * screenSize.width,
              y: poseConfig.ycenter * screenSize.height,
              scale: 1.0,
              opacity: 1.0,
              animationName: characterState.animation,
              onAnimationComplete: () {
                print('[AnimatedCharacterWidget] 动画完成: ${characterState.animation} for $characterId');
              },
            );
          },
        );
      }

      // 没有动画时使用原有的渲染方式
      return FutureBuilder<List<CharacterLayerInfo>>(
        future: CharacterLayerParser.parseCharacterLayers(
          resourceId: characterState.resourceId,
          pose: characterState.pose ?? 'pose1',
          expression: characterState.expression ?? 'happy',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }

          final layerInfos = snapshot.data!;

          // 根据解析结果创建图层组件
          final layers = layerInfos.map((layerInfo) {
            return _CharacterLayer(
              key: ValueKey('$characterId-${layerInfo.layerType}'),
              assetName: layerInfo.assetName,
            );
          }).toList();
          
          final characterStack = Stack(children: layers);
          
          Widget finalWidget = characterStack;
          if (poseConfig.scale > 0) {
            finalWidget = SizedBox(
              height: MediaQuery.of(context).size.height * poseConfig.scale,
              child: characterStack,
            );
          }

          return Positioned(
            left: poseConfig.xcenter * MediaQuery.of(context).size.width,
            top: poseConfig.ycenter * MediaQuery.of(context).size.height,
            child: FractionalTranslation(
              translation: _anchorToTranslation(poseConfig.anchor),
              child: finalWidget,
            ),
          );
        },
      );
    }).toList();
  }

  Offset _anchorToTranslation(String anchor) {
    switch (anchor) {
      case 'topCenter': return const Offset(-0.5, 0);
      case 'bottomCenter': return const Offset(-0.5, -1.0);
      case 'centerLeft': return const Offset(0, -0.5);
      case 'centerRight': return const Offset(-1.0, -0.5);
      case 'center':
      default:
        return const Offset(-0.5, -0.5);
    }
  }
}

class _CharacterLayer extends StatefulWidget {
  final String assetName;
  const _CharacterLayer({
    super.key, 
    required this.assetName,
  });

  @override
  State<_CharacterLayer> createState() => _CharacterLayerState();
}

class _CharacterLayerState extends State<_CharacterLayer>
    with SingleTickerProviderStateMixin {
  ui.Image? _currentImage;
  ui.Image? _previousImage;

  late final AnimationController _controller;
  late final Animation<double> _animation;

  static ui.FragmentProgram? _dissolveProgram;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    _loadImage();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (_dissolveProgram == null) {
      try {
        final program = await ui.FragmentProgram.fromAsset('assets/shaders/dissolve.frag');
        _dissolveProgram = program;
      } catch (e) {
        print('Error loading shader: $e');
      }
    }
  }

  @override
  void didUpdateWidget(covariant _CharacterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetName != widget.assetName) {
      _previousImage = _currentImage;
      _loadImage().then((_) {
        if (mounted) {
          _controller.forward(from: 0.0);
        }
      });
    }
  }

  Future<void> _loadImage() async {
    final assetPath = await AssetManager().findAsset(widget.assetName);
    if (assetPath != null && mounted) {
      final image = await ImageLoader.loadImage(assetPath);
      if (mounted && image != null) {
        setState(() {
          _currentImage = image;
        });
        
        // 始终触发动画
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _currentImage?.dispose();
    _previousImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentImage == null || _dissolveProgram == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final imageSize = Size(_currentImage!.width.toDouble(), _currentImage!.height.toDouble());
            
            // 确定绘制尺寸
            Size paintSize;
            if (!constraints.hasBoundedHeight) {
              paintSize = imageSize;
            } else {
              final imageAspectRatio = imageSize.width / imageSize.height;
              final paintHeight = constraints.maxHeight;
              final paintWidth = paintHeight * imageAspectRatio;
              paintSize = Size(paintWidth, paintHeight);
            }
            
            return CustomPaint(
              size: paintSize,
              painter: _DissolvePainter(
                program: _dissolveProgram!,
                progress: _animation.value,
                imageFrom: _previousImage ?? _currentImage!, // 没有previousImage时用当前图片，shader会处理透明
                imageTo: _currentImage!,
              ),
            );
          },
        );
      },
    );
  }
}

class _DissolvePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final double progress;
  final ui.Image imageFrom;
  final ui.Image imageTo;

  _DissolvePainter({
    required this.program,
    required this.progress,
    required this.imageFrom,
    required this.imageTo,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    try {
      // 如果没有之前的图片（首次显示），从透明开始
      if (imageFrom == imageTo) {
        // 首次显示：简单的透明度渐变
        final paint = ui.Paint()
          ..color = Colors.white.withOpacity(progress)
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high;
        
        canvas.drawImageRect(
          imageTo,
          ui.Rect.fromLTWH(0, 0, imageTo.width.toDouble(), imageTo.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, size.width, size.height),
          paint,
        );
        return;
      }

      // 差分切换：使用dissolve效果
      final shader = program.fragmentShader();
      shader
        ..setFloat(0, progress)
        ..setFloat(1, size.width)
        ..setFloat(2, size.height)
        ..setFloat(3, imageFrom.width.toDouble())
        ..setFloat(4, imageFrom.height.toDouble())
        ..setFloat(5, imageTo.width.toDouble())
        ..setFloat(6, imageTo.height.toDouble())
        ..setImageSampler(0, imageFrom)
        ..setImageSampler(1, imageTo);

      final paint = ui.Paint()
        ..shader = shader
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high;
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), paint);
    } catch (e) {
      print("Error painting dissolve shader: $e");
    }
  }

  @override
  bool shouldRepaint(covariant _DissolvePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        imageFrom != oldDelegate.imageFrom ||
        imageTo != oldDelegate.imageTo;
  }
}

class _FilteredBackground extends StatefulWidget {
  final SceneFilter filter;
  final Widget child;
  
  const _FilteredBackground({
    required this.filter,
    required this.child,
  });

  @override
  State<_FilteredBackground> createState() => _FilteredBackgroundState();
}

class _FilteredBackgroundState extends State<_FilteredBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: (widget.filter.duration * 1000).round()),
      vsync: this,
    );
    
    if (widget.filter.animation != AnimationType.none) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_FilteredBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      _animationController.duration = Duration(milliseconds: (widget.filter.duration * 1000).round());
      if (widget.filter.animation != AnimationType.none) {
        _animationController.repeat();
      } else {
        _animationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FilterRenderer.applyFilter(
      child: widget.child,
      filter: widget.filter,
      animationController: _animationController,
    );
  }
}
