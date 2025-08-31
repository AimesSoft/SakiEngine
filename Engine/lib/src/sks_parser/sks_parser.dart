import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/rendering/color_background_renderer.dart';

class SksParser {
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
      final parts = trimmedLine.split(' ');
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
              
              // 解析后续参数（timer, fx, with等）
              final remainingParams = layerContent.substring(endBracket + 1).trim().split(' ').where((s) => s.isNotEmpty).toList();
              int i = 0;
              while (i < remainingParams.length) {
                if (remainingParams[i] == 'timer' && i + 1 < remainingParams.length) {
                  timerValue = double.tryParse(remainingParams[i + 1]);
                  i += 2;
                } else if (remainingParams[i] == 'with' && i + 1 < remainingParams.length) {
                  transitionType = remainingParams[i + 1];
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
            // 单图层模式（原有逻辑）
            int i = 0;
            while (i < allParams.length) {
              if (allParams[i] == 'timer' && i + 1 < allParams.length) {
                timerValue = double.tryParse(allParams[i + 1]);
                i += 2;
              } else if (allParams[i] == 'with' && i + 1 < allParams.length) {
                transitionType = allParams[i + 1];
                i += 2;
              } else if (allParams[i] == 'fx') {
                if (i + 1 < allParams.length) {
                  fxString = allParams.sublist(i + 1).join(' ');
                }
                break;
              } else {
                backgroundName += (backgroundName.isEmpty ? '' : ' ') + allParams[i];
                i++;
              }
            }
          }
          
          // 检查是否为十六进制颜色格式
          if (ColorBackgroundRenderer.isValidHexColor(backgroundName.trim())) {
            nodes.add(BackgroundNode(backgroundName.trim(), timer: timerValue, layers: layers, transitionType: transitionType));
          } else {
            nodes.add(BackgroundNode(backgroundName, timer: timerValue, layers: layers, transitionType: transitionType));
          }
          
          // 如果有fx参数，添加FxNode
          if (fxString != null && fxString.isNotEmpty) {
            nodes.add(FxNode(fxString));
          }
          break;
        case 'show':
          print('[SksParser] 解析show命令: $trimmedLine');
          final character = parts[1];
          String? pose;
          String? expression;
          String? position;
          String? animation;
          
          // 支持三种语法格式:
          // 1. show character pose:xxx expression:xxx
          // 2. show character pose1 happy at pose
          // 3. show character pose1 happy at pose an jump
          
          int atIndex = -1;
          int anIndex = -1;
          
          for (int i = 2; i < parts.length; i++) {
            if (parts[i] == 'at') {
              atIndex = i;
            } else if (parts[i] == 'an') {
              anIndex = i;
              break;
            }
          }
          
          if (atIndex >= 0 || anIndex >= 0) {
            // 新语法: show character pose1 happy at pose an jump
            int endIndex = anIndex >= 0 ? anIndex : (atIndex >= 0 ? parts.length : parts.length);
            if (atIndex >= 0 && anIndex >= 0) {
              endIndex = anIndex;
            } else if (atIndex >= 0) {
              endIndex = parts.length;
            }
            
            final attributeParts = parts.sublist(2, atIndex >= 0 ? atIndex : anIndex);
            if (attributeParts.isNotEmpty) {
              pose = attributeParts[0]; // 第一个属性作为pose
              if (attributeParts.length > 1) {
                expression = attributeParts[1]; // 第二个属性作为expression
              }
            }
            
            if (atIndex >= 0) {
              int positionEnd = anIndex >= 0 ? anIndex : parts.length;
              if (atIndex + 1 < positionEnd) {
                position = parts[atIndex + 1]; // at后面的参数作为位置
              }
            }
            
            if (anIndex >= 0 && anIndex + 1 < parts.length) {
              animation = parts[anIndex + 1]; // an后面的参数作为动画
            }
          } else {
            // 原语法: show character pose:xxx expression:xxx
            for (int i = 2; i < parts.length; i++) {
              if (parts[i].startsWith('pose:')) {
                pose = parts[i].substring(5);
              } else if (parts[i].startsWith('expression:')) {
                expression = parts[i].substring(11);
              }
            }
          }
          
          nodes.add(ShowNode(character, pose: pose, expression: expression, position: position, animation: animation));
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
          if (parts.length >= 3 && parts[1] == 'music') {
            final musicFile = parts.sublist(2).join(' ');
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
        default:
          final sayNode = _parseSay(trimmedLine);
          if (sayNode != null) {
            nodes.add(sayNode);
          }
          break;
      }
      i++;
    }
    return ScriptNode(nodes);
  }

  SayNode? _parseSay(String line) {
    // 先处理行末注释
    String processedLine = line;
    final commentIndex = line.indexOf('//');
    if (commentIndex >= 0) {
      processedLine = line.substring(0, commentIndex).trim();
    }
    
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
        return SayNode(dialogue: simpleMatch.group(1)!);
      }
      return null;
    }
    
    final dialogue = match.group(2)!;
    final beforeQuote = match.group(1)!.trim();

    if (beforeQuote.isEmpty) {
      // Narration: "dialogue"
      return SayNode(dialogue: dialogue);
    }
    
    final parts = beforeQuote.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null; // Should not happen with this regex, but for safety

    final character = parts[0];
    String? pose;
    String? expression;
    String? animation;
    
    // 查找an关键字
    int anIndex = -1;
    for (int i = 1; i < parts.length; i++) {
      if (parts[i] == 'an') {
        anIndex = i;
        break;
      }
    }
    
    // 解析pose和expression（在an之前的属性）
    if (parts.length > 1) {
      final attributeEndIndex = anIndex >= 0 ? anIndex : parts.length;
      final attrs = parts.sublist(1, attributeEndIndex);
      
      // 简单的启发式方法：第一个属性作为pose，第二个作为expression
      if (attrs.isNotEmpty) {
        pose = attrs[0];
        if (attrs.length > 1) {
          expression = attrs[1];
        }
      }
    }
    
    // 解析动画（在an之后）
    if (anIndex >= 0 && anIndex + 1 < parts.length) {
      animation = parts[anIndex + 1];
    }
    
    return SayNode(character: character, dialogue: dialogue, pose: pose, expression: expression, animation: animation);
  }
} 