import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/utils/character_attribute_parser.dart';
import 'package:sakiengine/src/utils/character_expression_layers.dart';

void main() {
  group('第二层差分表达式解析', () {
    test('空格语法把第二个 token 提升为第二层', () {
      final parsed = CharacterExpressionLayers.parse('happy mask');
      expect(parsed.nameAt(1), 'happy');
      expect(parsed.nameAt(2), 'mask');
      expect(parsed.encode(), 'happy+--mask');
    });

    test('不带前缀的 token 占用下一个空闲层级，不覆盖显式前缀', () {
      final parsed = CharacterExpressionLayers.parse('--mask happy');
      expect(parsed.nameAt(1), 'happy');
      expect(parsed.nameAt(2), 'mask');
      expect(parsed.encode(), 'happy+--mask');
    });

    test('单横线历史写法仍属于第一层并归一掉前缀', () {
      final parsed = CharacterExpressionLayers.parse('-happy');
      expect(parsed.layers, hasLength(1));
      expect(parsed.nameAt(1), 'happy');
      expect(parsed.encode(), 'happy');
    });

    test('同一层显式重复出现时后者覆盖前者', () {
      final parsed = CharacterExpressionLayers.parse('--sad --happy');
      expect(parsed.layers, hasLength(1));
      expect(parsed.nameAt(2), 'happy');
    });

    test('空格语法产生的是两层而不是同层覆盖', () {
      final parsed = CharacterExpressionLayers.parse('sad happy');
      expect(parsed.nameAt(1), 'sad');
      expect(parsed.nameAt(2), 'happy');
    });

    test('资源 token 保留层级前缀，供磁盘查找使用', () {
      final parsed = CharacterExpressionLayers.parse('happy mask');
      expect(parsed.assetTokenAt(1), 'happy');
      expect(parsed.assetTokenAt(2), '--mask');
      // 渲染顺序按层级升序，与书写顺序无关。
      expect(parsed.layers.map((layer) => layer.level), [1, 2]);
    });

    test('显式清除标记按层生效', () {
      final parsed = CharacterExpressionLayers.parse('happy --none');
      expect(parsed.clearedLevels, {2});
      expect(parsed.nameAt(1), 'happy');
      expect(parsed.layers, hasLength(1));
    });

    test('清除层不会覆盖其它层', () {
      final merged = CharacterExpressionLayers.merge(
        requested: CharacterExpressionLayers.parse('happy --none'),
        other: CharacterExpressionLayers.parse('sad+--mask'),
      );
      expect(merged.nameAt(1), 'happy');
      expect(merged.nameAt(2), isNull);
    });
  });

  group('第二层状态保留', () {
    test('只写第一层时保留当前第二层', () {
      final merged = CharacterExpressionLayers.merge(
        requested: CharacterExpressionLayers.parse('angry'),
        other: CharacterExpressionLayers.parse('happy+--mask'),
      );
      expect(merged.encode(), 'angry+--mask');
    });

    test('写出第二层时覆盖当前第二层', () {
      final merged = CharacterExpressionLayers.merge(
        requested: CharacterExpressionLayers.parse('happy glasses'),
        other: CharacterExpressionLayers.parse('happy+--mask'),
      );
      expect(merged.encode(), 'happy+--glasses');
    });

    test('合并后仍按层级升序输出', () {
      final merged = CharacterExpressionLayers.merge(
        requested: CharacterExpressionLayers.parse('--mask'),
        other: CharacterExpressionLayers.parse('happy'),
      );
      expect(merged.encode(), 'happy+--mask');
    });
  });

  group('角色属性归并', () {
    test('pose + 两个差分 token 归并成多层表达式', () {
      final resolved = CharacterAttributeParser.resolve([
        'pose2',
        'happy',
        'mask',
      ]);
      expect(resolved.pose, 'pose2');
      // AST 保存与剧本一致的空格形态。
      expect(resolved.expression, 'happy --mask');
    });

    test('内联 API token 不参与差分归并', () {
      final resolved = CharacterAttributeParser.resolve([
        'pose2',
        'happy',
        'apiFace(1)',
      ]);
      expect(resolved.pose, 'pose2');
      expect(resolved.expression, 'happy');
    });

    test('写回脚本时第二层保持 -- 前缀，第一层不带前缀', () {
      expect(
        CharacterAttributeParser.expressionTokens('happy+--mask'),
        ['happy', '--mask'],
      );
      expect(CharacterAttributeParser.expressionTokens('-happy'), ['happy']);
      expect(CharacterAttributeParser.expressionTokens(null), isEmpty);
    });
  });
}
