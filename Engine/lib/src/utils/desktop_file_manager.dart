import 'dart:io';

import 'package:flutter/foundation.dart';

/// Opens an existing directory without involving a command shell.
Future<void> openDirectoryInFileManager(
  String directoryPath, {
  @visibleForTesting String? operatingSystem,
  @visibleForTesting
  Future<void> Function(String executable, List<String> arguments)? launch,
}) async {
  if (kIsWeb) {
    throw UnsupportedError('浏览器不支持打开本地文件夹');
  }
  final directory = Directory(directoryPath).absolute;
  if (!await directory.exists()) {
    throw FileSystemException('文件夹不存在', directory.path);
  }

  final system = operatingSystem ?? Platform.operatingSystem;
  final start = launch ?? _launchFileManager;
  switch (system) {
    case 'macos':
      await start('open', [directory.path]);
    case 'windows':
      await start('explorer.exe', [directory.path]);
    case 'linux':
      try {
        await start('xdg-open', [directory.path]);
      } on ProcessException {
        await start('gio', ['open', directory.path]);
      }
    default:
      throw UnsupportedError('当前平台不支持打开文件夹');
  }
}

Future<void> _launchFileManager(
  String executable,
  List<String> arguments,
) async {
  if (Platform.isWindows) {
    // Explorer can reuse another process and return a nonzero exit code even
    // when opening succeeds. Only await process creation on Windows.
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return;
  }
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
}
