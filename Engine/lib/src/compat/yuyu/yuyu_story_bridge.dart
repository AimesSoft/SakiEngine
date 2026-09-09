import 'dart:async';
import 'package:flutter/material.dart';
import '../../game/game_manager.dart';
import '../../sks_parser/sks_ast.dart';
import '../../utils/dialogue_progression_manager.dart';
import 'yuyu_webview.dart';
import 'yuyu_nvl.dart';

class YuyuMainMenuBridge {
  final YuyuWebChannel channel;
  final VoidCallback onStart;
  bool _starting = false;
  YuyuMainMenuBridge({required this.channel, required this.onStart});

  Future<void> handle(Map<String, dynamic> message) async {
    switch (message['type']) {
      case 'game:start':
        if (_starting) return;
        _starting = true;
        onStart();
      case 'game:getContext':
        await channel.send({
          'type': 'game:context',
          'context': 'main_menu',
          'screen': 'web',
          'debugMode': false,
        });
      case 'game:pointer':
      case 'game:key':
        // The web page owns menu controls. There is no story stage to send
        // these input notifications to until a game has started.
        return;
      default:
        throw UnsupportedError(
          'Unmapped YuYuball menu message: ${message['type']}',
        );
    }
  }
}

/// The small, versioned core bridge. Additional original UI protocols must be
/// implemented before a package can require ui.yuyuball-web@1.
class YuyuStoryBridge {
  final YuyuWebChannel channel = YuyuWebChannel();
  final ValueNotifier<Offset?> pointer = ValueNotifier(null);
  final Map<String, dynamic> _snapshot = {};
  GameManager? _manager;
  StreamSubscription<GameState>? _states;
  final YuyuNvlMapping nvl;
  String _mode = 'adv';
  NvlDialogue? _lastNvlLine;
  YuyuStoryBridge({this.nvl = const YuyuNvlMapping.empty()});

  void attachManager(GameManager manager) {
    if (_disposed || identical(_manager, manager)) return;
    unawaited(_states?.cancel());
    _manager = manager;
    _states = manager.gameStateStream.listen(observeState);
    observeState(manager.currentState);
  }

  void bindProgression(DialogueProgressionManager? value) {
    if (!identical(progression, value)) {
      progression?.externalTypewriterComplete = null;
      progression?.finishExternalTypewriter = null;
      progression = value;
    }
    progression?.externalTypewriterComplete = () => canAdvance;
    progression?.finishExternalTypewriter = finishTypewriter;
  }

  /// Observe every VM emission, including an end/begin pair in one Flutter
  /// frame. Widget rebuilds alone can omit those intermediate mode changes.
  void observeState(GameState state) {
    if (_disposed) return;
    final presentation = state.isNvlMode ? state.nvlPresentation : null;
    final mode = presentation?.startsWith('yuyu_') == true
        ? presentation!.substring(5)
        : 'adv';
    if (mode == 'adv') {
      if (_mode != 'adv') {
        final old = _snapshot['game:dialogue']?['dialogue'] as Map?;
        if (old != null && old['visible'] == true) {
          _send({
            'type': 'game:dialogue',
            'dialogue': {...old, 'visible': false},
          });
        }
        _dialogueKey = null;
        _lastNvlLine = null;
        _mode = mode;
      }
      return;
    }
    final block = nvl.blocks[state.nvlLayout];
    if (block == null || block.mode != mode) {
      throw const FormatException('Unmapped NVL presentation state');
    }
    final expected = block.expectedLines;
    if (mode != _mode) {
      _mode = mode;
      _dialogueKey = null;
      final old = _snapshot['game:dialogue']?['dialogue'] as Map?;
      if (old != null && old['visible'] == true) {
        _send({
          'type': 'game:dialogue',
          'dialogue': {
            ...old,
            'mode': mode,
            'lines': [],
            'currentLineIndex': -1,
            'expectedLines': expected,
            'expectedLineCount': expected.length,
          },
        });
      }
    }
    final last = state.nvlDialogues.lastOrNull;
    if (identical(last, _lastNvlLine)) return;
    _lastNvlLine = last;
    if (last == null) return;
    final lines = [
      for (final line in state.nvlDialogues)
        {
          'who': YuyuNvlMapping.cleanText(line.speaker ?? ''),
          'what': YuyuNvlMapping.cleanText(line.dialogue),
          'text': YuyuNvlMapping.lineText(
            YuyuNvlMapping.cleanText(line.speaker ?? ''),
            YuyuNvlMapping.cleanText(line.dialogue),
            line.presentation?.substring(5) ?? mode,
          ),
        },
    ];
    _newDialogue(_manager?.isFastForwardMode ?? false);
    _send({
      'type': 'game:dialogue',
      'dialogue': {
        'id': _dialogueId,
        'visible': state.isNvlOverlayVisible,
        'who': lines.last['who'],
        'what': lines.map((v) => v['text']).join('\n'),
        'mode': mode,
        'lines': lines,
        'currentLineIndex': lines.length - 1,
        'expectedLines': expected,
        'expectedLineCount': expected.length,
        'seen': false,
      },
    });
  }

