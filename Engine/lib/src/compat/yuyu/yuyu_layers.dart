import 'dart:convert';

/// Declarative attribute selection only. Plot control and animation execution
/// continue to use SKS. The resolved pose stores explicit attributes, excluding
/// implicit defaults, so native CharacterState snapshots preserve inheritance.
class YuyuLayerMapping {
  final Map<String, dynamic> combinations;
  final Map<String, dynamic> models;
  final Map<String, dynamic> requests;
  static const statePrefix = 'yuls_';

  YuyuLayerMapping(Map<String, dynamic> data)
    : combinations = Map<String, dynamic>.from(data['combinations'] as Map),
      models = Map<String, dynamic>.from(data['models'] as Map? ?? {}),
      requests = Map<String, dynamic>.from(data['requests'] as Map? ?? {}) {
    if (data['version'] != 1) {
      throw const FormatException('Layer mapping version');
    }
    for (final entry in models.entries) {
      final model = entry.value as Map;
      if (model.keys.toSet().difference({
            'groups',
            'baseGroup',
            'defaults',
            'layers',
            'width',
            'height',
          }).isNotEmpty ||
          [
            model['width'],
            model['height'],
          ].any((v) => v is! int || v <= 0 || v > 32768)) {
        throw const FormatException('Invalid layer canvas');
      }
      final groups = model['groups'] as Map;
      if (groups.isEmpty) throw const FormatException('Empty layer groups');
      final available = <String>{};
      for (final members in groups.values) {
        final names = _names(members);
        if (names.isEmpty || names.toSet().length != names.length) {
          throw const FormatException('Invalid exclusive group');
        }
        available.addAll(names);
      }
      final defaults = _names(model['defaults']);
      _checkSelection(model, defaults);
      for (final layer in model['layers'] as List) {
        if (layer is! Map ||
            layer.keys.toSet().difference({
              'attribute',
              'group',
              'if_all',
              'if_any',
              'if_not',
              'assetName',
              'blend',
            }).isNotEmpty ||
            !(groups[layer['group']] as List? ?? []).contains(
              layer['attribute'],
            )) {
          throw const FormatException('Invalid layer declaration');
        }
        for (final condition in ['if_all', 'if_any', 'if_not']) {
          if (!available.containsAll(_names(layer[condition] ?? []))) {
            throw const FormatException('Unknown layer condition');
          }
        }
        if (layer['assetName'] != null &&
            (layer['assetName'] is! String ||
                !{
                  'normal',
                  'multiplyPreserveAlpha',
                }.contains(layer['blend']))) {
          throw const FormatException('Unmapped layer blend');
        }
      }
      // A fixed, unconditional base is required by this geometry profile.
      final baseGroup = model['baseGroup'];
      if (!groups.containsKey(baseGroup)) {
        throw const FormatException('Missing base group');
      }
      if (!defaults.any((v) => (groups[baseGroup] as List).contains(v)) ||
          (groups[baseGroup] as List).any(
            (v) => !(model['layers'] as List).any(
              (layer) =>
                  layer['group'] == baseGroup &&
                  layer['attribute'] == v &&
                  layer['assetName'] is String &&
                  layer['blend'] == 'normal' &&
                  [
                    'if_all',
                    'if_any',
                    'if_not',
                  ].every((key) => (layer[key] as List? ?? []).isEmpty),
            ),
          )) {
        throw const FormatException(
          'Layer profile requires an unconditional base group',
        );
      }
    }
    for (final request in requests.values) {
      if (request is! Map ||
          !models.containsKey(request['model']) ||
          request.keys.toSet().difference({'model', 'attributes'}).isNotEmpty) {
        throw const FormatException('Invalid layer request');
      }
      _select(models[request['model']] as Map, request['attributes'], const []);
    }
  }

  static List<String> _names(dynamic value, {bool removals = false}) {
    if (value is! List ||
        value.length > 1024 ||
        value.any(
          (v) =>
              v is! String ||
              !RegExp(
                removals
                    ? r'^-?[A-Za-z_][A-Za-z0-9_]*$'
                    : r'^[A-Za-z_][A-Za-z0-9_]*$',
              ).hasMatch(v),
        )) {
      throw const FormatException('Invalid layer attributes');
    }
    return List<String>.from(value);
  }

