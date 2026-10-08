import 'dart:collection';

import 'package:sakiengine/src/game/story_flowchart_manager.dart';

bool _inheritsUnlockStatus(StoryFlowNode node) =>
    node.metadata?.containsKey('branchText') == true ||
    node.type == StoryNodeType.merge;

/// Finds visible nodes without recursively following possibly cyclic parents.
List<StoryFlowNode> visibleStoryFlowchartNodes(
  Iterable<StoryFlowNode> nodes,
  String? chapterName,
) {
  if (chapterName == null) return [];

  final allNodes = nodes.toList();
  final dependents = <String, List<String>>{};
  final visibleIds = <String>{};
  final pending = Queue<String>();

  for (final node in allNodes) {
    if (!_inheritsUnlockStatus(node)) {
      if (node.isUnlocked && visibleIds.add(node.id)) pending.add(node.id);
      continue;
    }

    final parentIds = node.type == StoryNodeType.merge
        ? (node.metadata?['parentIds'] as List<dynamic>?)
        : null;
    final parents = parentIds != null && parentIds.isNotEmpty
        ? parentIds.cast<String>()
        : [if (node.parentNodeId != null) node.parentNodeId!];
    for (final parentId in parents) {
      (dependents[parentId] ??= []).add(node.id);
    }
  }

  // Only an unlocked chapter, branch choice or ending can seed visibility.
  // A cycle of options/merge points alone must not unlock itself.
  while (pending.isNotEmpty) {
    for (final id in dependents[pending.removeFirst()] ?? const <String>[]) {
      if (visibleIds.add(id)) pending.add(id);
    }
  }

  return allNodes
      .where(
        (node) =>
            node.chapterName == chapterName && visibleIds.contains(node.id),
      )
      .toList();
}

/// Lays out each reachable, visible node once, including cyclic story graphs.
Map<String, Map<String, double>> calculateStoryFlowchartLayout(
  List<StoryFlowNode> nodes,
  List<StoryFlowNode> rootNodes, {
  required double largeNodeHeight,
  required double smallNodeHeight,
}) {
  final nodesMap = {for (final node in nodes) node.id: node};
  final depthNodes = <int, List<StoryFlowNode>>{};
  final visited = <String>{};
  final pending = Queue<(StoryFlowNode, int)>();

  for (final root in rootNodes) {
    if (nodesMap.containsKey(root.id) && visited.add(root.id)) {
      pending.add((root, 0));
    }
  }

  // Breadth-first traversal gives shared nodes a stable shortest depth and
  // keeps both back edges and very long paths off the Dart call stack.
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeFirst();
    (depthNodes[depth] ??= []).add(node);
    for (final childId in node.childNodeIds) {
      final child = nodesMap[childId];
      if (child != null && visited.add(childId)) {
        pending.add((child, depth + 1));
      }
    }
  }

  const canvasCenter = 20000.0;
  final verticalAdjustment = (largeNodeHeight - smallNodeHeight) / 2;
  final layout = <String, Map<String, double>>{};
  for (final entry in depthNodes.entries) {
    final startY = canvasCenter - (entry.value.length - 1) * 200.0 / 2;
    for (var i = 0; i < entry.value.length; i++) {
      final node = entry.value[i];
      layout[node.id] = {
        'x': canvasCenter + 100 + entry.key * 400.0,
        'y':
            startY +
            i * 200.0 +
            (_inheritsUnlockStatus(node) ? verticalAdjustment : 0),
        'depth': entry.key.toDouble(),
      };
    }
  }
  return layout;
}
