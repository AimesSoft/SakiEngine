class RuntimeProjectConfig {
  final String? projectName;
  final String? appName;
  final String? gamePath;
  final String? packageDigest;

  const RuntimeProjectConfig({
    this.projectName,
    this.appName,
    this.gamePath,
    this.packageDigest,
  });
}

class RuntimeProjectConfigStore {
  static final RuntimeProjectConfigStore _instance =
      RuntimeProjectConfigStore._internal();

  factory RuntimeProjectConfigStore() => _instance;

  RuntimeProjectConfigStore._internal();

  RuntimeProjectConfig _config = const RuntimeProjectConfig();

  RuntimeProjectConfig get config => _config;

  void configure({
    String? projectName,
    String? appName,
    String? gamePath,
    String? packageDigest,
  }) {
    _config = RuntimeProjectConfig(
      projectName: _normalize(projectName),
      appName: _normalize(appName),
      gamePath: _normalize(gamePath),
      packageDigest: _normalize(packageDigest),
    );
  }

  void clear() {
    _config = const RuntimeProjectConfig();
  }

  String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

void configureRuntimeProject({
  String? projectName,
  String? appName,
  String? gamePath,
  String? packageDigest,
}) {
  RuntimeProjectConfigStore().configure(
    projectName: projectName,
    appName: appName,
    gamePath: gamePath,
    packageDigest: packageDigest,
  );
}

void clearRuntimeProjectConfig() {
  RuntimeProjectConfigStore().clear();
}