  static Set<String> _banned(Map model, Set<String> required) => {
    for (final members in (model['groups'] as Map).values)
      if ((members as List).any(required.contains))
        ...members.where((v) => !required.contains(v)).cast<String>(),
  };

  static void _checkSelection(Map model, Iterable<String> selected) {
    final names = selected.toSet();
    final groups = model['groups'] as Map;
    final available = {for (final members in groups.values) ...members as List};
    if (!available.containsAll(names) ||
        groups.values.any(
          (v) => (v as List).where(names.contains).length > 1,
        )) {
      throw const FormatException('Unknown or conflicting layered attributes');
    }
  }

  static List<String> _select(
    Map model,
    dynamic requested,
    List<String> previous,
  ) {
    final required = <String>{};
    final available = {
      for (final members in (model['groups'] as Map).values) ...members as List,
    };
    final optional = previous.where(available.contains).toSet();
    for (final value in _names(requested, removals: true)) {
      final remove = value.startsWith('-');
      final name = remove ? value.substring(1) : value;
      _checkSelection(model, [name]);
      if (remove) {
        required.remove(name);
        optional.remove(name);
      } else {
        required.add(name);
      }
    }
    _checkSelection(model, required);
    final selected = {
      ...required,
      ...optional.difference(_banned(model, required)),
    };
    _checkSelection(model, selected);
    return selected.toList()..sort();
  }

  (String, List<String>) _state(String pose) {
    if (!pose.startsWith(statePrefix) || pose.length > 65536) {
      throw const FormatException('Invalid resolved layer pose');
    }
    final decoded = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(pose.substring(statePrefix.length)),
        ),
      ),
    );
    if (decoded is! List ||
        decoded.length != 2 ||
        !models.containsKey(decoded[0])) {
      throw const FormatException('Unknown layer model');
    }
    final attributes = _names(decoded[1]);
    _checkSelection(models[decoded[0]] as Map, attributes);
    return (decoded[0] as String, attributes);
  }

  String resolvePose(String requested, String? previous) {
    final request = requests[requested] as Map?;
    if (request == null) return requested;
    final model = request['model'] as String;
    List<String> inherited = const [];
    if (previous?.startsWith(statePrefix) == true) {
      final old = _state(previous!);
      inherited = old.$2;
    }
    final selected = _select(
      models[model] as Map,
      request['attributes'],
      inherited,
    );
    return statePrefix +
        base64Url
            .encode(utf8.encode(jsonEncode([model, selected])))
            .replaceAll('=', '');
  }

  List<Map<String, dynamic>> layersFor(String key) {
    final fixed = combinations[key];
    if (fixed is List && fixed.isNotEmpty) {
      return fixed.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    }
    final parts = key.split(':');
    if (parts.length != 3 || parts[2] != '__none') {
      throw FormatException('Unmapped layer combination: $key');
    }
    final (modelId, explicit) = _state(resolvePose(parts[1], null));
    final model = models[modelId] as Map;
    final selected = explicit.toSet();
    final banned = _banned(model, selected);
    selected.addAll(
      _names(model['defaults']).where((v) => !banned.contains(v)),
    );
    final output = <Map<String, dynamic>>[];
    for (final layer in model['layers'] as List) {
      if (!selected.contains(layer['attribute']) ||
          layer['assetName'] == null ||
          !(layer['if_all'] as List? ?? []).every(selected.contains) ||
          ((layer['if_any'] as List? ?? []).isNotEmpty &&
              !(layer['if_any'] as List).any(selected.contains)) ||
          (layer['if_not'] as List? ?? []).any(selected.contains)) {
        continue;
      }
      output.add({
        'assetName': layer['assetName'],
        'layerLevel': output.length,
        'layerType': 'yuyu',
        'blend': layer['blend'],
      });
    }
    if (output.isEmpty) {
      throw const FormatException('Empty resolved layeredimage');
    }
    return output;
  }
}
