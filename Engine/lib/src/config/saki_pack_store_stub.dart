import 'dart:typed_data';

class SakiPackStore {
  static final SakiPackStore instance = SakiPackStore._();

  SakiPackStore._();

  Future<bool> ensureInitialized() async => false;

  bool contains(String virtualPath) => false;

  String? resolveVirtualAssetPath(String name) => null;

  Future<String?> loadText(String virtualPath) async => null;

  Future<Uint8List?> loadBytes(String virtualPath) async => null;

  Future<String?> materializeFilePath(String virtualPath) async => null;

  Future<String?> resolvePathForPlayback(String pathOrName) async => null;

  List<String> listFileNames(String directory, String extension) =>
      const <String>[];
}
