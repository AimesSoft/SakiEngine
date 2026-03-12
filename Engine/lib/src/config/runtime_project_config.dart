class RuntimeProjectConfig {
  final String? projectName;
  final String? appName;
  final String? gamePath;

  const RuntimeProjectConfig({
    this.projectName,
    this.appName,
    this.gamePath,
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
  }) {
    _config = RuntimeProjectConfig(
      projectName: _normalize(projectName),
      appName: _normalize(appName),
      gamePath: _normalize(gamePath),
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
}) {
  RuntimeProjectConfigStore().configure(
    projectName: projectName,
    appName: appName,
    gamePath: gamePath,
  );
}

void clearRuntimeProjectConfig() {
  RuntimeProjectConfigStore().clear();
}
