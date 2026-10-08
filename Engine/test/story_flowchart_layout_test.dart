import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/story_flowchart_manager.dart';
import 'package:sakiengine/src/utils/story_flowchart_layout.dart';

StoryFlowNode node(
  String id, {
  StoryNodeType type = StoryNodeType.branch,
  List<String> children = const [],
  String? parent,
  List<String>? parents,
  bool option = false,
  bool unlocked = true,
  String chapter = 'chapter',
}) => StoryFlowNode(
  id: id,
  label: id,
  type: type,
  displayName: id,
  scriptIndex: 0,
  chapterName: chapter,
  childNodeIds: children,
  parentNodeId: parent,
  isUnlocked: unlocked,
  metadata: {
    if (option) 'branchText': id,
    if (parents != null) 'parentIds': parents,
  },
);

Map<String, Map<String, double>> layout(List<StoryFlowNode> nodes) =>
    calculateStoryFlowchartLayout(
      nodes,
      nodes.where((node) => node.type == StoryNodeType.chapter).toList(),
      largeNodeHeight: 76,
      smallNodeHeight: 38,
    );

void main() {
  test('a self-loop is laid out once and keeps the chapter at depth zero', () {
    final result = layout([
      node('root', type: StoryNodeType.chapter, children: ['root', 'root']),
    ]);
    expect(result, {
      'root': {'x': 20100.0, 'y': 20000.0, 'depth': 0.0},
    });
  });

  test('a retry loop retains the shared merge and the exit path', () {
    final nodes = [
      node('root', type: StoryNodeType.chapter, children: ['entry']),
      node('entry', children: ['enter']),
      node('enter', children: ['merge'], parent: 'entry', option: true),
      node(
        'merge',
        type: StoryNodeType.merge,
        children: ['choice'],
        parents: ['enter', 'retry'],
      ),
      node('choice', children: ['retry', 'exit'], parent: 'merge'),
      node('retry', children: ['merge'], parent: 'choice', option: true),
      node('exit', children: ['ending'], parent: 'choice', option: true),
      node('ending', type: StoryNodeType.ending, parent: 'exit'),
    ];
    final result = layout(nodes);
    expect(result.keys, containsAll(nodes.map((node) => node.id)));
    expect(result, hasLength(nodes.length));
    expect(result['merge']!['depth'], 3);
    expect(result['ending']!['depth'], 6);
    expect(result['retry']!['y'], isNot(result['exit']!['y']));
  });

  test(
    'converging branches do not duplicate or displace their shared node',
    () {
      final result = layout([
        node('root', type: StoryNodeType.chapter, children: ['left', 'right']),
        node('left', children: ['merge']),
        node('right', children: ['merge']),
        node('merge', type: StoryNodeType.merge, children: ['ending']),
        node('ending', type: StoryNodeType.ending),
      ]);
      expect(result, hasLength(5));
      expect(result['left']!['y'], 19900);
      expect(result['right']!['y'], 20100);
      expect(result['merge'], {'x': 20900.0, 'y': 20019.0, 'depth': 2.0});
      expect(result['ending']!['y'], 20000);
    },
  );

  test('multiple roots stay at depth zero even with links between them', () {
    final result = layout([
      node('first', type: StoryNodeType.chapter, children: ['second']),
      node('second', type: StoryNodeType.chapter, children: ['first']),
    ]);
    expect(result, hasLength(2));
    expect(result['first']!['depth'], 0);
    expect(result['second']!['depth'], 0);
    expect(result['first']!['y'], isNot(result['second']!['y']));
  });

  test('missing or filtered children are not added to the layout', () {
    final result = layout([
      node(
        'root',
        type: StoryNodeType.chapter,
        children: ['missing', 'visible'],
      ),
      node('visible'),
    ]);
    expect(result.keys, unorderedEquals(['root', 'visible']));
  });

  test('long child and ancestor chains do not consume the call stack', () {
    const count = 15000;
    final nodes = [
      node('0', type: StoryNodeType.chapter, children: ['1']),
      for (var i = 1; i < count; i++)
        node(
          '$i',
          children: [if (i + 1 < count) '${i + 1}'],
          parent: '${i - 1}',
          option: true,
          unlocked: false,
        ),
    ];
    final visible = visibleStoryFlowchartNodes(nodes, 'chapter');
    expect(visible, hasLength(count));
    final result = layout(visible);
    expect(result, hasLength(count));
    expect(result['${count - 1}']!['depth'], count - 1);
  });

  test('an unanchored option/merge cycle cannot unlock itself', () {
    final nodes = [
      node('option', parent: 'merge', option: true),
      node('merge', type: StoryNodeType.merge, parents: ['option']),
    ];
    expect(visibleStoryFlowchartNodes(nodes, 'chapter'), isEmpty);
    expect(visibleStoryFlowchartNodes(nodes, null), isEmpty);
  });

  test('a merge can inherit visibility from any parent despite a cycle', () {
    final nodes = [
      node(
        'cycle',
        type: StoryNodeType.merge,
        parents: ['merge'],
        unlocked: false,
      ),
      node(
        'merge',
        type: StoryNodeType.merge,
        parents: ['cycle', 'option'],
        unlocked: false,
      ),
      node('option', parent: 'branch', option: true, unlocked: false),
      node('branch'),
    ];
    expect(visibleStoryFlowchartNodes(nodes, 'chapter'), hasLength(4));
  });

  test('a locked choice blocks inheritance from its unlocked chapter', () {
    final nodes = [
      node('root', type: StoryNodeType.chapter),
      node('locked', parent: 'root', unlocked: false),
      node('option', parent: 'locked', option: true),
      node('merge', type: StoryNodeType.merge, parent: 'option', parents: []),
      node('orphan', parent: 'missing', option: true),
    ];
    expect(
      visibleStoryFlowchartNodes(nodes, 'chapter').map((node) => node.id),
      ['root'],
    );
  });

  test(
    'chapter filtering retains ancestor lookup across chapter boundaries',
    () {
      final nodes = [
        node('other', chapter: 'other'),
        node('option', parent: 'other', option: true, unlocked: false),
        node(
          'merge',
          type: StoryNodeType.merge,
          parent: 'option',
          unlocked: false,
        ),
      ];
      expect(
        visibleStoryFlowchartNodes(nodes, 'chapter').map((node) => node.id),
        ['option', 'merge'],
      );
    },
  );
}
