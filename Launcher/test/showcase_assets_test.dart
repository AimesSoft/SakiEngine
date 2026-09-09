import 'dart:io';

import '../lib/showcase_assets.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main(List<String> arguments) {
  const source = '''name: example
flutter:
  shaders:
    - assets/shaders/dissolve.frag
  assets:
    - default_game.txt
    - Assets/
    - Assets/fonts/
    - 'Assets/music/' # music
    - Assets/shaders/
    - GameScript/
    - GameScript_ja/
    - .saki_cache/game.sakipak
  fonts:
    - family: Example
      fonts:
        - asset: Assets/fonts/example.ttf
''';
  final result = prepareShowcasePubspec(source);
  check(!result.contains('    - Assets/\n'), 'Root assets duplicated');
  check(!result.contains('music/'), 'Music duplicated');
  check(!result.contains('    - Assets/fonts/'), 'Unused fonts bundled');
  check(!result.contains('GameScript'), 'Scripts duplicated');
  check(!result.contains('.sakipak'), 'Old release pack bundled');
  check(result.contains('    - default_game.txt'), 'Bootstrap asset removed');
  check(result.contains('    - Assets/shaders/'), 'Shader assets removed');
  check(
    result.contains(source.substring(source.indexOf('  fonts:'))),
    'Font declarations modified',
  );
  check(
    result.contains('  shaders:\n    - assets/shaders/dissolve.frag'),
    'Compiled shaders removed',
  );
  check(
    prepareShowcasePubspec(source.replaceAll('\n', '\r\n')) ==
        result.replaceAll('\n', '\r\n'),
    'Line endings changed',
  );
  check(
    prepareShowcasePubspec('flutter:\n  assets:\n    - Assets/\n') ==
        'flutter:\n  assets: []\n',
    'Empty assets list is invalid',
  );

  print('Showcase asset fixture checks passed.');
  if (arguments.isEmpty) return;
  final gamePubspec = File(arguments.single).readAsStringSync();
  final gameResult = prepareShowcasePubspec(gamePubspec);
  check(!gameResult.contains('    - Assets/music/'), 'Game music duplicated');
  check(!gameResult.contains('    - GameScript'), 'Game scripts duplicated');
  check(!gameResult.contains('.sakipak'), 'Game release pack duplicated');
  check(
    gameResult.substring(gameResult.indexOf('  fonts:')) ==
        gamePubspec.substring(gamePubspec.indexOf('  fonts:')),
    'Game font/icon configuration modified',
  );
  print('Showcase asset checks passed for ${arguments.single}.');
}
