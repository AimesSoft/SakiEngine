import 'package:sakiengine/src/sks_parser/sks_ast.dart';

class SksParser {
  static const bool _musicParseDiagnostics =
      bool.fromEnvironment('SAKI_MUSIC_PARSE_DIAGNOSTICS', defaultValue: false);

  static void _logMusicParse(String message) {
    if (_musicParseDiagnostics) {
      print('[SksParser][music] $message');
    }
  }

  static bool _isValidHexColor(String color) {
    if (!color.startsWith('#')) return false;
    final hex = color.substring(1);
    return RegExp(r'^([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
        .hasMatch(hex);
  }

  /// 为角色对话添加引号（旁白除外）
  String _formatDialogueWithQuotes(String dialogue, String? character) {
    // 如果没有角色（旁白），直接返回原文本
    if (character == null || character.isEmpty) {
      return dialogue;
    }
    
    // 如果已经有引号，直接返回
    if (dialogue.startsWith('「') && dialogue.endsWith('」')) {
      return dialogue;
    }
    
    // 为角色对话添加引号
    return '「$dialogue」';
  }

  ScriptNode parse(String content) {
    final lines = content.split('\n');
    final nodes = <SksNode>[];
    int i = 0;
    while (i < lines.length) {
      final originalLine = lines[i].trim();
      // 处理行末注释，去掉//后面的内容
      String trimmedLine = originalLine;
      final commentIndex = originalLine.indexOf('//');
      if (commentIndex >= 0) {
        trimmedLine = originalLine.substring(0, commentIndex).trim();
      }
      
      if (trimmedLine.isEmpty || trimmedLine.startsWith('//')) {
        i++;
        continue;
      }
      final parts = trimmedLine
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      final command = parts[0];
      switch (command) {
        case 'label':
          nodes.add(LabelNode(parts[1]));
          break;
        case 'jump':
          nodes.add(JumpNode(parts[1]));
          break;
        case 'return':
          nodes.add(ReturnNode());
          break;
        case 'menu':
          final choiceNodes = <ChoiceOptionNode>[];
          i++; 
          while (i < lines.length) {
            final menuLine = lines[i].trim();
            if (menuLine.startsWith('endmenu')) {
              break;
            }
            if (menuLine.isNotEmpty && !menuLine.startsWith('//')) {
              final choiceMatch = RegExp(r'"([^"]*)"\s+(\w+)')
                  .firstMatch(menuLine);
              if (choiceMatch != null) {
                final text = choiceMatch.group(1)!;
                final targetLabel = choiceMatch.group(2)!;
                choiceNodes.add(ChoiceOptionNode(text, targetLabel));
              }
            }
            i++;
          }
          nodes.add(MenuNode(choiceNodes));
          break;
        case 'endmenu':
          break;
        case 'scene':
          final allParams = parts.sublist(1);
          String backgroundName = '';
          double? timerValue;
          String? fxString;
          List<String>? layers;
          String? transitionType; // 新增：转场类型
          String? animation; // 新增：动画类型
          int? repeatCount; // 新增：重复次数
          
          // 检查是否为多图层语法 [layer1,layer2:params,...]
          if (allParams.isNotEmpty && allParams[0].startsWith('[') && allParams.join(' ').contains(']')) {
            final layerContent = allParams.join(' ');
            final startBracket = layerContent.indexOf('[');
            final endBracket = layerContent.indexOf(']');
            
            if (startBracket >= 0 && endBracket > startBracket) {
              final layerString = layerContent.substring(startBracket + 1, endBracket);
              layers = layerString.split(',').map((s) => s.trim()).toList();
              
              // 第一个图层作为主背景名
              if (layers.isNotEmpty) {
                backgroundName = layers[0].split(':')[0]; // 去掉可能的位置参数
              }
              
              // 解析后续参数（timer, fx, with, an, repeat等）
              final remainingParams = layerContent.substring(endBracket + 1).trim().split(' ').where((s) => s.isNotEmpty).toList();
              int i = 0;
              while (i < remainingParams.length) {
                if (remainingParams[i] == 'timer' && i + 1 < remainingParams.length) {
                  timerValue = double.tryParse(remainingParams[i + 1]);
                  i += 2;
                } else if (remainingParams[i] == 'with' && i + 1 < remainingParams.length) {
                  transitionType = remainingParams[i + 1];
                  i += 2;
                } else if (remainingParams[i] == 'an' && i + 1 < remainingParams.length) {
                  animation = remainingParams[i + 1];
                  i += 2;
                } else if (remainingParams[i] == 'repeat' && i + 1 < remainingParams.length) {
                  repeatCount = int.tryParse(remainingParams[i + 1]);
                  i += 2;
                } else if (remainingParams[i] == 'fx') {
                  if (i + 1 < remainingParams.length) {
                    fxString = remainingParams.sublist(i + 1).join(' ');
                  }
                  break;
                } else {
                  i++;
                }
              }
            }
          } else {
            // 单图层模式 - 改进解析逻辑
            // 首先找到所有关键字的位置
            final timerIndex = allParams.indexOf('timer');
            final withIndex = allParams.indexOf('with');
            final anIndex = allParams.indexOf('an');
            final repeatIndex = allParams.indexOf('repeat');
            final fxIndex = allParams.indexOf('fx');
            
            // 找到第一个关键字的位置，背景名称在这之前
            final keywordIndices = [timerIndex, withIndex, anIndex, repeatIndex, fxIndex]
                .where((index) => index >= 0)
                .toList();
            
            final firstKeywordIndex = keywordIndices.isEmpty ? allParams.length : keywordIndices.reduce((a, b) => a < b ? a : b);
            
            // 背景名称是第一个关键字之前的所有参数
            backgroundName = allParams.sublist(0, firstKeywordIndex).join(' ');
            
            // 解析各个参数
            int i = 0;
            while (i < allParams.length) {
              if (allParams[i] == 'timer' && i + 1 < allParams.length) {
                timerValue = double.tryParse(allParams[i + 1]);
                i += 2;
              } else if (allParams[i] == 'with' && i + 1 < allParams.length) {
                transitionType = allParams[i + 1];
                i += 2;
              } else if (allParams[i] == 'an' && i + 1 < allParams.length) {
                animation = allParams[i + 1];
                i += 2;
              } else if (allParams[i] == 'repeat' && i + 1 < allParams.length) {
                repeatCount = int.tryParse(allParams[i + 1]);
                i += 2;
              } else if (allParams[i] == 'fx') {
                if (i + 1 < allParams.length) {
                  fxString = allParams.sublist(i + 1).join(' ');
                }
                break;
              } else {
                i++;
              }
            }
          }
          
          // 调试输出
          //print('[SksParser] scene解析结果: background="$backgroundName", transition="$transitionType", animation="$animation", repeat=$repeatCount');
          
          // 检查是否为十六进制颜色格式
          if (_isValidHexColor(backgroundName.trim())) {
            nodes.add(BackgroundNode(backgroundName.trim(), timer: timerValue, layers: layers, transitionType: transitionType, animation: animation, repeatCount: repeatCount));
          } else {
            nodes.add(BackgroundNode(backgroundName, timer: timerValue, layers: layers, transitionType: transitionType, animation: animation, repeatCount: repeatCount));
          }
          
          // 如果有fx参数，添加FxNode
          if (fxString != null && fxString.isNotEmpty) {
            nodes.add(FxNode(fxString));
          }
          break;
        case 'movie':
          final allParams = parts.sublist(1);
          String movieFile = '';
          double? timerValue;
          String? fxString;
          List<String>? layers;
          String? transitionType;
          String? animation;
          int? repeatCount;
          
          // 检查是否为多图层语法 [layer1,layer2:params,...]
          if (allParams.isNotEmpty && allParams[0].startsWith('[') && allParams.join(' ').contains(']')) {
            final layerContent = allParams.join(' ');
            final startBracket = layerContent.indexOf('[');
            final endBracket = layerContent.indexOf(']');
            
            if (startBracket >= 0 && endBracket > startBracket) {
              final layerString = layerContent.substring(startBracket + 1, endBracket);
              layers = layerString.split(',').map((s) => s.trim()).toList();
              
              // 第一个图层作为主视频文件名
              if (layers.isNotEmpty) {
                movieFile = layers[0].split(':')[0];
              }
              
              // 解析后续参数（timer, fx, with, an, repeat等）
              final remainingParams = layerContent.substring(endBracket + 1).trim().split(' ').where((s) => s.isNotEmpty).toList();
              int i = 0;
              while (i < remainingParams.length) {
                if (remainingParams[i] == 'timer' && i + 1 < remainingParams.length) {
                  timerValue = double.tryParse(remainingParams[i + 1]);
                  i += 2;
                } else if (remainingParams[i] == 'with' && i + 1 < remainingParams.length) {
                  transitionType = remainingParams[i + 1];
                  i += 2;
                } else if (remainingParams[i] == 'an' && i + 1 < remainingParams.length) {
                  animation = remainingParams[i + 1];
                  i += 2;
                } else if (remainingParams[i] == 'repeat' && i + 1 < remainingParams.length) {
                  repeatCount = int.tryParse(remainingParams[i + 1]);
                  i += 2;
                } else if (remainingParams[i] == 'fx') {
                  if (i + 1 < remainingParams.length) {
                    fxString = remainingParams.sublist(i + 1).join(' ');
                  }
                  break;
                } else {
                  i++;
                }
              }
            }
          } else {
            // 单文件模式
            final timerIndex = allParams.indexOf('timer');
            final withIndex = allParams.indexOf('with');
            final anIndex = allParams.indexOf('an');
            final repeatIndex = allParams.indexOf('repeat');
            final fxIndex = allParams.indexOf('fx');
            
            final keywordIndices = [timerIndex, withIndex, anIndex, repeatIndex, fxIndex]
                .where((index) => index >= 0)
                .toList();
            
            final firstKeywordIndex = keywordIndices.isEmpty ? allParams.length : keywordIndices.reduce((a, b) => a < b ? a : b);
            
            // 视频文件名是第一个关键字之前的所有参数
            movieFile = allParams.sublist(0, firstKeywordIndex).join(' ');
            
            // 解析各个参数
            int i = 0;
            while (i < allParams.length) {
              if (allParams[i] == 'timer' && i + 1 < allParams.length) {
                timerValue = double.tryParse(allParams[i + 1]);
                i += 2;
              } else if (allParams[i] == 'with' && i + 1 < allParams.length) {
                transitionType = allParams[i + 1];
                i += 2;
              } else if (allParams[i] == 'an' && i + 1 < allParams.length) {
                animation = allParams[i + 1];
                i += 2;
              } else if (allParams[i] == 'repeat' && i + 1 < allParams.length) {
                repeatCount = int.tryParse(allParams[i + 1]);
                i += 2;
              } else if (allParams[i] == 'fx') {
                if (i + 1 < allParams.length) {
                  fxString = allParams.sublist(i + 1).join(' ');
                }
                break;
              } else {
                i++;
              }
            }
          }
          
          nodes.add(MovieNode(movieFile, timer: timerValue, layers: layers, transitionType: transitionType, animation: animation, repeatCount: repeatCount));
          
          // 如果有fx参数，添加FxNode
          if (fxString != null && fxString.isNotEmpty) {
            nodes.add(FxNode(fxString));
          }
          break;
        case 'anime':
          // anime命令：anime cg_igiari [loop] [keep] [with diss] [timer 2.0]
          if (parts.length < 2) break;
          
          final animeName = parts[1];
          bool isLoop = false;
          bool keepAfterComplete = false; // 新增：是否在完成后保留
          String? transitionType;
          double? timerValue;
          
          // 解析参数
          for (int i = 2; i < parts.length; i++) {
            if (parts[i].toLowerCase() == 'loop') {
              isLoop = true;
            } else if (parts[i].toLowerCase() == 'keep') { // 新增：keep参数
              keepAfterComplete = true;
            } else if (parts[i] == 'with' && i + 1 < parts.length) {
              transitionType = parts[i + 1];
              i++; // 跳过下一个参数
            } else if (parts[i] == 'timer' && i + 1 < parts.length) {
              timerValue = double.tryParse(parts[i + 1]);
              i++; // 跳过下一个参数
            }
          }
          
          //print('[SksParser] 解析anime命令: $animeName, loop: $isLoop, keep: $keepAfterComplete, transition: $transitionType, timer: $timerValue');
          nodes.add(AnimeNode(animeName, loop: isLoop, keep: keepAfterComplete, transitionType: transitionType, timer: timerValue));
          break;
        case 'show':
          //print('[SksParser] 解析show命令: $trimmedLine');
          final character = parts[1];
          
          // CG显示命令保持为ShowNode，支持叠加显示
          // 但需要特殊处理以支持WebP动图的loop参数
          
          String? pose;
          String? expression;
          String? position;
          String? animation;
          int? repeatCount;
          
          // 支持an语法和repeat语法:
          // show xiayo1 pose1 happy at pose an jump repeat 3
          // x happy an jump repeat 3
          
          int atIndex = -1;
          int anIndex = -1;
          int repeatIndex = -1;
          
          for (int i = 2; i < parts.length; i++) {
            if (parts[i] == 'at') {
              atIndex = i;
            } else if (parts[i] == 'an') {
              anIndex = i;
            } else if (parts[i] == 'repeat') {
              repeatIndex = i;
              break;
            }
          }
          
          // 解析repeat参数
          if (repeatIndex >= 0 && repeatIndex + 1 < parts.length) {
            repeatCount = int.tryParse(parts[repeatIndex + 1]);
          }
          
          int endIndex = repeatIndex >= 0 ? repeatIndex : parts.length;
          
          if (anIndex >= 0 && anIndex < endIndex) {
            // 有an动画语法
            if (anIndex + 1 < endIndex) {
              animation = parts[anIndex + 1];
            }

            if (atIndex >= 0 && atIndex < anIndex) {
              // show character pose1 happy at pose an jump repeat 3
              final attributeParts = parts.sublist(2, atIndex);
              if (attributeParts.isNotEmpty) {
                if (attributeParts.length == 1) {
                  // 只有一个参数时，视为expression，pose使用默认值pose1
                  expression = attributeParts[0];
                } else {
                  // 有两个或更多参数时，第一个是pose，第二个是expression
                  pose = attributeParts[0];
                  expression = attributeParts[1];
                }
              }
              if (atIndex + 1 < anIndex) {
                position = parts[atIndex + 1];
              }
            } else {
              // x happy an jump repeat 3
              final attributeParts = parts.sublist(2, anIndex);
              if (attributeParts.isNotEmpty) {
                expression = attributeParts[0];
              }
            }
          } else if (atIndex >= 0 && atIndex < endIndex) {
            // 原有at语法，无动画
            final attributeParts = parts.sublist(2, atIndex);
            if (attributeParts.isNotEmpty) {
              if (attributeParts.length == 1) {
                // 只有一个参数时，视为expression，pose使用默认值pose1
                expression = attributeParts[0];
              } else {
                // 有两个或更多参数时，第一个是pose，第二个是expression
                pose = attributeParts[0];
                expression = attributeParts[1];
              }
            }
            if (atIndex + 1 < endIndex) {
              position = parts[atIndex + 1];
            }
          } else {
            // 原有pose:语法
            for (int i = 2; i < endIndex; i++) {
              if (parts[i].startsWith('pose:')) {
                pose = parts[i].substring(5);
              } else if (parts[i].startsWith('expression:')) {
                expression = parts[i].substring(11);
              }
            }
          }

          nodes.add(ShowNode(character, pose: pose, expression: expression, position: position, animation: animation, repeatCount: repeatCount));
          break;
        case 'cg':
          //print('[SksParser] 解析cg命令: $trimmedLine');
          final character = parts[1];
          
          // CG显示命令，支持与show相同的参数，但渲染方式像scene一样铺满
          
          String? pose;
          String? expression;
          String? position;
          String? animation;
          int? repeatCount;
          
          // 支持an语法和repeat语法:
          // cg xiayo1 pose1 happy at pose an jump repeat 3
          // cg x happy an jump repeat 3
          
          int atIndex = -1;
          int anIndex = -1;
          int repeatIndex = -1;
          
          for (int i = 2; i < parts.length; i++) {
            if (parts[i] == 'at') {
              atIndex = i;
            } else if (parts[i] == 'an') {
              anIndex = i;
            } else if (parts[i] == 'repeat') {
              repeatIndex = i;
              break;
            }
          }
          
          // 解析repeat参数
          if (repeatIndex >= 0 && repeatIndex + 1 < parts.length) {
            repeatCount = int.tryParse(parts[repeatIndex + 1]);
          }
          
          int endIndex = repeatIndex >= 0 ? repeatIndex : parts.length;
          
          if (anIndex >= 0 && anIndex < endIndex) {
            // 有an动画语法
            if (anIndex + 1 < endIndex) {
              animation = parts[anIndex + 1];
            }

            if (atIndex >= 0 && atIndex < anIndex) {
              // cg character pose1 happy at pose an jump repeat 3
              final attributeParts = parts.sublist(2, atIndex);
              if (attributeParts.isNotEmpty) {
                if (attributeParts.length == 1) {
                  // 只有一个参数时，视为expression，pose使用默认值pose1
                  expression = attributeParts[0];
                } else {
                  // 有两个或更多参数时，第一个是pose，第二个是expression
                  pose = attributeParts[0];
                  expression = attributeParts[1];
                }
              }
              if (atIndex + 1 < anIndex) {
                position = parts[atIndex + 1];
              }
            } else {
              // cg x happy an jump repeat 3
              final attributeParts = parts.sublist(2, anIndex);
              if (attributeParts.isNotEmpty) {
                expression = attributeParts[0];
              }
            }
          } else if (atIndex >= 0 && atIndex < endIndex) {
            // 原有at语法，无动画
            final attributeParts = parts.sublist(2, atIndex);
            if (attributeParts.isNotEmpty) {
              if (attributeParts.length == 1) {
                // 只有一个参数时，视为expression，pose使用默认值pose1
                expression = attributeParts[0];
              } else {
                // 有两个或更多参数时，第一个是pose，第二个是expression
                pose = attributeParts[0];
                expression = attributeParts[1];
              }
            }
            if (atIndex + 1 < endIndex) {
              position = parts[atIndex + 1];
            }
          } else {
            // 简单的参数解析（没有特殊关键词）
            // 检查是否有pose:前缀的参数
            final attributeParts = parts.sublist(2, endIndex);

            bool hasPosePrefix = false;
            for (int i = 0; i < attributeParts.length; i++) {
              if (attributeParts[i].startsWith('pose:')) {
                pose = attributeParts[i].substring(5);
                hasPosePrefix = true;
              } else if (attributeParts[i].startsWith('expression:')) {
                expression = attributeParts[i].substring(11);
              }
            }

            // 如果没有pose:前缀，所有参数都是expression（差分图）
            if (!hasPosePrefix && attributeParts.isNotEmpty) {
              // 将所有参数作为expression
              expression = attributeParts.join(' ');
            }
          }

          //print('[SksParser] CG解析结果: character=$character, pose=$pose, expression=$expression, position=$position, animation=$animation');
          nodes.add(CgNode(character, pose: pose, expression: expression, position: position, animation: animation, repeatCount: repeatCount));
          break;
        case 'hide':
          nodes.add(HideNode(parts[1]));
          break;
        case 'nvl':
          nodes.add(NvlNode());
          break;
        case 'endnvl':
          nodes.add(EndNvlNode());
          break;
        case 'nvln': // 新增：nvln（无遮罩NVL模式）
          nodes.add(NvlnNode());
          break;
        case 'endnvln': // 新增：endnvln
          nodes.add(EndNvlnNode());
          break;
        case 'nvlm':
          nodes.add(NvlMovieNode());
          break;
        case 'endnvlm':
          nodes.add(EndNvlMovieNode());
          break;
        case 'fx':
          final filterString = parts.sublist(1).join(' ');
          nodes.add(FxNode(filterString));
          break;
        case 'play':
          _logMusicParse(
            'line=${i + 1} play raw="$originalLine" parsed="$trimmedLine" parts=${parts.join('|')}',
          );
          if (parts.length >= 3 && parts[1] == 'music') {
            final musicFile = parts.sublist(2).join(' ').trim();
            _logMusicParse('line=${i + 1} parsed play music -> "$musicFile"');
            if (musicFile.isEmpty) {
              _logMusicParse('line=${i + 1} warning: musicFile is empty');
            }
            nodes.add(PlayMusicNode(musicFile));
          } else if (parts.length >= 3 && parts[1] == 'sound') {
            // play sound filename [loop]
            final soundParts = parts.sublist(2);
            final soundFile = soundParts[0];
            final loop = soundParts.length > 1 && soundParts[1] == 'loop';
            nodes.add(PlaySoundNode(soundFile, loop: loop));
          }
          break;
        case 'stop':
          if (parts.length >= 2 && parts[1] == 'music') {
            nodes.add(StopMusicNode());
          } else if (parts.length >= 2 && parts[1] == 'sound') {
            nodes.add(StopSoundNode());
          }
          break;
        case 'bool':
          if (parts.length >= 3) {
            final variableName = parts[1];
            final value = parts[2].toLowerCase() == 'true';
            nodes.add(BoolNode(variableName, value));
          }
          break;
        case 'pause':
          // pause(1.5) - 暂停指定秒数
          if (parts.length >= 2) {
            // 支持两种格式：pause(1.5) 或 pause 1.5
            String durationStr = parts[1];
            
            // 如果是 pause(1.5) 格式，提取括号内的数字
            final parenRegex = RegExp(r'pause\(([0-9.]+)\)');
            final parenMatch = parenRegex.firstMatch(trimmedLine);
            if (parenMatch != null) {
              durationStr = parenMatch.group(1)!;
            }
            
            final duration = double.tryParse(durationStr);
            if (duration != null && duration > 0) {
              nodes.add(PauseNode(duration));
              //print('[SksParser] 解析pause命令: duration=$duration');
            } else {
              print('[SksParser] 警告: 无效的pause时长: $durationStr');
            }
          }
          break;
        case 'shake':
          // shake [duration 1.0] [intensity 8.0] [target background]
          double? duration;
          double? intensity;
          String? target;
          
          // 解析参数
          for (int i = 1; i < parts.length; i++) {
            if (parts[i] == 'duration' && i + 1 < parts.length) {
              duration = double.tryParse(parts[i + 1]);
              i++; // 跳过下一个参数
            } else if (parts[i] == 'intensity' && i + 1 < parts.length) {
              intensity = double.tryParse(parts[i + 1]);
              i++; // 跳过下一个参数
            } else if (parts[i] == 'target' && i + 1 < parts.length) {
              target = parts[i + 1];
              i++; // 跳过下一个参数
            }
          }
          
          nodes.add(ShakeNode(duration: duration, intensity: intensity, target: target));
          break;
        default:
          final sayNode = _parseSay(trimmedLine);
          if (sayNode != null) {
            //print('[SksParser] 解析SayNode: character=${sayNode.character}, pose=${sayNode.pose}, expression=${sayNode.expression}, dialogue=${sayNode.dialogue}');
            nodes.add(sayNode);
          } else {
            //print('[SksParser] 无法解析行: $trimmedLine');
          }
          break;
      }
      i++;
    }
    return ScriptNode(nodes);
  }

  SksNode? _parseSay(String line) {
    // 先处理行末注释
    String processedLine = line;
    final commentIndex = line.indexOf('//');
    if (commentIndex >= 0) {
      processedLine = line.substring(0, commentIndex).trim();
    }
    
    // 检查是否是pause语法：pause(0.5) 
    final pauseRegex = RegExp(r'^pause\(([0-9.]+)\)$');
    final pauseMatch = pauseRegex.firstMatch(processedLine);
    if (pauseMatch != null) {
      final durationStr = pauseMatch.group(1)!;
      final duration = double.tryParse(durationStr);
      if (duration != null && duration > 0) {
        return PauseNode(duration);
      } else {
        print('[SksParser] 警告: 无效的pause时长: $durationStr');
        return null;
      }
    }
    
    // 检查是否是时序差分切换语法: x [wakuwaku2,0.5,think] "我去。"
    final timedExpressionRegex = RegExp(r'^(\w+)\s*\[([^,]+),([^,]+),([^\]]+)\]\s*"([^"]*)"$');
    final timedMatch = timedExpressionRegex.firstMatch(processedLine);
    
    if (timedMatch != null) {
      final character = timedMatch.group(1)!.trim();
      final startExpression = timedMatch.group(2)!.trim();
      final delayStr = timedMatch.group(3)!.trim();
      final endExpression = timedMatch.group(4)!.trim();
      final dialogue = timedMatch.group(5)!;
      
      final switchDelay = double.tryParse(delayStr);
      if (switchDelay == null || switchDelay <= 0) {
        print('[SksParser] 警告: 无效的延迟时间 "$delayStr"，跳过时序差分切换');
        return null;
      }
      
      //print('[SksParser] 解析时序差分切换: $character [$startExpression,$switchDelay,$endExpression] "$dialogue"');
      
      return SayNode(
        character: character,
        dialogue: _formatDialogueWithQuotes(dialogue, character),
        startExpression: startExpression,
        switchDelay: switchDelay,
        endExpression: endExpression,
      );
    }
    
    // 检查是否是条件对话 "dialogue" if variable true/false
    final conditionalRegex = RegExp(r'^(.*?)\s*"([^"]+)"\s+if\s+(\w+)\s+(true|false)\s*$');
    final conditionalMatch = conditionalRegex.firstMatch(processedLine);
    
    if (conditionalMatch != null) {
      final beforeQuote = conditionalMatch.group(1)!.trim();
      final dialogue = conditionalMatch.group(2)!;
      final variableName = conditionalMatch.group(3)!;
      final conditionValue = conditionalMatch.group(4)! == 'true';
      
      String? character;
      String? pose;
      String? expression;
      String? position;
      String? animation;
      int? repeatCount;
      
      // 解析角色和属性（如果存在）
      if (beforeQuote.isNotEmpty) {
        final parts = beforeQuote.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          character = parts[0];
          
          // 解析其他属性
          if (parts.length > 1) {
            final attrs = parts.sublist(1);
            
            // 查找at、an和repeat关键字位置
            int atIndex = -1;
            int anIndex = -1;
            int repeatIndex = -1;
            for (int i = 0; i < attrs.length; i++) {
              if (attrs[i] == 'at') {
                atIndex = i;
              } else if (attrs[i] == 'an') {
                anIndex = i;
              } else if (attrs[i] == 'repeat') {
                repeatIndex = i;
                break;
              }
            }
            
            // 解析repeat参数
            if (repeatIndex >= 0 && repeatIndex + 1 < attrs.length) {
              repeatCount = int.tryParse(attrs[repeatIndex + 1]);
            }
            
            int endIndex = repeatIndex >= 0 ? repeatIndex : attrs.length;
            
            List<String> regularAttrs;
            
            if (anIndex >= 0 && anIndex < endIndex) {
              // 有an动画语法
              if (anIndex + 1 < endIndex) {
                animation = attrs[anIndex + 1];
              }
              
              if (atIndex >= 0 && atIndex < anIndex) {
                // at在an之前：character pose expression at position an animation
                final attributeParts = attrs.sublist(0, atIndex);
                regularAttrs = attributeParts;
                if (atIndex + 1 < anIndex) {
                  position = attrs[atIndex + 1];
                }
              } else {
                // 没有at或at在an之后（无效）
                regularAttrs = attrs.sublist(0, anIndex);
              }
            } else if (atIndex >= 0 && atIndex < endIndex) {
              // 有at但没有an：character pose expression at position
              final attributeParts = attrs.sublist(0, atIndex);
              regularAttrs = attributeParts;
              if (atIndex + 1 < endIndex) {
                position = attrs[atIndex + 1];
              }
            } else {
              // 没有特殊语法，都是普通属性
              regularAttrs = attrs.sublist(0, endIndex);
            }
            
            // 解析普通属性
            for (final attr in regularAttrs) {
              if (attr.startsWith('pose') || attr.contains('pose')) {
                pose = attr;
              } else {
                expression = attr;
              }
            }
          }
        }
      }
      
      return ConditionalSayNode(
        dialogue: _formatDialogueWithQuotes(dialogue, character),
        character: character,
        conditionVariable: variableName,
        conditionValue: conditionValue,
        pose: pose,
        expression: expression,
        position: position,
        animation: animation,
        repeatCount: repeatCount,
      );
    }
    
    // 继续原有的解析逻辑
    
    // Improved regex to capture character, attributes and dialogue
    // 1: Optional character and attributes part
    // 2: Dialogue part
    final sayRegex = RegExp(r'^(.*?)\s*"([^"]*)"$');
    final match = sayRegex.firstMatch(processedLine);

    if (match == null) {
      // Simple narration check for lines that are just "dialogue"
      final simpleNarrationRegex = RegExp(r'^"([^"]*)"$');
      final simpleMatch = simpleNarrationRegex.firstMatch(processedLine);
      if (simpleMatch != null) {
        return SayNode(dialogue: _formatDialogueWithQuotes(simpleMatch.group(1)!, null));
      }
      return null;
    }
    
    final dialogue = match.group(2)!;
    final beforeQuote = match.group(1)!.trim();

    if (beforeQuote.isEmpty) {
      // Narration: "dialogue"
      return SayNode(dialogue: _formatDialogueWithQuotes(dialogue, null));
    }
    
    final parts = beforeQuote.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null; // Should not happen with this regex, but for safety

    final character = parts[0];
    String? pose;
    String? expression;
    String? position;
    int? repeatCount;
    
    // 解析pose、expression、position、animation和repeat属性
    if (parts.length > 1) {
        final attrs = parts.sublist(1);
        
        // 查找at、an和repeat关键字位置
        int atIndex = -1;
        int anIndex = -1;
        int repeatIndex = -1;
        for (int i = 0; i < attrs.length; i++) {
          if (attrs[i] == 'at') {
            atIndex = i;
          } else if (attrs[i] == 'an') {
            anIndex = i;
          } else if (attrs[i] == 'repeat') {
            repeatIndex = i;
            break;
          }
        }
        
        // 解析repeat参数
        if (repeatIndex >= 0 && repeatIndex + 1 < attrs.length) {
          repeatCount = int.tryParse(attrs[repeatIndex + 1]);
        }
        
        int endIndex = repeatIndex >= 0 ? repeatIndex : attrs.length;
        
        String? animation;
        List<String> regularAttrs;
        
        if (anIndex >= 0 && anIndex < endIndex) {
          // 有an动画语法
          if (anIndex + 1 < endIndex) {
            animation = attrs[anIndex + 1];
          }
          
          if (atIndex >= 0 && atIndex < anIndex) {
            // at在an之前：character pose expression at position an animation
            final attributeParts = attrs.sublist(0, atIndex);
            regularAttrs = attributeParts;
            if (atIndex + 1 < anIndex) {
              position = attrs[atIndex + 1];
            }
          } else {
            // 没有at或at在an之后（无效）
            regularAttrs = attrs.sublist(0, anIndex);
          }
        } else if (atIndex >= 0 && atIndex < endIndex) {
          // 有at但没有an：character pose expression at position
          final attributeParts = attrs.sublist(0, atIndex);
          regularAttrs = attributeParts;
          if (atIndex + 1 < endIndex) {
            position = attrs[atIndex + 1];
          }
        } else {
          // 没有特殊语法，都是普通属性
          regularAttrs = attrs.sublist(0, endIndex);
        }
        
        // 解析普通属性
        for (final attr in regularAttrs) {
          if (attr.startsWith('pose') || attr.contains('pose')) {
            pose = attr;
          } else {
            expression = attr;
          }
        }
        
        return SayNode(character: character, dialogue: _formatDialogueWithQuotes(dialogue, character), pose: pose, expression: expression, position: position, animation: animation, repeatCount: repeatCount);
    }
    
    return SayNode(character: character, dialogue: _formatDialogueWithQuotes(dialogue, character), pose: pose, expression: expression, position: position);
  }
} 
