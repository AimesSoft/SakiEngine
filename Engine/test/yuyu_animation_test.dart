import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';
import 'package:sakiengine/src/utils/scene_animation_controller.dart';

const mapped = '''
shake
profile yuyuball-sequence-v1
xcenter+0
hold 0.6
ease 0.2 xcenter-0.00390625
ease 0.2 xcenter+0.00390625
ease 0.2 xcenter-0.00390625
ease 0.2 xcenter+0.00390625
ease 0.1 xcenter+0
''';

void main() {
  tearDown(AnimationManager.clearCache);
  test('exact source samples, hold and noncumulative targets', () {
    final definition = AnimationConfigParser().parse(mapped)['shake']!;
    final sequence = YuyuSequence(definition, {'xcenter': .5, 'scale': 1});
    expect(sequence.duration, closeTo(1.5, 1e-12));
    expect(sequence.sample(.5)['xcenter'], .5);
    expect(
      (sequence.sample(.65)['xcenter']! - .5) * 1280,
      closeTo(-.732233047, 1e-8),
    );
    expect((sequence.sample(.7)['xcenter']! - .5) * 1280, closeTo(-2.5, 1e-10));
    expect((sequence.sample(.8)['xcenter']! - .5) * 1280, closeTo(-5, 1e-10));
    expect((sequence.sample(1)['xcenter']! - .5) * 1280, closeTo(5, 1e-10));
    expect(sequence.sample(1.5)['xcenter'], .5);
    expect(sequence.sample(1.5)['scale'], 1);
    expect(YuyuSequence.warp('easein', .25), closeTo(.382683432365, 1e-10));
    expect(YuyuSequence.warp('easeout', .25), closeTo(.076120467489, 1e-10));
  });

  test('native definitions keep native profile and finite final values', () {
    AnimationManager.loadAnimationsFromStringForTesting('''
native
ease 0.2 xcenter+0.1
''');
    expect(AnimationManager.getAnimation('native')!.profile, 'saki');
    expect(
      AnimationManager.resolveFinalProperties('native', {
        'xcenter': .5,
      })!['xcenter'],
      .6,
    );
  });

  testWidgets(
    'character and scene share continuous loop phase and cancel cleanly',
    (tester) async {
      AnimationManager.loadAnimationsFromStringForTesting('''
loop
profile yuyuball-sequence-v1
xcenter+0
linear 0.1 xcenter+0.1
linear 0.1 xcenter+0
''');
      final character = CharacterAnimationController(characterId: 'c');
      final scene = SceneAnimationController(sceneId: 's');
      final characterDone = character.playAnimation('loop', const TestVSync(), {
        'xcenter': .5,
      }, repeatCount: 0);
      final sceneDone = scene.playAnimation('loop', const TestVSync(), {
        'xcenter': .5,
      }, repeatCount: 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(character.currentProperties['xcenter'], closeTo(.525, 1e-9));
      expect(scene.currentProperties['xcenter'], closeTo(.525, 1e-9));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(character.currentProperties['xcenter'], closeTo(.525, 1e-9));
      expect(scene.currentProperties['xcenter'], closeTo(.525, 1e-9));
      character.dispose();
      scene.dispose();
      await characterDone;
      await sceneDone;
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  test('unknown profiles and nonadvancing infinite loops fail explicitly', () {
    expect(
      () => AnimationConfigParser().parse('a\nprofile unknown\n'),
      throwsFormatException,
    );
    final definition = AnimationDefinition(name: 'empty', keyframes: []);
    final playback = YuyuSequencePlayback(
      definition: definition,
      base: {},
      onUpdate: (_) {},
    );
    expect(
      () => playback.play(const TestVSync(), repeatCount: 0),
      throwsArgumentError,
    );
    playback.dispose();
  });
}
