import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

Color? parseColor(String? colorStr) {
  if (colorStr == null) {
    return null;
  }

  final trimmed = colorStr.trim();
  
  if (trimmed.startsWith('#')) {
    try {
      return Color(int.parse(trimmed.replaceFirst('#', '0xff')));
    } catch (e) {
      return null;
    }
  } else if (trimmed.startsWith('rgb')) {
    final valuesRegex = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)');
    final match = valuesRegex.firstMatch(trimmed);
    if (match != null) {
      try {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        
        if (match.group(4) != null) { 
          final a = double.parse(match.group(4)!);
          return Color.fromRGBO(r, g, b, a);
        } else {
          return Color.fromRGBO(r, g, b, 1.0);
        }
      } catch(e) {
        return null;
      }
    }
  }
  return null;
}
