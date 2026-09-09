import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../sks_parser/sks_ast.dart';
import '../../sks_parser/sks_parser.dart';
import '../../utils/animation_config.dart';
import 'yuyu_package.dart';
import 'yuyu_nvl.dart';

/// Strict checks are layered on the actual target parser: an ignored source
/// line, missing alias, or unknown API cannot become a successful conversion.
Future<Map<String, dynamic>> validateYuyuPackage(YuyuPackage package) async {
  Future<Map<String, dynamic>> object(String entry) async {
    final file = package.entryFile(entry);
    if (file == null) throw FormatException('Missing mapping: $entry');
    final result = jsonDecode(await file.readAsString());
    if (result is! Map<String, dynamic> || result['version'] != 1) {
      throw FormatException('Unsupported mapping: $entry');
    }
    return result;
  }

  final coverage = await object('reports/mapping-coverage.json');
  final sourceDigests = coverage['sourceSha256'];
  if (sourceDigests is! Map || sourceDigests.isEmpty) {
    throw const FormatException('Missing source snapshot hashes');
  }
  for (final entry in sourceDigests.entries) {
    final file = package.entryFile(entry.key);
    if (file == null ||
        (await sha256.bind(file.openRead()).first).toString() != entry.value) {
      throw FormatException('Mapped source snapshot mismatch: ${entry.key}');
    }
  }
  if (coverage['errors'] is! List ||
      (coverage['errors'] as List).isNotEmpty ||
      coverage['entries'] is! List ||
      (coverage['entries'] as List).any((v) => v['status'] != 'mapped')) {
    throw const FormatException('Source coverage is incomplete');
  }
  final mapping = await object('mappings/source-map.json');
  if (mapping['script'] != 'saki/GameScript/labels/start.sks' ||
      mapping['lines'] is! List) {
    throw const FormatException('Unsupported source map');
  }
  final scripts = package.listFiles('GameScript/labels/', '.sks');
  if (scripts.length != 1 || scripts.single != 'start.sks') {
    throw const FormatException(
      'Sequence profile requires one merged source-mapped script',
    );
  }
  final source = await package.loadText('GameScript/labels/start.sks');
  final sourceLines = const LineSplitter().convert(source);
  final records = mapping['lines'] as List;
  if (records.length != sourceLines.length) {
    throw const FormatException(
      'Source map does not cover every generated line',
    );
  }
  for (var i = 0; i < records.length; i++) {
    if (records[i]['generatedLine'] != i + 1 ||
        records[i]['expectedNode'] is! String) {
      throw FormatException('Invalid source record at line ${i + 1}');
    }
  }
  final expected = [
    for (final record in records)
      if (!const {
        'ChoiceOptionNode',
        'MenuEnd',
      }.contains(record['expectedNode']))
        record['expectedNode'],
  ];
  final script = SksParser().parse(source);
  if (script.children.length != expected.length) {
    throw FormatException(
      'SKS parser dropped or added nodes: expected ${expected.length}, got ${script.children.length}',
    );
  }
  for (var i = 0; i < expected.length; i++) {
    if (!const {
      'LabelNode',
      'JumpNode',
      'SayNode',
      'ReturnNode',
      'ShowNode',
      'HideNode',
      'BackgroundNode',
      'MenuNode',
      'CommentNode',
      'PauseNode',
      'PlayMusicNode',
      'StopMusicNode',
      'PlaySoundNode',
      'StopSoundNode',
      'VoiceNode',
      'StopVoiceNode',
      'NvlNode',
      'EndNvlNode',
    }.contains(expected[i])) {
      throw FormatException(
        'Node is outside the declared mapping profile: ${expected[i]}',
      );
    }
    if (script.children[i].runtimeType.toString() != expected[i]) {
      throw FormatException(
        'Unexpected SKS node $i: expected ${expected[i]}, got ${script.children[i].runtimeType}',
      );
    }
  }
  final characters = <String, String>{};
  final defaultPoses = <String, String?>{};
  final defaultAnimations = <String, String?>{};
  final defaultRepeats = <String, int?>{};
  for (final line in const LineSplitter().convert(
    await package.loadText('GameScript/configs/characters.sks'),
  )) {
    if (line.trim().isEmpty || line.trim().startsWith('//')) continue;
    final match = RegExp(
      r'^(\w+)\s*:\s*"[^"\n]*"\s*:\s*(\w+)(?:\s+at\s+(\w+))?(?:\s+an\s+(\w+)(?:\s+repeat\s+(\d+))?)?$',
    ).firstMatch(line);
    if (match == null || characters.containsKey(match[1])) {
      throw FormatException('Invalid character configuration: $line');
    }
    characters[match[1]!] = match[2]!;
    defaultPoses[match[1]!] = match[3];
    defaultAnimations[match[1]!] = match[4];
    defaultRepeats[match[1]!] = int.tryParse(match[5] ?? '');
  }
  final poses = <String>{};
  for (final line in const LineSplitter().convert(
    await package.loadText('GameScript/configs/poses.sks'),
  )) {
    if (line.trim().isEmpty || line.trim().startsWith('//')) continue;
    final match = RegExp(
      r'^(\w+): scale=([0-9.]+) xcenter=(-?[0-9.]+) ycenter=(-?[0-9.]+) anchor=center$',
    ).firstMatch(line);
    if (match == null ||
        !poses.add(match[1]!) ||
        [2, 3, 4].any((i) => double.tryParse(match[i]!)?.isFinite != true) ||
        double.parse(match[2]!) <= 0) {
      throw FormatException('Invalid mapped pose: $line');
    }
  }
  final animations = AnimationConfigParser().parse(
    await package.loadText('GameScript/configs/animation.sks'),
    strict: true,
  );
  final animationMapping =
      (await object('mappings/animations.json'))['animations'] as Map;
  if (animationMapping.length != animations.length ||
      !animations.keys.toSet().containsAll(animationMapping.keys)) {
    throw const FormatException(
      'Animation mapping and parsed definitions differ',
    );
  }
  for (final definition in animations.values) {
    if (definition.profile != 'yuyuball-sequence-v1') {
      throw const FormatException('Wrong animation profile');
    }
  }
  for (final name in characters.keys) {
    if ((defaultPoses[name] != null && !poses.contains(defaultPoses[name])) ||
        (defaultAnimations[name] != null &&
            !animations.containsKey(defaultAnimations[name]))) {
      throw FormatException('Unresolved character defaults: $name');
    }
    if (defaultRepeats[name] == 0 &&
        animations[defaultAnimations[name]]!.keyframes.fold<double>(
              0,
              (v, k) => v + k.duration,
            ) <=
            0) {
      throw const FormatException(
        'Infinite default animation does not advance time',
      );
    }
  }
  final requiredCapabilities =
      ((package.manifest['compatibility'] as Map)['requiredCapabilities']
              as List)
          .toSet();
  final nvl = package.nvlMapping;
  final usesNvl = script.children.any(
    (node) => node is NvlNode || node is EndNvlNode,
  );
  if ((usesNvl || package.entryFile('mappings/nvl.json') != null) &&
      (package.webEntry == null ||
          !requiredCapabilities.contains('ui.yuyuball-web-nvl@1'))) {
    throw const FormatException('Web NVL requires its presentation capability');
  }
  final layouts = <String>{};
  // The native parser intentionally tolerates unknown tokens. This profile
  // accepts only the complete generated spelling and checks parsed values too.
  for (var i = 0; i < records.length; i++) {
    if (records[i]['expectedNode'] == 'NvlNode') {
      final match = RegExp(
        r'^nvl style:yuyu_(nvl[2-6]?) layout:(\w+) preserve( replace)?$',
      ).firstMatch(sourceLines[i]);
      if (match == null ||
          nvl.blocks[match[2]]?.mode != match[1] ||
          (match[3] == null) != YuyuNvlMapping.accumulates(match[1]!)) {
        throw const FormatException('Invalid NVL presentation instruction');
      }
      layouts.add(match[2]!);
    } else if (records[i]['expectedNode'] == 'EndNvlNode' &&
        sourceLines[i] != 'endnvl') {
      throw const FormatException('Invalid NVL end instruction');
    }
  }
  if (layouts.length != nvl.blocks.length ||
      !layouts.containsAll(nvl.blocks.keys)) {
    throw const FormatException('NVL mapping and source references differ');
  }
  final layers = await package.layerMapping;
  if (layers.models.isNotEmpty &&
      !requiredCapabilities.contains('sks.layers.yuyuball-attributes@1')) {
    throw const FormatException('Layered image capability must be declared');
  }
  if (package.speakerMapping.isNotEmpty ||
      defaultAnimations.values.any((v) => v != null)) {
    if (!requiredCapabilities.contains('sks.characters.yuyuball@1')) {
      throw const FormatException(
        'Character mapping capability must be declared',
      );
    }
  }
  for (final entry in package.speakerMapping.entries) {
    final speaker = entry.value;
    if (speaker is! Map ||
        !characters.containsKey(entry.key) ||
        speaker['name'] is! String ||
        (speaker['color'] != null &&
            (speaker['color'] is! String ||
                !RegExp(
                  r'^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$',
                ).hasMatch(speaker['color'])))) {
      throw const FormatException('Invalid mapped speaker');
    }
  }
  for (final model in layers.models.values) {
    for (final layer in model['layers'] as List) {
      if (layer['assetName'] != null &&
          package.resolveAsset(layer['assetName']) == null) {
        throw const FormatException('Unresolved conditional layer asset');
      }
    }
  }
  final labels = <String>{};
  for (final node in script.children.whereType<LabelNode>()) {
    if (!labels.add(node.name)) {
      throw FormatException('Duplicate label: ${node.name}');
    }
  }
  if (!labels.contains(package.entryLabel)) {
    throw const FormatException('Missing entry label');
  }
  for (final node in script.children) {
    if (node is NvlNode) {
      final block = nvl.blocks[node.layout];
      if (block == null ||
          node.presentation != 'yuyu_${block.mode}' ||
          !node.preserve ||
          node.accumulate != YuyuNvlMapping.accumulates(block.mode)) {
        throw const FormatException('Parsed NVL state differs from mapping');
      }
    }
    if (node is JumpNode && !labels.contains(node.targetLabel)) {
      throw FormatException('Missing jump target: ${node.targetLabel}');
    }
    if (node is MenuNode) {
      if (node.choices.isEmpty ||
          node.choices.any((v) => !labels.contains(v.targetLabel))) {
        throw const FormatException('Invalid menu target');
      }
    }
    if (node is ShowNode) {
      if (!characters.containsKey(node.character) ||
          !poses.contains(node.position ?? defaultPoses[node.character]) ||
          (node.animation != null && !animations.containsKey(node.animation))) {
        throw const FormatException('Unresolved show configuration');
      }
      final key =
          '${characters[node.character]}:${node.pose}:${node.expression}';
      final combination = layers.layersFor(key);
      if (combination.isEmpty ||
          combination.any(
            (v) => package.resolveAsset(v['assetName']) == null,
          )) {
        throw FormatException('Unresolved layer combination: $key');
      }
      if (node.repeatCount == 0 &&
          animations[node.animation]!.keyframes.fold<double>(
                0,
                (v, k) => v + k.duration,
              ) <=
              0) {
        throw const FormatException('Infinite animation does not advance time');
      }
    }
    if (node is SayNode &&
        node.character != null &&
        !characters.containsKey(node.character)) {
      throw FormatException('Unknown speaker: ${node.character}');
    }
    String? asset;
    if (node is BackgroundNode) asset = node.background;
    if (node is PlayMusicNode) asset = node.musicFile;
    if (node is PlaySoundNode) asset = node.soundFile;
    if (node is VoiceNode) asset = node.voiceFile;
    if (asset != null && package.resolveAsset(asset) == null) {
      throw FormatException('Unmapped asset: $asset');
    }
  }
  return {
    'status': 'mapping-validated',
    'packageSha256': package.digest,
    'validator': 'saki-yuyu-sequence-v1',
    'nodes': script.children.length,
    'labels': labels.length,
    'animations': animations.length,
    'runtimeParity': 'not-verified',
  };
}
