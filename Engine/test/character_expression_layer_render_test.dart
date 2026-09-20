import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/character_expression_layers.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/widgets/expression_focus_preview.dart';

/// 1x1 透明 PNG，足够让资源查找命中。
const List<int> _transparentPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SKS 演出语法的第二层差分', () {
    test('第二层 token 直接接在第一层之后', () {
      final script = SksParser().parse('x pose2 happy mask "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.pose, 'pose2');
      expect(say.expression, 'happy --mask');
    });

    test('未写姿态时第一层仍是差分而不是姿态', () {
      final script = SksParser().parse('x happy mask "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.pose, isNull);
      expect(say.expression, 'happy --mask');
    });

    test('没有第二层时表达式保持单层', () {
      final script = SksParser().parse('x pose1 happy "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.pose, 'pose1');
      expect(say.expression, 'happy');
    });

    test('显式 -- 前缀与空格语法等价', () {
      final script = SksParser().parse('x happy --mask "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.expression, 'happy --mask');
    });

    test('an/repeat 属性不会混进差分名', () {
      final script = SksParser().parse('x happy mask an jump repeat 2 "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.expression, 'happy --mask');
      expect(say.animation, 'jump');
      expect(say.repeatCount, 2);
    });

    test('at 位置语法与两层差分共存', () {
      final script = SksParser().parse('x happy mask at center "台词"\n');
      final say = script.children.single as SayNode;
      expect(say.expression, 'happy --mask');
      expect(say.position, 'center');
    });

    test('show 命令同样支持第二层', () {
      final script = SksParser().parse('show xiayo1 pose1 happy mask\n');
      final show = script.children.single as ShowNode;
      expect(show.pose, 'pose1');
      expect(show.expression, 'happy --mask');
    });
  });

  group('分层资源解析', () {
    late Directory gameDirectory;

    setUp(() {
      gameDirectory = Directory.systemTemp.createTempSync('saki_layer_diff_');
      final charactersDir = Directory(
        '${gameDirectory.path}/Assets/images/characters',
      )..createSync(recursive: true);
      // GamePathResolver 通过 Assets + GameScript 识别游戏根目录。
      Directory(
        '${gameDirectory.path}/GameScript/labels',
      ).createSync(recursive: true);
      for (final name in [
        'xiayo1-pose1',
        'xiayo1-angry',
        'xiayo1-happy',
        'xiayo1-sad',
        'xiayo1--mask',
        'xiayo1--glasses',
      ]) {
        File(
          '${charactersDir.path}/$name.png',
        ).writeAsBytesSync(_transparentPng);
      }
      configureRuntimeProject(gamePath: gameDirectory.path);
      GamePathResolver.clearCache();
      CharacterLayerParser.clearCache();
    });

    tearDown(() {
      CharacterLayerParser.clearCache();
      clearRuntimeProjectConfig();
      GamePathResolver.clearCache();
      if (gameDirectory.existsSync()) {
        gameDirectory.deleteSync(recursive: true);
      }
    });

    test('第二层解析到 -- 资源并按层级升序排列', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'happy+--mask',
      );

      expect(layers.map((layer) => layer.layerLevel), [0, 1, 2]);
      expect(layers[1].assetName, 'characters/xiayo1-happy');
      expect(layers[2].assetName, 'characters/xiayo1--mask');
      expect(layers[2].layerType, 'expression_layer_2');
    });

    test('空格写法的表达式直接可用', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'happy mask',
      );
      expect(layers.last.assetName, 'characters/xiayo1--mask');
    });

    test('只写第一层时不会带上第二层图层', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'sad',
      );
      expect(layers, hasLength(2));
      expect(layers.last.assetName, 'characters/xiayo1-sad');
    });

    test('第二层换层不会影响第一层', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'sad+--glasses',
      );
      expect(layers[1].assetName, 'characters/xiayo1-sad');
      expect(layers[2].assetName, 'characters/xiayo1--glasses');
    });

    test('第二层缺失时不做默认补位，缺图交给渲染层跳过', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'happy+--unknown',
      );
      expect(layers.map((layer) => layer.layerLevel), [0, 1, 2]);
      expect(layers.last.assetName, 'characters/xiayo1--unknown');
    });

    test('第一层缺失时仍按字母序回退到该层默认差分', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'xiayo1',
        pose: 'pose1',
        expression: 'unknown',
      );
      expect(layers, hasLength(2));
      // 该层字母序第一个可用差分是 angry。
      expect(layers.last.assetName, 'characters/xiayo1-angry');
    });

    test('可用图层列表保留第二层的层级前缀', () async {
      final available = await AssetManager.getAvailableCharacterLayers(
        'xiayo1',
      );

      // `xiayo1--mask` 必须还原成 `--mask`，否则层级信息会在扫描时丢掉。
      expect(available, contains('--mask'));
      expect(available, contains('--glasses'));
      expect(available, contains('happy'));
      expect(CharacterExpressionLayers.levelOfToken('--mask'), 2);
    });

    test('该层默认差分带上正确层级前缀', () async {
      final defaultLayer = await AssetManager.getDefaultLayerForLevel(
        'xiayo1',
        2,
      );
      expect(defaultLayer, '--glasses');
    });
  });

  group('资源放在角色子目录时', () {
    late Directory gameDirectory;

    setUp(() {
      gameDirectory = Directory.systemTemp.createTempSync('saki_subdir_diff_');
      // 真实项目常见布局：characters/<角色文件夹>/<资源前缀>-<图层>.png
      final charactersDir = Directory(
        '${gameDirectory.path}/Assets/images/characters/noe_front',
      )..createSync(recursive: true);
      Directory(
        '${gameDirectory.path}/GameScript/labels',
      ).createSync(recursive: true);
      for (final name in [
        'noe-pose1',
        'noe-angry',
        'noe-happy',
        'noe--mask',
      ]) {
        File(
          '${charactersDir.path}/$name.png',
        ).writeAsBytesSync(_transparentPng);
      }
      configureRuntimeProject(gamePath: gameDirectory.path);
      GamePathResolver.clearCache();
      CharacterLayerParser.clearCache();
    });

    tearDown(() {
      CharacterLayerParser.clearCache();
      clearRuntimeProjectConfig();
      GamePathResolver.clearCache();
      if (gameDirectory.existsSync()) {
        gameDirectory.deleteSync(recursive: true);
      }
    });

    test('图层扫描递归进入角色子目录', () async {
      final available = await AssetManager.getAvailableCharacterLayers('noe');
      expect(available, contains('pose1'));
      expect(available, contains('happy'));
      expect(available, contains('--mask'));
    });

    test('缺层回退在子目录布局下同样可用', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'noe',
        pose: 'pose1',
        expression: 'missing',
      );
      expect(layers, hasLength(2));
      // 子目录里的图层能被回退逻辑看到，角色才不会没有表情层。
      expect(layers.last.assetName, 'characters/noe-angry');
    });

    test('第二层在子目录布局下正常叠加', () async {
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'noe',
        pose: 'pose1',
        expression: 'happy --mask',
      );
      expect(layers.map((layer) => layer.layerLevel), [0, 1, 2]);
      expect(layers[1].assetName, 'characters/noe-happy');
      expect(layers[2].assetName, 'characters/noe--mask');
    });

    testWidgets('层2 预览用双横线资源名，不会多拼一个', (tester) async {
      final repository = ExpressionPreviewMetadataRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 400,
              child: ExpressionFocusPreview(
                metadataRepository: repository,
                characterId: 'noe',
                pose: 'pose1',
                expression: 'mask',
                layerLevel: 2,
                baseLayerAssetNames: const [
                  'characters/noe-pose1',
                  'characters/noe-happy',
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final assets = tester
          .widgetList<SmartAssetImage>(find.byType(SmartAssetImage))
          .map((widget) => widget.assetName)
          .toList();
      // 层2 的资源是 `characters/noe--mask`；多拼一个横线会变成
      // `noe---mask`，预览就会整块空掉。
      expect(assets, contains('characters/noe--mask'));
      expect(assets, contains('characters/noe-happy'));
    });
  });
}
