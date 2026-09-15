import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';
import 'package:sakiengine/src/utils/game_file_logger.dart';

import 'support/settings_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory downloads;
  late GameFileLogger logger;

  setUp(() async {
    DebugLogger.instance.clear();
    downloads = await Directory.systemTemp.createTemp('saki-file-logger-test-');
    logger = GameFileLogger.forTesting(
      downloadsDirectory: downloads,
      projectName: 'SoraNoUta',
    );
  });
  tearDown(() async {
    await logger.disposeForTesting();
    await downloads.delete(recursive: true);
  });

  test(
    'records history, immediate console lines, and errors without duplicates',
    () async {
      DebugLogger.instance.addLog('before enabling');
      await logger.initialize();
      expect(logger.isEnabled, isFalse);
      expect(downloads.listSync(), isEmpty);
      await logger.setEnabled(true);
      final file = File(logger.currentLogFilePath!);
      expect(
        file.path,
        startsWith('${downloads.path}${Platform.pathSeparator}SoraNoUta-log-'),
      );
      logger.recordConsoleLine('immediate console entry');
      expect(file.readAsStringSync(), contains('immediate console entry'));
      DebugLogger.instance.addLog('immediate console entry');
      DebugLogger.instance.addLog('direct debug entry');
      expect(file.readAsStringSync(), contains('direct debug entry'));
      logger.recordUncaughtError(
        StateError('failure'),
        StackTrace.fromString('frame one\nframe two'),
        source: 'test',
      );
      final bytes = file.readAsBytesSync();
      expect(bytes.take(3), orderedEquals(utf8.encode('\ufeff')));
      final content = utf8.decode(bytes);
      expect(content, contains('SoraNoUta live game log'));
      expect(content, contains('before enabling'));
      expect('immediate console entry'.allMatches(content), hasLength(1));
      expect(content, contains('direct debug entry'));
      expect(content, contains('[UNCAUGHT][test]'));
      expect(content, contains('frame one\r\n'));
    },
  );

  test(
    'stopping closes the file and restarting creates a separate session',
    () async {
      await logger.setEnabled(true);
      final first = File(logger.currentLogFilePath!);
      await logger.setEnabled(false);
      final stoppedContent = first.readAsStringSync();
      logger.recordConsoleLine('must not be written');
      DebugLogger.instance.addLog('while disabled');
      expect(logger.isWriting, isFalse);
      expect(logger.currentLogFilePath, isNull);
      expect(first.readAsStringSync(), stoppedContent);
      await logger.setEnabled(true);
      expect(logger.currentLogFilePath, isNot(first.path));
      expect(first.readAsStringSync(), stoppedContent);
    },
  );

  test(
    'concurrent toggle requests finish disabled without leaking a writer',
    () async {
      final resolver = Completer<Directory?>();
      final pendingLogger = GameFileLogger.forTesting(
        downloadsDirectory: downloads,
        downloadsDirectoryResolver: () => resolver.future,
      );
      addTearDown(pendingLogger.disposeForTesting);
      final enabling = pendingLogger.setEnabled(true);
      final disabling = pendingLogger.setEnabled(false);
      resolver.complete(downloads);
      await Future.wait([enabling, disabling]);
      expect(pendingLogger.isEnabled, isFalse);
      expect(pendingLogger.isWriting, isFalse);
      expect(downloads.listSync(), hasLength(1));
    },
  );

  test('unavailable Downloads reports an error and allows retry', () async {
    var unavailable = true;
    final retryLogger = GameFileLogger.forTesting(
      downloadsDirectory: downloads,
      downloadsDirectoryResolver: () async => unavailable ? null : downloads,
    );
    addTearDown(retryLogger.disposeForTesting);
    await retryLogger.setEnabled(true);
    expect(retryLogger.isWriting, isFalse);
    expect(retryLogger.currentLogFilePath, isNull);
    expect(retryLogger.lastStartError, isA<FileSystemException>());
    unavailable = false;
    await retryLogger.setEnabled(true);
    expect(retryLogger.isWriting, isTrue);
    expect(retryLogger.lastStartError, isNull);
  });

  test('unsupported platforms do not create files', () async {
    final unsupported = GameFileLogger.forTesting(
      downloadsDirectory: downloads,
      isSupported: false,
    );
    addTearDown(unsupported.disposeForTesting);
    await unsupported.setEnabled(true);
    expect(unsupported.isWriting, isFalse);
    expect(downloads.listSync(), isEmpty);
  });

  test('error hooks record failures and preserve previous handlers', () async {
    await logger.setEnabled(true);
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });
    var flutterCalls = 0;
    var platformCalls = 0;
    FlutterError.onError = (_) => flutterCalls++;
    PlatformDispatcher.instance.onError = (_, _) {
      platformCalls++;
      return true;
    };
    logger.installGlobalErrorHandlers();
    logger.installGlobalErrorHandlers();
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('framework failure')),
    );
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('async failure'),
        StackTrace.current,
      ),
      isTrue,
    );
    expect(flutterCalls, 1);
    expect(platformCalls, 1);
    final content = File(logger.currentLogFilePath!).readAsStringSync();
    expect(content, contains('[UNCAUGHT][FlutterError]'));
    expect(content, contains('[UNCAUGHT][PlatformDispatcher]'));
  });

  test(
    'migrates a legacy preference once and restores the new preference',
    () async {
      await initializeSettingsTestEnvironment();
      const legacy = 'example.developer.fileLogging';
      final data = UnifiedGameDataManager();
      await data.setBoolVariable(legacy, true, 'Saki-Logger-Test');
      GameFileLogger createPersistentLogger() => GameFileLogger.forTesting(
        downloadsDirectory: downloads,
        persistPreference: true,
      );
      final migrated = createPersistentLogger();
      addTearDown(migrated.disposeForTesting);
      await migrated.initialize(legacyPreferenceKeys: [legacy]);
      expect(migrated.isWriting, isTrue);
      expect(migrated.currentLogFilePath, contains('Saki-Logger-Test-log-'));
      await migrated.setEnabled(false);
      final restored = createPersistentLogger();
      addTearDown(restored.disposeForTesting);
      await restored.initialize(legacyPreferenceKeys: [legacy]);
      expect(restored.isEnabled, isFalse);
      expect(restored.isWriting, isFalse);
      await restored.setEnabled(true);
      await restored.disposeForTesting();
      final enabledAgain = createPersistentLogger();
      addTearDown(enabledAgain.disposeForTesting);
      await enabledAgain.initialize();
      expect(enabledAgain.isWriting, isTrue);
    },
  );
}
