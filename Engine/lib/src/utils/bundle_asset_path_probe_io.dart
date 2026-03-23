import 'dart:io';

import 'package:path/path.dart' as p;

List<String> _bundleAssetCandidates(String assetRelativePath) {
  final exePath = p.normalize(Platform.resolvedExecutable);
  final exeDir = p.dirname(exePath);
  return <String>[
    p.normalize(
      p.join(
        exeDir,
        '..',
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
        assetRelativePath,
      ),
    ),
    p.normalize(
      p.join(exeDir, 'data', 'flutter_assets', assetRelativePath),
    ),
  ];
}

String? probeBundleAssetAbsolutePath(String assetRelativePath) {
  if (assetRelativePath.trim().isEmpty) {
    return null;
  }

  final candidates = _bundleAssetCandidates(assetRelativePath);

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  return candidates.first;
}

bool? probeBundleAssetExists(String assetRelativePath) {
  if (assetRelativePath.trim().isEmpty) {
    return false;
  }
  final candidates = _bundleAssetCandidates(assetRelativePath);
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return true;
    }
  }
  return false;
}
