import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/utils/key_sequence_detector.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';

/// Debug脚本编辑浮窗（Shift+P）
/// - 悬浮置顶
/// - 可拖拽
/// - 可调整尺寸
/// - 打开时自动将当前对话对应脚本行定位到中间
class FloatingScriptEditorOverlay extends StatefulWidget {
  final GameManager gameManager;
  final String currentScript;
  final Future<void> Function()? onReload;
  final VoidCallback onClose;
  final void Function(String message)? onNotify;

  const FloatingScriptEditorOverlay({
    super.key,
    required this.gameManager,
    required this.currentScript,
    required this.onClose,
    this.onReload,
    this.onNotify,
  });

  @override
  State<FloatingScriptEditorOverlay> createState() =>
      _FloatingScriptEditorOverlayState();
}

class _VisualLineLayout {
  final double top;
  final double height;

  const _VisualLineLayout({
    required this.top,
    required this.height,
  });
}

class _FloatingScriptEditorOverlayState
    extends State<FloatingScriptEditorOverlay> {
  final TextEditingController _scriptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _currentScriptPath = '';
  bool _isLoading = true;

  bool _rectInitialized = false;
  double _windowLeft = 96;
  double _windowTop = 72;
  double _windowWidth = 960;
  double _windowHeight = 640;

  static const double _minWidth = 500;
  static const double _minHeight = 340;
  static const double _lineHeightMultiplier = 1.5;
  static const double _editorFontSize = 14.0;

  @override
  void initState() {
    super.initState();
    _loadCurrentScriptAndCenter();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _notify(String message) {
    widget.onNotify?.call(message);
  }

  void _ensureInitialRect(Size size) {
    if (_rectInitialized) {
      return;
    }
    _rectInitialized = true;
    _windowWidth = (size.width * 0.58).clamp(_minWidth, size.width - 32);
    _windowHeight = (size.height * 0.68).clamp(_minHeight, size.height - 32);
    _windowLeft = (size.width - _windowWidth) / 2;
    _windowTop = (size.height - _windowHeight) / 2;
  }

  void _clampRect(Size size) {
    final maxLeft = (size.width - _windowWidth).clamp(0.0, double.infinity);
    final maxTop = (size.height - _windowHeight).clamp(0.0, double.infinity);
    _windowLeft = _windowLeft.clamp(0.0, maxLeft);
    _windowTop = _windowTop.clamp(0.0, maxTop);
  }

  Future<void> _loadCurrentScriptAndCenter() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final preferredScriptFile =
          widget.gameManager.currentDialogueSourceScriptFile;
      final candidateScriptNames = <String>[
        if (preferredScriptFile != null && preferredScriptFile.isNotEmpty)
          preferredScriptFile,
        widget.gameManager.currentScriptFile,
        widget.currentScript,
      ].toSet().toList();

      String? matchedScriptPath;
      for (final scriptName in candidateScriptNames) {
        matchedScriptPath =
            await ScriptContentModifier.getCurrentScriptFilePath(scriptName);
        if (matchedScriptPath != null) {
          break;
        }
      }

      if (matchedScriptPath == null) {
        _scriptController.text =
            '// 未找到当前脚本文件\n// 已尝试: ${candidateScriptNames.join(', ')}';
        _currentScriptPath = '';
        return;
      }

      final file = File(matchedScriptPath);
      final content = await file.readAsString();
      _scriptController.text = content;
      _currentScriptPath = matchedScriptPath;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerCurrentDialogueInEditor();
      });
    } catch (e) {
      _scriptController.text = '// 读取脚本失败: $e';
      _currentScriptPath = '';
      if (kEngineDebugMode) {
        print('浮窗脚本编辑器: 加载脚本失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _findLineByDialogueText(List<String> lines, String dialogueText) {
    final target = dialogueText.trim();
    if (target.isEmpty) {
      return -1;
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.contains('"')) {
        continue;
      }
      final quoteStart = line.indexOf('"');
      final quoteEnd = line.lastIndexOf('"');
      if (quoteStart < 0 || quoteEnd <= quoteStart) {
        continue;
      }
      final lineDialogue = line.substring(quoteStart + 1, quoteEnd);
      if (lineDialogue.contains(target) || target.contains(lineDialogue)) {
        return i;
      }
    }

    return -1;
  }

  int _findLineByPartialText(List<String> lines, String dialogueText) {
    final target = dialogueText.trim();
    if (target.length < 4) {
      return -1;
    }
    final half = target.substring(0, (target.length / 2).round());
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains(half)) {
        return i;
      }
    }
    return -1;
  }

  List<_VisualLineLayout> _computeVisualLineLayouts({
    required String text,
    required TextStyle textStyle,
    required double maxTextWidth,
  }) {
    final lines = text.split('\n');
    if (lines.isEmpty || maxTextWidth <= 0) {
      return const <_VisualLineLayout>[];
    }

    final layouts = <_VisualLineLayout>[];
    var top = 0.0;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: null,
      textScaler: MediaQuery.textScalerOf(context),
    );

    for (final line in lines) {
      final measurable = line.isEmpty ? ' ' : line;
      painter.text = TextSpan(text: measurable, style: textStyle);
      painter.layout(maxWidth: maxTextWidth);

      final height = painter.height;
      layouts.add(_VisualLineLayout(top: top, height: height));
      top += height;
    }

    return layouts;
  }

  int _resolveTargetLine(List<String> lines, {bool verbose = false}) {
    int targetLine = -1;
    final sourceLine = widget.gameManager.currentDialogueSourceLine;
    if (sourceLine != null && sourceLine >= 1 && sourceLine <= lines.length) {
      targetLine = sourceLine - 1;
      if (verbose && kEngineDebugMode) {
        print('浮窗脚本编辑器: 使用sourceLine定位，line=$sourceLine');
      }
      return targetLine;
    }

    final currentDialogue = widget.gameManager.currentDialogueText;
    targetLine = _findLineByDialogueText(lines, currentDialogue);
    if (targetLine < 0) {
      targetLine = _findLineByPartialText(lines, currentDialogue);
    }
    if (verbose && kEngineDebugMode) {
      print('浮窗脚本编辑器: 回退文本定位，line=$targetLine');
    }
    return targetLine;
  }

  void _centerCurrentDialogueInEditor() {
    if (!_scrollController.hasClients) {
      return;
    }
    final lines = _scriptController.text.split('\n');
    if (lines.isEmpty) {
      return;
    }
    final targetLine = _resolveTargetLine(lines, verbose: true);
    if (targetLine < 0) {
      return;
    }

    final textScale = context.scaleFor(ComponentType.text);
    final uiScale = context.scaleFor(ComponentType.ui);
    final textStyle = TextStyle(
      fontSize: _editorFontSize * textScale,
      fontFamily: 'Courier New',
      height: _lineHeightMultiplier,
      letterSpacing: 0.4,
    );

    final lineNumberWidth = 52 * uiScale;
    final horizontalPadding = 12 * uiScale;
    final availableWidth = (_windowWidth - lineNumberWidth - horizontalPadding * 2)
        .clamp(120.0, double.infinity);

    final layouts = _computeVisualLineLayouts(
      text: _scriptController.text,
      textStyle: textStyle,
      maxTextWidth: availableWidth,
    );
    if (targetLine < 0 || targetLine >= layouts.length) {
      return;
    }

    final viewport = _scrollController.position.viewportDimension;
    final targetLayout = layouts[targetLine];
    final centeredOffset =
        targetLayout.top + targetLayout.height / 2 - viewport / 2;
    final targetOffset = centeredOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveScript({required bool reloadAfterSave}) async {
    if (_currentScriptPath.isEmpty) {
      _notify('未加载脚本文件，无法保存');
      return;
    }

    try {
      final file = File(_currentScriptPath);
      if (!await file.exists()) {
        throw FileSystemException('目标脚本不存在', _currentScriptPath);
      }
      await _atomicWriteScript(file, _scriptController.text);
      _notify('脚本已保存: ${p.basename(_currentScriptPath)}');

      if (reloadAfterSave && widget.onReload != null) {
        await widget.onReload!();
        _notify('重载完成');
      }
    } catch (e) {
      _notify('保存失败: $e');
      if (kEngineDebugMode) {
        print('浮窗脚本编辑器: 保存失败: $e');
      }
    }
  }

  Future<void> _atomicWriteScript(File targetFile, String content) async {
    final tmpPath =
        '${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}';
    final tmpFile = File(tmpPath);
    Object? atomicError;

    try {
      await tmpFile.writeAsString(content, flush: true);
      await tmpFile.rename(targetFile.path);
      return;
    } catch (e) {
      atomicError = e;
      if (kEngineDebugMode) {
        print('浮窗脚本编辑器: 原子写入失败，尝试回退: $e');
      }
    }

    try {
      if (await tmpFile.exists()) {
        await tmpFile.copy(targetFile.path);
        await tmpFile.delete();
        return;
      }
      await targetFile.writeAsString(content, flush: true);
      return;
    } catch (fallbackError) {
      final message =
          '原子写入失败: $atomicError; 回退失败: $fallbackError; path=${targetFile.path}';
      throw FileSystemException(message, targetFile.path);
    } finally {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    }
  }

  Widget _buildLineNumbers(
    double uiScale,
    double textScale,
    List<_VisualLineLayout> lineLayouts,
    int highlightedLineIndex,
  ) {
    return Container(
      width: 52 * uiScale,
      padding: EdgeInsets.symmetric(
        vertical: 12 * uiScale,
        horizontal: 8 * uiScale,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(
          right: BorderSide(color: Color(0xFF3E3E42), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < lineLayouts.length; i++)
            Container(
              height: lineLayouts[i].height,
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 2 * uiScale),
              decoration: i == highlightedLineIndex
                  ? BoxDecoration(
                      color: const Color(0xFFAB20A1).withOpacity(0.16),
                      border: const Border(
                        left: BorderSide(
                          color: Color(0xFFAB20A1),
                          width: 2,
                        ),
                      ),
                    )
                  : null,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: i == highlightedLineIndex
                      ? const Color(0xFFE9A6E2)
                      : const Color(0xFF858585),
                  fontSize: 12 * textScale,
                  fontFamily: 'Courier New',
                  height: _lineHeightMultiplier,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);
    final editorTextStyle = TextStyle(
      color: const Color(0xFFD4D4D4),
      fontSize: _editorFontSize * textScale,
      fontFamily: 'Courier New',
      height: _lineHeightMultiplier,
      letterSpacing: 0.4,
    );

    _ensureInitialRect(screenSize);
    _windowWidth = _windowWidth.clamp(_minWidth, screenSize.width);
    _windowHeight = _windowHeight.clamp(_minHeight, screenSize.height);
    _clampRect(screenSize);

    final lineNumberWidth = 52 * uiScale;
    final editorPadding = 12 * uiScale;
    final editorTextMaxWidth =
        (_windowWidth - lineNumberWidth - editorPadding * 2).clamp(
      120.0,
      double.infinity,
    );
    final lineLayouts = _computeVisualLineLayouts(
      text: _scriptController.text,
      textStyle: editorTextStyle,
      maxTextWidth: editorTextMaxWidth,
    );
    final highlightedLineIndex =
        _resolveTargetLine(_scriptController.text.split('\n'));
    final hasHighlight = highlightedLineIndex >= 0 &&
        highlightedLineIndex < lineLayouts.length;
    final highlightTop =
        hasHighlight ? lineLayouts[highlightedLineIndex].top : 0.0;
    final highlightHeight =
        hasHighlight ? lineLayouts[highlightedLineIndex].height : 0.0;

    return Positioned(
      left: _windowLeft,
      top: _windowTop,
      width: _windowWidth,
      height: _windowHeight,
      child: Material(
        elevation: 30,
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: config.themeColors.background.withOpacity(0.96),
            borderRadius: BorderRadius.circular(config.baseWindowBorder),
            border: Border.all(
              color: config.themeColors.primary.withOpacity(0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(config.baseWindowBorder),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _windowLeft += details.delta.dx;
                          _windowTop += details.delta.dy;
                          _clampRect(screenSize);
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10 * uiScale,
                          vertical: 8 * uiScale,
                        ),
                        color: config.themeColors.primary.withOpacity(0.16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '脚本编辑浮窗 (Shift+P)',
                                style: config.reviewTitleTextStyle.copyWith(
                                  fontSize:
                                      config.reviewTitleTextStyle.fontSize! *
                                          textScale *
                                          0.62,
                                  color: config.themeColors.primary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '定位当前句',
                              onPressed: _centerCurrentDialogueInEditor,
                              icon: const Icon(Icons.center_focus_strong),
                              visualDensity: VisualDensity.compact,
                              color: config.themeColors.primary,
                            ),
                            IconButton(
                              tooltip: '保存',
                              onPressed: () =>
                                  _saveScript(reloadAfterSave: false),
                              icon: const Icon(Icons.save_alt),
                              visualDensity: VisualDensity.compact,
                              color: Colors.green.shade500,
                            ),
                            IconButton(
                              tooltip: '保存并重载',
                              onPressed: () =>
                                  _saveScript(reloadAfterSave: true),
                              icon: const Icon(Icons.refresh),
                              visualDensity: VisualDensity.compact,
                              color: Colors.lightBlue.shade400,
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close),
                              visualDensity: VisualDensity.compact,
                              color: config.themeColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * uiScale,
                        vertical: 6 * uiScale,
                      ),
                      color: Colors.black.withOpacity(0.2),
                      child: Text(
                        _currentScriptPath.isNotEmpty
                            ? _currentScriptPath
                            : '未加载脚本文件',
                        style: TextStyle(
                          color: config.themeColors.primary.withOpacity(0.86),
                          fontSize: 11 * textScale,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Container(
                              color: const Color(0xFF1E1E1E),
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLineNumbers(
                                      uiScale,
                                      textScale,
                                      lineLayouts,
                                      highlightedLineIndex,
                                    ),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          if (hasHighlight)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              top: highlightTop + editorPadding,
                                              height: highlightHeight,
                                              child: IgnorePointer(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFAB20A1,
                                                    ).withOpacity(0.12),
                                                    border: const Border(
                                                      left: BorderSide(
                                                        color: Color(0xFFAB20A1),
                                                        width: 3,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          TextField(
                                            controller: _scriptController,
                                            maxLines: null,
                                            keyboardType: TextInputType.multiline,
                                            style: editorTextStyle,
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.all(editorPadding),
                                              hintText: '脚本内容...',
                                              hintStyle: TextStyle(
                                                color: const Color(0xFF6A9955),
                                                fontSize:
                                                    _editorFontSize * textScale,
                                                fontFamily: 'Courier New',
                                              ),
                                              isDense: true,
                                            ),
                                            onChanged: (_) {
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        setState(() {
                          final maxWidth = (screenSize.width - _windowLeft)
                              .clamp(_minWidth, screenSize.width);
                          final maxHeight = (screenSize.height - _windowTop)
                              .clamp(_minHeight, screenSize.height);
                          _windowWidth = (_windowWidth + details.delta.dx)
                              .clamp(_minWidth, maxWidth);
                          _windowHeight = (_windowHeight + details.delta.dy)
                              .clamp(_minHeight, maxHeight);
                        });
                      },
                      child: Container(
                        width: 22 * uiScale,
                        height: 22 * uiScale,
                        alignment: Alignment.bottomRight,
                        padding: EdgeInsets.only(
                          right: 5 * uiScale,
                          bottom: 5 * uiScale,
                        ),
                        child: Icon(
                          Icons.drag_handle,
                          size: 14 * uiScale,
                          color: config.themeColors.primary.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
