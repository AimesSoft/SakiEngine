import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unicode;
import 'yuyu_layers.dart';
import 'yuyu_nvl.dart';

/// Versioned content container. Script execution remains in SksParser/GameManager.
class YuyuPackage {
  static const capabilities = <String>{
    'sks.core@1',
    'sks.animation.yuyuball-sequence@1',
    'ui.yuyuball-web-core@1',
    'ui.yuyuball-web-nvl@1',
    'sks.layers.yuyuball-attributes@1',
    'sks.characters.yuyuball@1',
  };
  static YuyuPackage? active;
  final String digest;
  final Map<String, dynamic> manifest;
  final Directory directory;
  final Map<String, String> aliases;
  final Map<String, File> _files;
  bool _closed = false;
  Future<YuyuLayerMapping>? _layers;
  Future<YuyuLayerMapping> get layerMapping => _layers ??= () async {
    final file = entryFile('mappings/layers.json');
    if (file == null) throw const FormatException('Missing layer mapping');
    return YuyuLayerMapping(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }();
  late final Map<String, dynamic> speakerMapping = () {
    final file = entryFile('mappings/characters.json');
    if (file == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(
      (jsonDecode(file.readAsStringSync()) as Map)['speakers'] as Map,
    );
  }();

  late final YuyuNvlMapping nvlMapping = () {
    final file = entryFile('mappings/nvl.json');
    return file == null
        ? const YuyuNvlMapping.empty()
        : YuyuNvlMapping(
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
          );
  }();

  YuyuPackage._(
    this.digest,
    this.manifest,
    this.directory,
    this.aliases,
    this._files,
  );

  String get gameId => (manifest['game'] as Map)['id'] as String;
  String get gameName => (manifest['game'] as Map)['name'] as String;
  String get entryLabel =>
      (manifest['compatibility'] as Map)['entryLabel'] as String;
  String? get webEntry => (manifest['web'] as Map?)?['entry'] as String?;

  static String validatePath(String value) {
    final parts = value.split('/');
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains(RegExp(r'[\x00-\x1f\x7f:<>"|?*]')) ||
        parts.any(
          (v) =>
              v.isEmpty ||
              v == '.' ||
              v == '..' ||
              v.endsWith('.') ||
              v.endsWith(' ') ||
              RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false,
              ).hasMatch(v),
        )) {
      throw FormatException('Unsafe package path: $value');
    }
    return value;
  }

  static String _key(String path) => unicode.nfc(path).toLowerCase();

