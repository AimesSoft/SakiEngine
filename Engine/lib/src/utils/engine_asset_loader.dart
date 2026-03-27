import 'dart:ui' as ui;

import 'package:flutter/services.dart';

class EngineAssetLoader {
  static const String _packagePrefix = 'packages/sakiengine/';

  static String _toPackageAssetPath(String assetPath) {
    if (assetPath.startsWith(_packagePrefix)) {
      return assetPath;
    }
    return '$_packagePrefix$assetPath';
  }

  static String _toWebHostedPackageAssetPath(String assetPath) {
    final packagePath = _toPackageAssetPath(assetPath);
    if (packagePath.startsWith('assets/')) {
      return packagePath;
    }
    return 'assets/$packagePath';
  }

  static String _stripAssetsPrefix(String assetPath) {
    if (assetPath.startsWith('assets/')) {
      return assetPath.substring('assets/'.length);
    }
    return assetPath;
  }

  static List<String> _buildCandidates(String assetPath) {
    final candidates = <String>[];
    final seen = <String>{};

    void add(String value) {
      if (seen.add(value)) {
        candidates.add(value);
      }
    }

    final stripped = _stripAssetsPrefix(assetPath);
    add(assetPath);
    add(stripped);
    add(_toPackageAssetPath(assetPath));
    add(_toPackageAssetPath(stripped));
    add(_toWebHostedPackageAssetPath(assetPath));
    add(_toWebHostedPackageAssetPath(stripped));
    return candidates;
  }

  static Future<String> loadString(String assetPath,
      {bool cache = true}) async {
    Object? lastError;
    for (final candidate in _buildCandidates(assetPath)) {
      try {
        return await rootBundle.loadString(candidate, cache: cache);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Failed to load asset: $assetPath');
  }

  static Future<ui.FragmentProgram> loadFragmentProgram(
      String assetPath) async {
    Object? lastError;
    for (final candidate in _buildCandidates(assetPath)) {
      try {
        return await ui.FragmentProgram.fromAsset(candidate);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Failed to load shader: $assetPath');
  }
}
