import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

class TextSpanWithSize {
  final String text;
  final double? sizeMultiplier;
  
  TextSpanWithSize(this.text, {this.sizeMultiplier});
}

class TextSegment {
  final String text;
  final double? sizeMultiplier;
  final double? waitSeconds;
  final bool isInstantDisplay; // 新增：是否瞬间显示
  
  TextSegment(this.text, {this.sizeMultiplier, this.waitSeconds, this.isInstantDisplay = false});
}

class RichTextParser {
  static String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\[size=[0-9.]+\]'), '')
        .replaceAll('[/size]', '')
        .replaceAll(RegExp(r'\[w=[0-9.]+\]'), '')
        .replaceAll('[pass]', '')
        .replaceAll('[/pass]', '');
  }
  
  static List<TextSegment> parseTextSegments(String text) {
    final List<TextSegment> segments = [];
    final combinedRegex = RegExp(r'\[size=([0-9.]+)\](.*?)\[/size\]|\[w=([0-9.]+)\]|\[pass\](.*?)\[/pass\]');
    
    int lastEnd = 0;
    double? currentSizeMultiplier;
    
    for (final match in combinedRegex.allMatches(text)) {
      // 添加匹配前的普通文本
      if (match.start > lastEnd) {
        final normalText = text.substring(lastEnd, match.start);
        if (normalText.isNotEmpty) {
          segments.add(TextSegment(normalText, sizeMultiplier: currentSizeMultiplier));
        }
      }
      
      if (match.group(1) != null && match.group(2) != null) {
        // 这是一个size标签
        final sizeValue = double.tryParse(match.group(1)!) ?? 1.0;
        final taggedText = match.group(2)!;
        
        // 在size标签内部可能还有w标签，需要递归解析
        final innerSegments = _parseInnerSegments(taggedText, sizeValue);
        segments.addAll(innerSegments);
        currentSizeMultiplier = null; // 重置
      } else if (match.group(3) != null) {
        // 这是一个w标签
        final waitValue = double.tryParse(match.group(3)!) ?? 0.0;
        segments.add(TextSegment('', waitSeconds: waitValue, sizeMultiplier: currentSizeMultiplier));
      } else if (match.group(4) != null) {
        // 这是一个pass标签
        final passText = match.group(4)!;
        // pass标签内的文本仍然可能包含其他标签，需要递归解析
        final innerSegments = _parseInnerSegments(passText, currentSizeMultiplier, isInstantDisplay: true);
        segments.addAll(innerSegments);
      }
      
      lastEnd = match.end;
    }
    
    // 添加剩余的普通文本
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        segments.add(TextSegment(remainingText, sizeMultiplier: currentSizeMultiplier));
      }
    }
    
    return segments;
  }
  
  static List<TextSegment> _parseInnerSegments(String text, double? sizeMultiplier, {bool isInstantDisplay = false}) {
    final List<TextSegment> segments = [];
    final waitRegex = RegExp(r'\[w=([0-9.]+)\]');
    
    int lastEnd = 0;
    
    for (final match in waitRegex.allMatches(text)) {
      // 添加匹配前的文本
      if (match.start > lastEnd) {
        final normalText = text.substring(lastEnd, match.start);
        if (normalText.isNotEmpty) {
          segments.add(TextSegment(normalText, sizeMultiplier: sizeMultiplier, isInstantDisplay: isInstantDisplay));
        }
      }
      
      // 添加等待段
      final waitValue = double.tryParse(match.group(1)!) ?? 0.0;
      segments.add(TextSegment('', waitSeconds: waitValue, sizeMultiplier: sizeMultiplier, isInstantDisplay: isInstantDisplay));
      
      lastEnd = match.end;
    }
    
    // 添加剩余文本
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        segments.add(TextSegment(remainingText, sizeMultiplier: sizeMultiplier, isInstantDisplay: isInstantDisplay));
      }
    }
    
    return segments;
  }
  
  static List<TextSpanWithSize> parseText(String text) {
    final segments = parseTextSegments(text);
    return segments
        .where((segment) => segment.text.isNotEmpty)
        .map((segment) => TextSpanWithSize(segment.text, sizeMultiplier: segment.sizeMultiplier))
        .toList();
  }
  
  static List<TextSpan> createTextSpans(String text, TextStyle baseStyle) {
    final parsedSpans = parseText(text);
    return parsedSpans.map((span) {
      final style = span.sizeMultiplier != null 
          ? baseStyle.copyWith(fontSize: baseStyle.fontSize! * span.sizeMultiplier!)
          : baseStyle;
      return TextSpan(text: span.text, style: style);
    }).toList();
  }
  
  static List<TextSpan> createPartialTextSpans(String originalText, String displayedText, TextStyle baseStyle) {
    final originalSpans = parseText(originalText);
    final List<TextSpan> result = [];
    
    // 计算已显示的清理后文本长度
    int displayedCleanLength = displayedText.length;
    int currentCleanPos = 0;
    
    for (final span in originalSpans) {
      final spanCleanLength = span.text.length;
      
      if (currentCleanPos + spanCleanLength <= displayedCleanLength) {
        // 完整显示这个span
        final style = span.sizeMultiplier != null 
            ? baseStyle.copyWith(fontSize: baseStyle.fontSize! * span.sizeMultiplier!)
            : baseStyle;
        result.add(TextSpan(text: span.text, style: style));
        currentCleanPos += spanCleanLength;
      } else if (currentCleanPos < displayedCleanLength) {
        // 部分显示这个span
        final partialLength = displayedCleanLength - currentCleanPos;
        final partialText = span.text.substring(0, partialLength);
        final style = span.sizeMultiplier != null 
            ? baseStyle.copyWith(fontSize: baseStyle.fontSize! * span.sizeMultiplier!)
            : baseStyle;
        result.add(TextSpan(text: partialText, style: style));
        break;
      } else {
        break;
      }
    }
    
    return result;
  }
}