  /// Verifies all entries before exposing the package. Media is streamed to disk.
  /// Each mount owns a fresh directory, so interrupted or stale caches cannot win.
  static Future<YuyuPackage> open(
    String path, {
    Directory? cacheRoot,
    Set<String> supportedCapabilities = capabilities,
    int maxEntries = 100000,
    int maxEntryBytes = 16 * 1024 * 1024 * 1024,
    int maxTotalBytes = 64 * 1024 * 1024 * 1024,
    bool forValidation = false,
  }) async {
    final inputFile = File(path);
    final digest = (await sha256.bind(inputFile.openRead()).first).toString();
    final input = InputFileStream(path);
    Directory? staging;
    try {
      // Inspect central headers before ZipDecoder can coalesce duplicate names
      // or read the contents of a symlink.
      final zip = ZipDirectory()..read(input);
      if (zip.fileHeaders.length > maxEntries) {
        throw const FormatException('Too many package entries');
      }
      final names = <String>{};
      final rawNames = <String>{};
      var total = 0;
      for (final header in zip.fileHeaders) {
        final name = validatePath(header.filename);
        final mode = (header.externalFileAttributes >> 16) & 0xf000;
        if (!names.add(_key(name)) || !rawNames.add(name)) {
          throw FormatException('Colliding package entry: $name');
        }
        if ((mode != 0 && mode != 0x8000) ||
            (header.generalPurposeBitFlag & 1) != 0 ||
            !const {0, 8}.contains(header.compressionMethod) ||
            header.file?.filename != name ||
            header.diskNumberStart != 0 ||
            header.uncompressedSize < 0 ||
            header.uncompressedSize > maxEntryBytes ||
            header.localHeaderOffset < 0 ||
            header.localHeaderOffset >= inputFile.lengthSync()) {
          throw FormatException('Unsupported or invalid ZIP entry: $name');
        }
        total += header.uncompressedSize;
        if (total > maxTotalBytes) {
          throw const FormatException('Package exceeds extraction limit');
        }
      }
      for (final name in names) {
        var parent = p.posix.dirname(name);
        while (parent != '.') {
          if (names.contains(parent)) {
            throw FormatException('File/directory collision: $name');
          }
          parent = p.posix.dirname(parent);
        }
      }
      final entries = {
        for (final header in zip.fileHeaders) header.filename: header,
      };
      List<int> metadataBytes(String name) {
        final header = entries[name];
        if (header == null || header.uncompressedSize > 8 * 1024 * 1024) {
          throw FormatException('Missing or oversized metadata: $name');
        }
        final output = _BoundedMemoryOutput(header.uncompressedSize);
        header.file!.decompress(output);
        if (output.length != header.uncompressedSize) {
          throw FormatException('Invalid size: $name');
        }
        return output.getBytes();
      }

      Map<String, dynamic> object(List<int> bytes) {
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) {
          throw const FormatException('Expected JSON object');
        }
        return result;
      }

      final manifest = object(metadataBytes('manifest.json'));
      final compatibility = manifest['compatibility'] as Map?;
      if (compatibility?['publicationTarget'] == 'yuyuball' &&
          compatibility?['status'] != 'mapping-validated') {
        throw const FormatException(
          '此 .yuyu 是 YuYuball 发行内容包，Saki 映射尚未通过校验。请使用 YuYuball 运行。',
        );
      }
      final game = manifest['game'] as Map?;
      final stage = manifest['stage'] as Map?;
      bool dimension(dynamic value) =>
          value is int && value > 0 && value <= 16384;
      if (!dimension(stage?['width']) ||
          !dimension(stage?['height']) ||
          (manifest['sourceRuntime'] as Map?)?['root'] != 'game') {
        throw const FormatException('Invalid stage or source game root');
      }
      if (manifest['format'] != 'yuyu' ||
          (manifest['formatVersion'] as Map?)?['major'] != 1 ||
          manifest['contentIndex'] != 'index.json' ||
          compatibility?['method'] != 'rpy-to-sks' ||
          compatibility?['mappingProfile'] != 'yuyuball-to-sks-sequence-v1' ||
          !(compatibility?['status'] == 'mapping-validated' ||
              (forValidation && compatibility?['status'] == 'converted')) ||
          compatibility?['scriptRoot'] != 'saki/GameScript' ||
          game?['id'] is! String ||
          !RegExp(
            r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$',
          ).hasMatch(game!['id']) ||
          game['name'] is! String ||
          compatibility?['entryLabel'] is! String) {
        throw const FormatException('Unsupported or incomplete .yuyu manifest');
      }
      final required = compatibility!['requiredCapabilities'];
      if (required is! List ||
          !required.contains('sks.core@1') ||
          !required.contains('sks.animation.yuyuball-sequence@1') ||
          required.any(
            (v) => v is! String || !supportedCapabilities.contains(v),
          )) {
        throw FormatException('Unsupported package capabilities: $required');
      }
      if (manifest['web'] != null &&
          !const {
            'yuyuball-web-core-v1',
            'yuyuball-web-nvl-v1',
          }.contains((manifest['web'] as Map?)?['bridgeProfile'])) {
        throw const FormatException('Unsupported Web bridge profile');
      }
      final indexBytes = metadataBytes('index.json');
      if (sha256.convert(indexBytes).toString() != manifest['indexSha256']) {
        throw const FormatException('Package index checksum mismatch');
      }
      final index = object(indexBytes);
      if (index['version'] != 1 || index['entries'] is! Map) {
        throw const FormatException('Unsupported package index');
      }
      final indexed = Map<String, dynamic>.from(index['entries']);
      final payloadNames = rawNames.difference({'manifest.json', 'index.json'});
      if (indexed.length != payloadNames.length ||
          !payloadNames.containsAll(indexed.keys)) {
        throw const FormatException('Index does not cover the package exactly');
      }
      final root = cacheRoot ?? Directory.systemTemp;
      await root.create(recursive: true);
      staging = await root.createTemp('yuyu-${digest.substring(0, 16)}-');
      final files = <String, File>{};
      for (final name in payloadNames) {
        final record = indexed[name];
        final header = entries[name]!;
        if (record is! Map ||
            record['size'] != header.uncompressedSize ||
            record['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(record['sha256'])) {
          throw FormatException('Invalid index entry: $name');
        }
        final file = File(p.joinAll([staging.path, ...name.split('/')]));
        await file.parent.create(recursive: true);
        final output = _BoundedFileOutput(file.path, header.uncompressedSize);
        try {
          header.file!.decompress(output);
        } finally {
          output.closeSync();
        }
        if (await file.length() != header.uncompressedSize ||
            (await sha256.bind(file.openRead()).first).toString() !=
                record['sha256']) {
          throw FormatException('Package content checksum mismatch: $name');
        }
        files[name] = file;
      }
      final assetFile = files['mappings/assets.json'];
      if (assetFile == null) {
        throw const FormatException('Missing asset mappings');
      }
      final assetMapping = object(await assetFile.readAsBytes());
      if (assetMapping['version'] != 1 || assetMapping['aliases'] is! Map) {
        throw const FormatException('Invalid asset mappings');
      }
      final aliases = <String, String>{};
      void addAlias(String name, String target) {
        validatePath(name);
        if (!files.containsKey(target)) {
          throw FormatException('Missing mapped asset: $target');
        }
        final key = _key(name);
        if (aliases.containsKey(key) && aliases[key] != target) {
          throw FormatException('Ambiguous asset: $name');
        }
        aliases[key] = target;
      }

      for (final entry in (assetMapping['aliases'] as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Invalid asset alias');
        }
        addAlias(entry.key, entry.value);
      }
      for (final name in files.keys.where(
        (v) => v.startsWith('saki/GameScript/'),
      )) {
        addAlias(name.substring(5), name);
      }
      final webEntry = (manifest['web'] as Map?)?['entry'];
      if (webEntry != null && !files.containsKey(webEntry)) {
        throw const FormatException('Missing Web UI entry');
      }
      if (webEntry != null && !required.contains('ui.yuyuball-web-core@1')) {
        throw const FormatException(
          'Web UI requires an explicit supported bridge capability',
        );
      }
      final nvlProfile =
          (manifest['web'] as Map?)?['bridgeProfile'] == 'yuyuball-web-nvl-v1';
      if (nvlProfile != required.contains('ui.yuyuball-web-nvl@1') ||
          (nvlProfile && webEntry == null)) {
        throw const FormatException('NVL Web profile/capability mismatch');
      }
      return YuyuPackage._(
        digest,
        manifest,
        staging,
        Map.unmodifiable(aliases),
        files,
      );
    } catch (_) {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    } finally {
      input.closeSync();
    }
  }

