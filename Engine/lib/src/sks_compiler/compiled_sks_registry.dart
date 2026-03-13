import 'package:flutter/foundation.dart';
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
    if (kDebugMode) {
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

    final expectedProject = RuntimeProjectConfigStore().config.projectName;
    final expected = expectedProject?.trim();
    if (expected == null || expected.isEmpty) {
      return true;
    }

    final bundledProject = bundle.gameName?.trim();
    if (bundledProject == null || bundledProject.isEmpty) {
      return true;
    }

    return expected.toLowerCase() == bundledProject.toLowerCase();
  }
}
