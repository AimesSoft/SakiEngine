import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'yuyu_package.dart';

/// Session-scoped original Web UI and media URLs, including video Range reads.
class YuyuResourceServer {
  final YuyuPackage package;
  final HttpServer _server;
  final String _token;
  bool _closed = false;
  YuyuResourceServer._(this.package, this._server, this._token);

  static Future<YuyuResourceServer> start(YuyuPackage package) async {
    if (package.webEntry == null) {
      throw const FormatException('Package has no Web UI');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final result = YuyuResourceServer._(package, server, token);
    server.listen(result._serve);
    return result;
  }

  Uri get origin => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);
  Uri get entryUri => origin.replace(
    pathSegments: [_token, 'web', p.posix.basename(package.webEntry!)],
  );
  Uri gameAssetUri(String relative) {
    YuyuPackage.validatePath(relative);
    if (package.entryFile('game/$relative') == null) {
      throw FormatException('Missing game asset: $relative');
    }
    return origin.replace(
      pathSegments: [_token, 'game', ...relative.split('/')],
    );
  }

  bool permits(Uri uri) =>
      uri.origin == origin.origin && uri.pathSegments.firstOrNull == _token;

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Cache-Control', 'no-store');
      if (_closed || !const {'GET', 'HEAD'}.contains(request.method)) {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final parts = request.uri.pathSegments;
      if (parts.length < 3 ||
          parts[0] != _token ||
          !const {'web', 'game'}.contains(parts[1])) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final relative = YuyuPackage.validatePath(parts.skip(2).join('/'));
      final root = parts[1] == 'web'
          ? p.posix.dirname(package.webEntry!)
          : 'game';
      final file = package.entryFile('$root/$relative');
      if (file == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final size = await file.length();
      var start = 0, end = size - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null ||
            size == 0 ||
            (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          return;
        }
        if (match[1]!.isEmpty) {
          final count = int.tryParse(match[2]!);
          if (count == null || count <= 0) {
            response.statusCode = 416;
            return;
          }
          start = max(0, size - count);
        } else {
          start = int.tryParse(match[1]!) ?? size;
          end = match[2]!.isEmpty
              ? size - 1
              : min(size - 1, int.tryParse(match[2]!) ?? -1);
        }
        if (start >= size || end < start) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
      }
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _mime[p.extension(relative).toLowerCase()] ??
            'application/octet-stream',
      );
      response.contentLength = size == 0 ? 0 : end - start + 1;
      if (request.method != 'HEAD' && size > 0) {
        await response.addStream(file.openRead(start, end + 1));
      }
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }

  static const _mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.avif': 'image/avif',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
    '.mp3': 'audio/mpeg',
    '.ogg': 'audio/ogg',
    '.wav': 'audio/wav',
    '.m4a': 'audio/mp4',
  };
}
