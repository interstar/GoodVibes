import 'dart:io';

import 'package:path/path.dart' as p;

/// Serves the apps directory over HTTP on `127.0.0.1` so that apps can use
/// `fetch`, modules, and relative assets without `file://` restrictions.
class LocalServer {
  HttpServer? _server;

  int? get port => _server?.port;

  /// Base URL of the server, e.g. `http://127.0.0.1:41231`.
  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  /// URL that opens a specific app in the embedded browser.
  String urlForApp(String appId) => '$baseUrl/$appId/index.html';

  /// URL for an asset inside an app (e.g. its icon).
  String urlForAsset(String appId, String relativePath) =>
      '$baseUrl/$appId/${relativePath.replaceAll('\\', '/')}';

  Future<void> start(String docRoot) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => _handle(request, docRoot));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request, String docRoot) async {
    try {
      final path = request.uri.path;
      final safePath = _resolve(docRoot, path);
      final file = File(safePath);
      if (await file.exists()) {
        request.response.headers.contentType = _mimeType(safePath);
        await request.response.addStream(file.openRead());
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$e');
    } finally {
      await request.response.close();
    }
  }

  /// Map a request path to a real file under [docRoot], rejecting traversal.
  static String _resolve(String docRoot, String path) {
    final relative = path.replaceAll(RegExp(r'/+'), '/').replaceFirst('/', '');
    final normalized = p.normalize(relative);
    if (normalized == '.' || normalized == '..') {
      return p.join(docRoot, 'index.html');
    }
    if (normalized.startsWith('..')) {
      return p.join(docRoot, 'index.html');
    }
    final full = p.join(docRoot, normalized);
    if (!p.isWithin(docRoot, full)) {
      return p.join(docRoot, 'index.html');
    }
    return full;
  }

  static ContentType _mimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.html':
      case '.htm':
        return ContentType.html;
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.js':
      case '.mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType.json;
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.webp':
        return ContentType('image', 'webp');
      case '.ico':
        return ContentType('image', 'x-icon');
      case '.txt':
        return ContentType('text', 'plain', charset: 'utf-8');
      case '.woff':
        return ContentType('font', 'woff');
      case '.woff2':
        return ContentType('font', 'woff2');
      case '.ttf':
        return ContentType('font', 'ttf');
      default:
        return ContentType('application', 'octet-stream');
    }
  }
}
