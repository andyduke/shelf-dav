import 'dart:io' as io;
import 'dart:convert';
import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_dav/shelf_dav.dart';

/// Example of running embedded in a broader application.
Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.message}');
  });

  final fs = const LocalFileSystem();
  final root = fs.directory('webdav_data');

  if (!await root.exists()) {
    await root.create(recursive: true);
    print('Created data directory: ${root.path}');
  }

  final config = DAVConfig(
    root: root,
    prefix: '/files',
    allowAnonymous: true,
    propertyStorageType: PropertyStorageType.file,
    enableThrottling: true,
  );

  final dav = ShelfDAV.withConfig(config);
  final app = Router();

  // API endpoints
  app.get('/', _handleRoot);
  app.get('/api/health', _handleHealth);
  app.get('/api/stats', _handleStats);
  app.post('/api/upload', _handleUpload);
  app.mount('/files', dav.handler);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(app.call);

  final server = await shelf_io.serve(
    handler,
    '0.0.0.0',
    8080,
  );

  print('');
  print('Server running at http://${server.address.host}:${server.port}');
  print('');
  print('Available endpoints:');
  print('  - GET  /                  - Welcome page');
  print('  - GET  /api/health        - Health check');
  print('  - GET  /api/stats         - Server statistics');
  print('  - POST /api/upload        - Upload files via POST');
  print('  - *    /files/*           - WebDAV interface');
  print('');
  print('WebDAV clients should connect to:');
  print('  http://localhost:8080/files');
  print('');
  print('Press Ctrl+C to stop');

  io.ProcessSignal.sigint.watch().listen((_) async {
    print('Shutting down...');
    await dav.close();
    await server.close();
    io.exit(0);
  });
}

/// Handle root endpoint
Response _handleRoot(Request request) => Response.ok(
      '''
<!DOCTYPE html>
<html>
<head>
  <title>WebDAV Server</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
    code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
    pre { background: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>WebDAV Server</h1>
  <p>This server provides both a WebDAV interface and a REST API.</p>

  <h2>WebDAV Access</h2>
  <p>Connect your WebDAV client to:</p>
  <pre>http://localhost:8080/files</pre>

  <h2>API Endpoints</h2>
  <ul>
    <li><code>GET /api/health</code> - Health check</li>
    <li><code>GET /api/stats</code> - Server statistics</li>
    <li><code>POST /api/upload</code> - Upload files</li>
  </ul>
</body>
</html>
''',
      headers: {'Content-Type': 'text/html'},
    );

/// Health check endpoint
Response _handleHealth(Request request) {
  final health = {
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
    'uptime': DateTime.now().millisecondsSinceEpoch,
  };

  return Response.ok(
    jsonEncode(health),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Statistics endpoint
Response _handleStats(Request request) {
  // In a real application, you would track actual statistics
  final stats = {
    'requests': {
      'total': 0,
      'successful': 0,
      'failed': 0,
    },
    'webdav': {
      'enabled': true,
      'prefix': '/files',
    },
  };

  return Response.ok(
    jsonEncode(stats),
    headers: {'Content-Type': 'application/json'},
  );
}

/// File upload endpoint (alternative to WebDAV PUT)
Future<Response> _handleUpload(Request request) async {
  final contentType = request.headers['content-type'];

  if (contentType == null || !contentType.contains('multipart/form-data')) {
    return Response.badRequest(
      body: jsonEncode({'error': 'Content-Type must be multipart/form-data'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // In a real implementation, you would:
  // 1. Parse the multipart form data
  // 2. Save files to the filesystem
  // 3. Return upload results

  return Response.ok(
    jsonEncode({
      'status': 'success',
      'message': 'File uploaded successfully',
      'uploaded': 1,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

/// CORS middleware for API endpoints
Middleware _corsMiddleware() => (handler) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };

final _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};
