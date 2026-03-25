import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';
import 'package:sakiengine/src/sks_compiler/generated/compiled_sks_bundle.g.dart'
    as generated_bundle;

class CompiledSksRegistry {
  CompiledSksRegistry._internal();

  static final CompiledSksRegistry instance = CompiledSksRegistry._internal();

  CompiledSksBundle? _overrideBundle;
  CompiledSksBundle? _generatedBundle;
  bool _generatedLoaded = false;

  void registerOverrideBundle(CompiledSksBundle bundle) {
    _overrideBundle = bundle;
  }

  void clearOverrideBundle() {
    _overrideBundle = null;
  }

  CompiledSksBundle? get activeBundle {
    if (kEngineDebugMode) {
      return null;
    }

    final override = _overrideBundle;
    if (_isBundleUsable(override)) {
      return override;
    }

    final generated = _loadGeneratedBundle();
    if (_isBundleUsable(generated)) {
      return generated;
    }

    return null;
  }

  CompiledSksBundle? _loadGeneratedBundle() {
    if (_generatedLoaded) {
      return _generatedBundle;
    }
    _generatedLoaded = true;
    _generatedBundle = generated_bundle.loadGeneratedCompiledSksBundle();
    return _generatedBundle;
  }

  bool _isBundleUsable(CompiledSksBundle? bundle) {
    if (bundle == null || !bundle.hasAnyData) {
      return false;
    }

    final expectedProjectKeys = _expectedProjectKeys();
    if (expectedProjectKeys.isEmpty) {
      return true;
    }

    final bundledProjectKey = _normalizeProjectKey(bundle.gameName);
    if (bundledProjectKey == null) {
      return true;
    }

    return expectedProjectKeys.contains(bundledProjectKey);
  }

  Set<String> _expectedProjectKeys() {
    final runtimeConfig = RuntimeProjectConfigStore().config;
    final keys = <String>{};

    void addCandidate(String? candidate) {
      final key = _normalizeProjectKey(candidate);
      if (key != null) {
        keys.add(key);
      }
    }

    addCandidate(runtimeConfig.projectName);
    addCandidate(runtimeConfig.appName);
    addCandidate(runtimeConfig.gamePath);

    return keys;
  }

  String? _normalizeProjectKey(String? value) {
    if (value == null) {
      return null;
    }

    var normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    final pathParts = normalized.split(RegExp(r'[\\/]+'));
    if (pathParts.isNotEmpty) {
      normalized = pathParts.last;
    }

    normalized = normalized.replaceFirst(RegExp(r'\.exe$'), '');

    var key = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (key.isEmpty) {
      return null;
    }

    final withoutEngineSuffix = key.replaceFirst(RegExp(r'sakiengine$'), '');
    if (withoutEngineSuffix.isNotEmpty) {
      key = withoutEngineSuffix;
    }

    return key;
  }
}
