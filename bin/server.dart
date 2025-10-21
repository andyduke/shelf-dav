import 'dart:io';
import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

Future<void> main(List<String> args) async {
  // Configure logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.message}');
  });

  // Parse configuration from environment variables
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final dataDir = Platform.environment['DATA_DIR'] ?? '/data';
  final prefix = Platform.environment['DAV_PREFIX'] ?? '/dav';

  // Authentication configuration
  final allowAnonymous = Platform.environment['ALLOW_ANONYMOUS'] != 'false';
  final username = Platform.environment['DAV_USERNAME'];
  final password = Platform.environment['DAV_PASSWORD'];

  // Throttling configuration
  final maxConcurrent =
      int.tryParse(Platform.environment['MAX_CONCURRENT'] ?? '100') ?? 100;
  final maxReqPerSec =
      int.tryParse(Platform.environment['MAX_REQ_PER_SEC'] ?? '10') ?? 10;

  // Initialize filesystem
  final fs = const LocalFileSystem();
  final root = fs.directory(dataDir);

  // Create data directory if it doesn't exist
  if (!await root.exists()) {
    await root.create(recursive: true);
    print('Created data directory: ${root.path}');
  }

  // Configure WebDAV server
  AuthenticationProvider? authProvider;
  AuthorizationProvider? authzProvider;

  if (username != null && password != null) {
    print('Using Basic Authentication (user: $username)');
    authProvider = BasicAuthenticationProvider.plaintext(
      realm: 'WebDAV Server',
      users: {username: password},
    );
    authzProvider = RoleBasedAuthorizationProvider(
      readWriteUsers: {username},
      readOnlyUsers: {},
      allowAnonymousRead: allowAnonymous,
    );
  } else if (!allowAnonymous) {
    print(
      'ERROR: ALLOW_ANONYMOUS=false requires DAV_USERNAME and DAV_PASSWORD',
    );
    exit(1);
  } else {
    print('Running in anonymous mode (no authentication)');
  }

  final config = DAVConfig(
    root: root,
    prefix: prefix,
    allowAnonymous: allowAnonymous,
    authenticationProvider: authProvider,
    authorizationProvider: authzProvider,
    propertyStorageType: PropertyStorageType.file,
    enableThrottling: true,
    throttleConfig: ThrottleConfig(
      maxConcurrentRequests: maxConcurrent,
      maxRequestsPerSecond: maxReqPerSec,
    ),
  );

  final dav = ShelfDAV.withConfig(config);

  // Add logging middleware
  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(dav.handler);

  // Start server
  final server = await shelf_io.serve(
    handler,
    host,
    port,
  );

  print('');
  print(
    'WebDAV server running at http://${server.address.host}:${server.port}$prefix',
  );
  print('Data directory: ${root.path}');
  print('Max concurrent requests: $maxConcurrent');
  print('Max requests per second: $maxReqPerSec');
  print('');
  print('Press Ctrl+C to stop');
}
