import 'dart:convert';
import 'dart:io';
import 'package:sakiengine/src/compat/yuyu/yuyu_package.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_validator.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/yuyu_validate.dart <game.yuyu>');
    exitCode = 2;
    return;
  }
  YuyuPackage? package;
  try {
    package = await YuyuPackage.open(args.single, forValidation: true);
    stdout.writeln(jsonEncode(await validateYuyuPackage(package)));
  } catch (error) {
    stderr.writeln('YuYuball validation failed: $error');
    exitCode = 2;
  } finally {
    await package?.close();
  }
}
