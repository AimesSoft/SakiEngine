import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/localization/script_localization_editing.dart';
import 'package:sakiengine/src/localization/script_localization_workspace.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/widgets/common/square_icon_button.dart';
import 'package:sakiengine/src/widgets/confirm_dialog.dart';
import 'package:sakiengine/src/widgets/game_style_dropdown.dart';
import 'package:sakiengine/src/widgets/game_style_switch.dart';

class FloatingLocalizationEditor extends StatefulWidget {
  final GameManager gameManager;
  final VoidCallback onClose;
  final Future<void> Function()? onReload;
  final ValueChanged<String>? onNotify;

  const FloatingLocalizationEditor({
    super.key,
    required this.gameManager,
    required this.onClose,
    this.onReload,
    this.onNotify,
  });

  @override
  State<FloatingLocalizationEditor> createState() =>
      FloatingLocalizationEditorState();
}

class FloatingLocalizationEditorState
    extends State<FloatingLocalizationEditor> {
  ScriptLocalizationWorkspace? _workspace;
  LocalizationSourceFile? _file;
  final Set<String> _visibleLanguages = {};
  final Map<String, TextEditingController> _controllers = {};
  final ScrollController _scroll = ScrollController();
  final _currentRowKey = GlobalKey();
  final _overlayKey = GlobalKey<OverlayScaffoldState>();
  String? _error;
  String _status = '正在读取剧情…';
  bool _saving = false;
  bool _closing = false;
  int _page = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    SettingsManager().addListener(_onSettingsChanged);
    unawaited(_load());
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() => SakiEngineConfig().updateThemeForDarkMode());
  }

  @override
  void dispose() {
    SettingsManager().removeListener(_onSettingsChanged);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final gamePath = await GamePathResolver.resolveGamePath();
      if (gamePath == null) throw const FormatException('找不到游戏项目目录');
      final workspace = await ScriptLocalizationWorkspace.load(gamePath);
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _visibleLanguages.addAll(workspace.languages);
        _status = '只显示对白与旁白 · 姓名修改会同步到使用同一角色别名的所有句子';
      });
      _locateCurrent();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    }
  }

  List<LocalizationTextEntry> get _rows =>
      _workspace?.dialogue.where((row) => row.file == _file).toList() ?? [];

  void _locateCurrent() {
    final workspace = _workspace;
    if (workspace == null || workspace.storyFiles.isEmpty) return;
    final current =
        widget.gameManager.currentDialogueSourceScriptFile ??
        widget.gameManager.currentScriptFile;
    final file =
        workspace.storyFiles
            .where(
              (file) =>
                  p.basenameWithoutExtension(file.path) ==
                  p.basenameWithoutExtension(current),
            )
            .firstOrNull ??
        workspace.storyFiles.first;
    final rows = workspace.dialogue.where((row) => row.file == file).toList();
    final target = rows.indexWhere(
      (row) =>
          row.lineIndex + 1 == widget.gameManager.currentDialogueSourceLine,
    );
    setState(() {
      _file = file;
      _page = target < 0 ? 0 : target ~/ _pageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _currentRowKey.currentContext;
      if (mounted && targetContext != null) {
        Scrollable.ensureVisible(targetContext, alignment: .25);
      } else {
        _scrollToTop();
      }
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<bool> _save() async {
    if (_saving || _workspace == null) return false;
    setState(() {
      _saving = true;
    });
    try {
      final count = await _workspace!.save();
      if (mounted) {
        setState(() {
          _status = '已保存 $count 个文件';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '保存失败，草稿已保留：$error';
          _saving = false;
        });
      }
      return false;
    }
    try {
      await widget.onReload?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '文件已保存，重载失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
    return true;
  }

  Future<void> requestClose() async {
    await _overlayKey.currentState?.close();
  }

  Future<bool> _confirmClose() async {
    if (_saving || _closing) return false;
    if (!(_workspace?.isDirty ?? false)) return true;
    _closing = true;
    final action = await showDialog<String>(
      context: context,
      builder: (_) => const ConfirmDialog(
        title: '保存多语言修改？',
        content: '正文与说话人名称还有未保存的修改。',
        cancelText: '继续编辑',
        cancelResult: 'cancel',
        alternateText: '放弃修改',
        alternateResult: 'discard',
        alternateIcon: Icons.delete_outline,
        confirmText: '保存并关闭',
        confirmResult: 'save',
      ),
    );
    _closing = false;
    if (!mounted) return false;
    return action == 'discard' || (action == 'save' && await _save());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        (command && event.logicalKey == LogicalKeyboardKey.keyW)) {
      unawaited(requestClose());
      return KeyEventResult.handled;
    }
    if (command && event.logicalKey == LogicalKeyboardKey.keyS) {
      unawaited(_save());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextEditingController _controller(
    LocalizationTextEntry entry,
    String language,
  ) {
    final key = '${entry.file.path}:${entry.lineIndex}:$language';
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: entry.text.value(language)),
    );
  }

  double get _uiScale => context.scaleFor(ComponentType.ui);
  SakiEngineConfig get _config => SakiEngineConfig();

  TextStyle _textStyle(double factor, {Color? color}) {
    return _config.dialogueTextStyle.copyWith(
      fontFamily: _config.dialogueFontFamily,
      fontSize:
          _config.dialogueTextStyle.fontSize! *
          context.scaleFor(ComponentType.text) *
          factor,
      color: color ?? _config.themeColors.onSurface,
      height: 1.6,
    );
  }

  Widget _icon(String tooltip, IconData icon, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        enabled: onPressed != null,
        child: SquareIconButton(
          icon: icon,
          onTap: onPressed ?? () {},
          enabled: onPressed != null,
          bare: true,
          size: 44 * _uiScale,
          iconSize: 26 * _uiScale,
        ),
      ),
    );
  }

  Widget _field(
    LocalizationTextEntry entry,
    String language, {
    bool name = false,
  }) {
    final colors = _config.themeColors;
    return TextField(
      key: ValueKey(
        '${name ? 'name' : 'dialogue'}:${entry.file.path}:${entry.lineIndex}:$language',
      ),
      controller: _controller(entry, language),
      enabled: !_saving,
      minLines: 1,
      maxLines: name ? 2 : null,
      cursorColor: colors.primary,
      style: _textStyle(.8, color: name ? colors.primary : colors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          vertical: 8 * _uiScale,
          horizontal: 4 * _uiScale,
        ),
        border: InputBorder.none,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.primary.withValues(alpha: .1)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.primary.withValues(alpha: .6)),
        ),
        hintStyle: _textStyle(
          .8,
          color: colors.onSurfaceVariant.withValues(alpha: .55),
        ),
        hintText: name ? entry.text.value(entry.defaultTag) : '待翻译…',
      ),
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          try {
            entry.text.setValue(language, newValue.text);
            return newValue;
          } catch (error) {
            setState(() {
              _status = '$error';
            });
            return oldValue;
          }
        }),
      ],
      onChanged: (value) {
        entry.setValue(language, value);
        setState(() {
          _status = '有未保存修改 · 姓名按角色别名同步';
        });
      },
    );
  }

  Widget _row(LocalizationTextEntry entry, int index) {
    final speaker = _workspace!.speakers[entry.speaker];
    final current =
        entry.lineIndex + 1 == widget.gameManager.currentDialogueSourceLine &&
        p.basenameWithoutExtension(entry.file.path) ==
            p.basenameWithoutExtension(
              widget.gameManager.currentDialogueSourceScriptFile ??
                  widget.gameManager.currentScriptFile,
            );
    final colors = _config.themeColors;
    return Container(
      key: current ? _currentRowKey : null,
      padding: EdgeInsets.symmetric(
        vertical: 18 * _uiScale,
        horizontal: 28 * _uiScale,
      ),
      decoration: BoxDecoration(
        color: current ? colors.primary.withValues(alpha: .06) : null,
        border: Border(
          bottom: BorderSide(color: colors.primary.withValues(alpha: .15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}  ·  第 ${entry.lineIndex + 1} 行${entry.speaker == null ? ' · 旁白' : ' · ${entry.speaker}'}${current ? ' · 当前句' : ''}',
            style: _textStyle(.55, color: colors.onSurfaceVariant),
          ),
          SizedBox(height: 6 * _uiScale),
          for (final language in scriptEditorLanguages.keys.where(
            _visibleLanguages.contains,
          ))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108 * _uiScale,
                  child: Padding(
                    padding: EdgeInsets.only(top: 11 * _uiScale),
                    child: Text(
                      scriptEditorLanguages[language]!,
                      style: _textStyle(.6, color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
                if (entry.speaker != null) ...[
                  SizedBox(
                    width: 150 * _uiScale,
                    child: speaker == null
                        ? Padding(
                            padding: EdgeInsets.only(top: 8 * _uiScale),
                            child: Text(entry.speaker!, style: _textStyle(.8)),
                          )
                        : _field(speaker, language, name: true),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 8 * _uiScale),
                    child: Text(
                      '：',
                      style: _textStyle(.8, color: colors.primary),
                    ),
                  ),
                  SizedBox(width: 10 * _uiScale),
                ],
                Expanded(child: _field(entry, language)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _toolbar(ScriptLocalizationWorkspace workspace, int count) {
    final scale = _uiScale;
    final textScale = context.scaleFor(ComponentType.text);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 28 * scale,
        vertical: 16 * scale,
      ),
      decoration: BoxDecoration(
        color: _config.themeColors.surface.withValues(alpha: .3),
        border: Border(
          bottom: BorderSide(
            color: _config.themeColors.primary.withValues(alpha: .2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '剧情文件',
                style: _textStyle(.7, color: _config.themeColors.primary),
              ),
              SizedBox(width: 20 * scale),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    if (_file == null) {
                      return Text('没有剧情文件', style: _textStyle(.7));
                    }
                    return IgnorePointer(
                      ignoring: _saving,
                      child: GameStyleDropdown<LocalizationSourceFile>(
                        key: const ValueKey('localization-file'),
                        config: _config,
                        scale: scale,
                        textScale: textScale,
                        width: constraints.maxWidth,
                        value: _file!,
                        items: workspace.storyFiles
                            .map(
                              (file) => GameStyleDropdownItem(
                                value: file,
                                label: p.relative(
                                  file.path,
                                  from: workspace.root,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (file) {
                          setState(() {
                            _file = file;
                            _page = 0;
                          });
                          _scrollToTop();
                        },
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: 16 * scale),
              _icon('定位当前句', Icons.my_location, _locateCurrent),
              _icon(
                '保存并重载 (⌘/Ctrl+S)',
                Icons.save_outlined,
                _saving ? null : _save,
              ),
            ],
          ),
          SizedBox(height: 16 * scale),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24 * scale,
            runSpacing: 12 * scale,
            children: [
              Text(
                '显示语言',
                style: _textStyle(.7, color: _config.themeColors.primary),
              ),
              for (final language in scriptEditorLanguages.keys.where(
                workspace.languages.contains,
              ))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scriptEditorLanguages[language]!,
                      style: _textStyle(.6),
                    ),
                    SizedBox(width: 12 * scale),
                    Semantics(
                      label: '显示${scriptEditorLanguages[language]}',
                      toggled: _visibleLanguages.contains(language),
                      child: GameStyleSwitch(
                        key: ValueKey('localization-language-$language'),
                        config: _config,
                        scale: scale * .55,
                        value: _visibleLanguages.contains(language),
                        onChanged: (visible) => setState(() {
                          if (visible) {
                            _visibleLanguages.add(language);
                          } else {
                            _visibleLanguages.remove(language);
                          }
                        }),
                      ),
                    ),
                  ],
                ),
              if (workspace.languages.length < scriptEditorLanguages.length)
                IgnorePointer(
                  ignoring: _saving,
                  child: GameStyleDropdown<String>(
                    key: const ValueKey('localization-add-language'),
                    config: _config,
                    scale: scale,
                    textScale: textScale,
                    width: 200 * scale,
                    value: 'add',
                    items: [
                      const GameStyleDropdownItem(
                        value: 'add',
                        label: '新增语言',
                        icon: Icons.add,
                      ),
                      for (final entry in scriptEditorLanguages.entries.where(
                        (entry) => !workspace.languages.contains(entry.key),
                      ))
                        GameStyleDropdownItem(
                          value: entry.key,
                          label: entry.value,
                        ),
                    ],
                    onChanged: (language) {
                      if (language == 'add') return;
                      setState(() {
                        workspace.addLanguage(language);
                        _visibleLanguages.add(language);
                        _status =
                            '已添加 ${scriptEditorLanguages[language]} 空白行，保存后生效';
                      });
                    },
                  ),
                ),
              Text(
                '$count 句${workspace.isDirty ? ' · 未保存' : ''}',
                style: _textStyle(
                  .55,
                  color: _config.themeColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    final rows = _rows;
    final pages = math.max(1, (rows.length / _pageSize).ceil());
    final pageRows = rows.skip(_page * _pageSize).take(_pageSize).toList();
    final scale = _uiScale;
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Material(
          type: MaterialType.transparency,
          child: OverlayScaffold(
            key: _overlayKey,
            title: '多语言编辑器',
            bareCloseButton: true,
            beforeClose: _confirmClose,
            onClose: (_) => widget.onClose(),
            content: Column(
              children: [
                if (workspace != null) _toolbar(workspace, rows.length),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: SelectableText(
                            _error!,
                            style: _textStyle(.75),
                          ),
                        )
                      : workspace == null
                      ? Center(
                          child: CircularProgressIndicator(
                            color: _config.themeColors.primary,
                          ),
                        )
                      : _visibleLanguages.isEmpty
                      ? Center(
                          child: Text('开启一种语言以显示剧情', style: _textStyle(.8)),
                        )
                      : rows.isEmpty
                      ? Center(
                          child: Text('此项目没有可编辑的剧情', style: _textStyle(.8)),
                        )
                      : ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor: WidgetStatePropertyAll(
                              _config.themeColors.primary.withValues(
                                alpha: .35,
                              ),
                            ),
                          ),
                          child: Scrollbar(
                            controller: _scroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              child: Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < pageRows.length;
                                    index++
                                  )
                                    _row(
                                      pageRows[index],
                                      _page * _pageSize + index,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            footer: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 28 * scale,
                vertical: 12 * scale,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: _config.themeColors.primary.withValues(alpha: .2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _textStyle(
                            .55,
                            color: _config.themeColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Shift+L · ⌘/Ctrl+S 保存',
                          style: _textStyle(
                            .5,
                            color: _config.themeColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _icon(
                    '上一页',
                    Icons.chevron_left,
                    _page > 0
                        ? () {
                            setState(() {
                              _page--;
                            });
                            _scrollToTop();
                          }
                        : null,
                  ),
                  Text(
                    '${_page + 1} / $pages',
                    style: _textStyle(.6, color: _config.themeColors.primary),
                  ),
                  _icon(
                    '下一页',
                    Icons.chevron_right,
                    _page + 1 < pages
                        ? () {
                            setState(() {
                              _page++;
                            });
                            _scrollToTop();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
