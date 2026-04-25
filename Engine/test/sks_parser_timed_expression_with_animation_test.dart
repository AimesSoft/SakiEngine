import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

void main() {
  test('timed expression keeps animation tokens between bracket and dialogue',
      () {
    const script =
        'aru2 [smile,0.3,shy] an jump "你看！呜啊——你怎么离鸦露露这么近。"';

    final root = SksParser().parse(script);
    expect(root.children.length, 1);
    final node = root.children.first as SayNode;

    expect(node.character, 'aru2');
    expect(node.startExpression, 'smile');
    expect(node.switchDelay, 0.3);
    expect(node.endExpression, 'shy');
    expect(node.animation, 'jump');
    expect(node.hasTimedExpression, isTrue);
  });
}
