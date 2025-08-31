abstract class SksNode {}

class ScriptNode implements SksNode {
  final List<SksNode> children;
  ScriptNode(this.children);
}

class ShowNode implements SksNode {
  final String character;
  final String? pose;
  final String? expression;
  final String? position;
  final String? animation; // 新增：动画名称
  ShowNode(this.character, {this.pose, this.expression, this.position, this.animation});
}

class HideNode implements SksNode {
  final String character;
  HideNode(this.character);
}

class BackgroundNode implements SksNode {
  final String background;
  final double? timer;
  final List<String>? layers; // 新增：多图层支持
  final String? transitionType; // 新增：转场类型支持 (with语法)
  BackgroundNode(this.background, {this.timer, this.layers, this.transitionType});
}

class SayNode implements SksNode {
  final String? character;
  final String dialogue;
  final String? pose;
  final String? expression;
  final String? animation; // 新增：动画名称
  SayNode({this.character, required this.dialogue, this.pose, this.expression, this.animation});
}

class ChoiceOptionNode {
  final String text;
  final String targetLabel;
  ChoiceOptionNode(this.text, this.targetLabel);
}

class MenuNode implements SksNode {
  final List<ChoiceOptionNode> choices;
  MenuNode(this.choices);
}

class LabelNode implements SksNode {
  final String name;
  LabelNode(this.name);
}

class ReturnNode implements SksNode {} 

class JumpNode implements SksNode {
  final String targetLabel;
  JumpNode(this.targetLabel);
} 

class CommentNode implements SksNode {
  final String comment;
  CommentNode(this.comment);
  
  @override
  String toString() => '// $comment';
}

class NvlNode implements SksNode {}

class EndNvlNode implements SksNode {}

class NvlMovieNode implements SksNode {}

class EndNvlMovieNode implements SksNode {}

class FxNode implements SksNode {
  final String filterString;
  FxNode(this.filterString);
}

class PlayMusicNode implements SksNode {
  final String musicFile;
  PlayMusicNode(this.musicFile);
}

class StopMusicNode implements SksNode {
  StopMusicNode();
}

class PlaySoundNode implements SksNode {
  final String soundFile;
  final bool loop;
  PlaySoundNode(this.soundFile, {this.loop = false});
}

class StopSoundNode implements SksNode {
  StopSoundNode();
}