  File? entryFile(String entry) {
    if (_closed) throw StateError('Package has been closed');
    return _files[entry];
  }

  String? resolveAsset(String name) {
    if (_closed) throw StateError('Package has been closed');
    var key = _key(name);
    if (key.startsWith('assets/')) key = key.substring(7);
    final target = aliases[key] ?? aliases['assets/$key'];
    return target == null ? null : _files[target]!.path;
  }

  Future<String> loadText(String name) async {
    final file = resolveAsset(name);
    if (file == null) throw FormatException('Unmapped .yuyu text asset: $name');
    return File(file).readAsString();
  }

  List<String> listFiles(String directory, String extension) {
    if (_closed) throw StateError('Package has been closed');
    var prefix = _key(directory);
    if (prefix.startsWith('assets/')) prefix = prefix.substring(7);
    if (!prefix.endsWith('/')) prefix += '/';
    final result = <String>{};
    for (final entry in aliases.entries) {
      if (entry.key.startsWith(prefix)) {
        final tail = entry.key.substring(prefix.length);
        if (!tail.contains('/') && tail.endsWith(extension.toLowerCase())) {
          result.add(tail);
        }
      }
    }
    return result.toList()..sort();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(active, this)) active = null;
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _BoundedFileOutput extends OutputFileStream {
  final int limit;
  _BoundedFileOutput(String path, this.limit)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));
  void _check(int count) {
    if (length + count > limit) {
      throw const FormatException(
        'Decompressed entry exceeds its declared size',
      );
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      writeBytes(stream.readBytes(stream.length.clamp(0, 65536)).toUint8List());
    }
  }
}

class _BoundedMemoryOutput extends OutputMemoryStream {
  final int limit;
  _BoundedMemoryOutput(this.limit);
  void _check(int count) {
    if (length + count > limit) {
      throw const FormatException('Metadata exceeds its declared size');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
