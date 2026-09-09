import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/utils/desktop_file_manager.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('saki 脚本 folder_');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  for (final entry in {
    'macos': 'open',
    'windows': 'explorer.exe',
    'linux': 'xdg-open',
  }.entries) {
    test(
      '${entry.key} passes the script folder as one literal argument',
      () async {
        final calls = <(String, List<String>)>[];
        await openDirectoryInFileManager(
          directory.path,
          operatingSystem: entry.key,
          launch: (executable, arguments) async =>
              calls.add((executable, arguments)),
        );
        expect(calls, hasLength(1));
        expect(calls.single.$1, entry.value);
        expect(calls.single.$2, [directory.absolute.path]);
      },
    );
  }

  test('Linux falls back to gio when xdg-open fails', () async {
    final calls = <String>[];
    await openDirectoryInFileManager(
      directory.path,
      operatingSystem: 'linux',
      launch: (executable, arguments) async {
        calls.add(executable);
        if (executable == 'xdg-open') {
          throw ProcessException(executable, arguments);
        }
        expect(arguments, ['open', directory.absolute.path]);
      },
    );
    expect(calls, ['xdg-open', 'gio']);
  });

  test('missing directories do not launch the file manager', () async {
    await expectLater(
      openDirectoryInFileManager(
        '${directory.path}/missing',
        launch: (_, _) async => fail('must not launch'),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('launch failures propagate for an editor notification', () async {
    await expectLater(
      openDirectoryInFileManager(
        directory.path,
        operatingSystem: 'macos',
        launch: (executable, arguments) async =>
            throw ProcessException(executable, arguments),
      ),
      throwsA(isA<ProcessException>()),
    );
  });
}