  void _newDialogue(bool fast) {
    _dialogueId = 'd${++_serial}';
    _advanceAccepted = false;
    _typingComplete = fast;
    _choices = {};
    _choose = null;
    _send({
      'type': 'game:context',
      'context': 'dialogue',
      'screen': 'say',
      'debugMode': false,
    });
    _send({'type': 'game:choiceHide', 'id': _choiceId});
  }

  DialogueProgressionManager? progression;
  ValueChanged<String>? _choose;
  Map<String, String> _choices = {};
  String? _dialogueKey;
  String _dialogueId = '';
  String _choiceId = '';
  int _serial = 0;
  bool _typingComplete = true;
  bool _advanceAccepted = false;
  bool ready = false;
  bool _disposed = false;
  Size viewport = Size.zero;

  bool get canAdvance =>
      ready &&
      _typingComplete &&
      !_advanceAccepted &&
      _snapshot['game:dialogue']?['dialogue']?['visible'] == true;
  void _advance() {
    if (!ready ||
        _choices.isNotEmpty ||
        _advanceAccepted ||
        _snapshot['game:dialogue']?['dialogue']?['visible'] != true) {
      return;
    }
    _advanceAccepted = progression?.progressDialogue() ?? false;
  }

  void finishTypewriter() {
    unawaited(
      channel.send({'type': 'game:typewriterSkip', 'dialogueId': _dialogueId}),
    );
  }

  void _send(Map<String, dynamic> payload) {
    if (_disposed) return;
    if (payload['type'] == 'game:choiceHide') _snapshot.remove('game:choice');
    if (payload['type'] == 'game:choice') _snapshot.remove('game:choiceHide');
    _snapshot[payload['type']] = payload;
    unawaited(channel.send(payload));
  }

  void presentDialogue({
    required String text,
    String? speaker,
    required int scriptIndex,
    required DialogueProgressionManager? progressionManager,
    bool fast = false,
  }) {
    if (_disposed) return;
    bindProgression(progressionManager);
    final key = '$scriptIndex:$speaker:$text';
    if (_dialogueKey == key) return;
    _dialogueKey = key;
    _mode = 'adv';
    _lastNvlLine = null;
    _newDialogue(fast);
    _send({
      'type': 'game:dialogue',
      'dialogue': {
        'id': _dialogueId,
        'visible': true,
        'who': YuyuNvlMapping.cleanText(speaker ?? ''),
        'what': YuyuNvlMapping.cleanText(text),
        'mode': 'adv',
        'lines': [],
        'currentLineIndex': -1,
        'expectedLines': [],
        'expectedLineCount': 0,
        'seen': false,
      },
    });
  }

  void presentChoices(MenuNode menu, ValueChanged<String> onChoice) {
    _choiceId = 'c${++_serial}';
    _choose = onChoice;
    _choices = {
      for (var i = 0; i < menu.choices.length; i++)
        '$i': menu.choices[i].targetLabel,
    };
    _send({
      'type': 'game:context',
      'context': 'choice',
      'screen': 'web',
      'debugMode': false,
    });
    _send({
      'type': 'game:choice',
      'choice': {
        'id': _choiceId,
        'items': [
          for (var i = 0; i < menu.choices.length; i++)
            {
              'id': '$i',
              'index': i + 1,
              'caption': menu.choices[i].text,
              'enabled': true,
            },
        ],
      },
    });
  }

  Future<void> pageReady() async {
    if (_disposed) return;
    ready = true;
    for (final event in List<dynamic>.from(_snapshot.values)) {
      await channel.send(Map<String, dynamic>.from(event));
    }
  }

  Future<void> handle(Map<String, dynamic> message) async {
    if (_disposed) return;
    switch (message['type']) {
      case 'game:getContext':
        for (final event in List<dynamic>.from(_snapshot.values)) {
          await channel.send(Map<String, dynamic>.from(event));
        }
      case 'web:typewriterState':
        if (message['dialogueId'] == _dialogueId &&
            message['complete'] is bool) {
          _typingComplete = message['complete'];
        }
      case 'game:advance':
        if (ready && _choices.isEmpty && message['dialogueId'] == _dialogueId) {
          _advance();
        }
      case 'web:choiceSelect':
        if (!ready || message['id'] != _choiceId) return;
        final target = _choices[message['choice']?.toString()];
        if (target == null) return;
        final choose = _choose;
        _choices = {};
        _choose = null;
        _dialogueKey = null;
        _send({'type': 'game:choiceHide', 'id': _choiceId});
        choose?.call(target);
      case 'game:pointer':
        if (message['action'] == 'leave') {
          pointer.value = null;
          return;
        }
        final x = message['x'], y = message['y'];
        if (x is! num ||
            y is! num ||
            !x.isFinite ||
            !y.isFinite ||
            viewport.isEmpty) {
          return;
        }
        pointer.value = Offset(
          (x / viewport.width * 2 - 1).clamp(-1, 1).toDouble(),
          (y / viewport.height * 2 - 1).clamp(-1, 1).toDouble(),
        );
      case 'game:key':
        if (message['action'] == 'down' &&
            const {'Enter', ' ', 'Space'}.contains(message['key'])) {
          _advance();
        }
      default:
        throw UnsupportedError(
          'Unmapped YuYuball Web message: ${message['type']}',
        );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_states?.cancel());
    _manager = null;
    progression?.externalTypewriterComplete = null;
    progression?.finishExternalTypewriter = null;
    channel.dispose();
    pointer.dispose();
  }
}
