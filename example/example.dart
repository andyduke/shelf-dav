import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

/// A standalone WebDAV server example
Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.message}');
  });

  final fs = const LocalFileSystem();
  final root = fs.directory('webdav_root');

  if (!await root.exists()) {
    await root.create(recursive: true);
    print('Created data directory: ${root.path}');
  }

  // Use DBM for persistent property and lock storage
  // Store database OUTSIDE the WebDAV-exposed directory for security
  // Share a single database file for both properties and locks (with different prefixes)
  final storage = DbmPropertyStorage('webdav_storage.db');
  final lockStorage = DbmLockStorage.fromDb(
    storage.db,
    tokenPrefix: 'lock:token:',
    pathPrefix: 'lock:path:',
  );

  final dav = ShelfDAV.withConfig(
    DAVConfig(
      root: root,
      prefix: '/dav',
      allowAnonymous: true,
      enableLocking: true,
      propertyStorageType: PropertyStorageType.custom,
      customPropertyStorage: storage,
      lockStorage: lockStorage,
    ),
  );

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(dav.handler);

  final server = await shelf_io.serve(
    handler,
    '0.0.0.0',
    8080,
  );

  print('');
  print(
    'WebDAV server running at http://${server.address.host}:${server.port}/dav',
  );
  print('Data directory: ${root.path}');
  print('');
  print('Try accessing it with a WebDAV client:');
  print('  - macOS Finder: Go > Connect to Server > http://localhost:8080/dav');
  print('  - Windows Explorer: Map Network Drive > http://localhost:8080/dav');
  print('  - Linux: nautilus dav://localhost:8080/dav');
  print('');
  print('Press Ctrl+C to stop');

  io.ProcessSignal.sigint.watch().listen((_) async {
    print('Shutting down...');
    await dav.close();
    await server.close();
    io.exit(0);
  });
}
