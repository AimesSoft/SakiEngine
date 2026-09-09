import 'sakiengine.dart';

Future<void> main(List<String> args) async {
  String? packagePath;
  if (args.isNotEmpty) {
    if (args.length != 2 || args.first != '--package') {
      throw ArgumentError('Usage: SakiEngine [--package <game.yuyu>]');
    }
    packagePath = args[1];
  }
  await runSakiEngine(yuyuPackagePath: packagePath);
}
