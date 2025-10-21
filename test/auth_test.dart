/// Comprehensive test suite for WebDAV authentication and authorization.
///
/// This file consolidates all auth-related tests including:
/// - Basic authentication with plaintext credentials
/// - Anonymous access control
/// - Role-based authorization (read-only, read-write users)
/// - Path-based authorization
/// - Authentication middleware behavior
/// - Authorization provider implementations

library;

import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Prepare a test filesystem with sample files and directories
Future<Directory> prepareFilesystem(final FileSystem fs) async {
  final root = fs.directory('/test_root');
  await root.create(recursive: true);

  // Create sample files
  await fs.file('${root.path}/index.html').writeAsString('<html>Test</html>');
  await fs.file('${root.path}/file.txt').writeAsString('content');

  // Create directory with files
  await fs.directory('${root.path}/dir').create();
  await fs.file('${root.path}/dir/foo.txt').writeAsString('foo');
  await fs.directory('${root.path}/dir/bar').create();
  await fs.file('${root.path}/dir/bar/baz.txt').writeAsString('baz');

  return root;
}

void main() {
  group('Authentication Tests', () {
    late MemoryFileSystem fs;
    late DAVConfig config;

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory('/webdav').createSync(recursive: true);
    });

    test('allowAnonymous=false without authProvider returns 401', () async {
      // Regression test for issue where null middleware let requests through
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false, // No anonymous access
        // No authProvider specified
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final request = shelf.Request(
        'GET',
        Uri.parse('http://localhost/dav/'),
      );

      final response = await dav.handler(request);

      // Should return 401 Unauthorized, not let the request through
      expect(response.statusCode, equals(401));
      expect(
        response.headers['www-authenticate'],
        contains('Basic realm='),
      );
    });

    test('allowAnonymous=true without authProvider allows access', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: true, // Anonymous access allowed
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final request = shelf.Request(
        'GET',
        Uri.parse('http://localhost/dav/'),
      );

      final response = await dav.handler(request);

      // Should allow access (not 401)
      expect(response.statusCode, isNot(equals(401)));
    });

    test('Basic auth with valid credentials succeeds', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test WebDAV',
          users: {'alice': 'secret123'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final credentials = base64.encode(utf8.encode('alice:secret123'));
      final request = shelf.Request(
        'GET',
        Uri.parse('http://localhost/dav/'),
        headers: {'authorization': 'Basic $credentials'},
      );

      final response = await dav.handler(request);

      // Should allow access with valid credentials
      expect(response.statusCode, isNot(equals(401)));
    });

    test('Basic auth with invalid credentials returns 401', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test WebDAV',
          users: {'alice': 'secret123'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final credentials = base64.encode(utf8.encode('alice:wrongpassword'));
      final request = shelf.Request(
        'GET',
        Uri.parse('http://localhost/dav/'),
        headers: {'authorization': 'Basic $credentials'},
      );

      final response = await dav.handler(request);

      expect(response.statusCode, equals(401));
    });

    test('Basic auth with missing header returns 401', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test WebDAV',
          users: {'alice': 'secret123'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final request = shelf.Request(
        'GET',
        Uri.parse('http://localhost/dav/'),
        // No authorization header
      );

      final response = await dav.handler(request);

      expect(response.statusCode, equals(401));
      expect(
        response.headers['www-authenticate'],
        equals('Basic realm="Test WebDAV"'),
      );
    });
  });

  group('Authorization Tests', () {
    test('Role-based authz allows read-write user to write', () async {
      final fs = MemoryFileSystem();
      fs.directory('/webdav').createSync(recursive: true);

      final config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test WebDAV',
          users: {'alice': 'secret123'},
        ),
        authorizationProvider: const RoleBasedAuthorizationProvider(
          readWriteUsers: {'alice'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final credentials = base64.encode(utf8.encode('alice:secret123'));
      final request = shelf.Request(
        'PUT',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'authorization': 'Basic $credentials'},
        body: 'test content',
      );

      final response = await dav.handler(request);

      // Should allow write operation
      expect(response.statusCode, isNot(equals(403)));
    });

    test('Role-based authz denies read-only user from writing', () async {
      final fs = MemoryFileSystem();
      fs.directory('/webdav').createSync(recursive: true);

      final config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test WebDAV',
          users: {'bob': 'password456'},
        ),
        authorizationProvider: const RoleBasedAuthorizationProvider(
          readOnlyUsers: {'bob'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final credentials = base64.encode(utf8.encode('bob:password456'));
      final request = shelf.Request(
        'PUT',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'authorization': 'Basic $credentials'},
        body: 'test content',
      );

      final response = await dav.handler(request);

      // Should deny write operation
      expect(response.statusCode, equals(403));
    });
  });

  group('Authentication with HTTP Server', () {
    test('BasicAuth - valid credentials', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          users: {'alice': 'secret123'},
        ),
        authorizationProvider: const AllowAllAuthorizationProvider(),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final auth = base64.encode(utf8.encode('alice:secret123'));
        final response = await http.get(
          Uri.parse('$url/dav/index.html'),
          headers: {'Authorization': 'Basic $auth'},
        );

        expect(response.statusCode, 200);
      } finally {
        await server.close();
      }
    });

    test('BasicAuth - invalid credentials', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          users: {'alice': 'secret123'},
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final auth = base64.encode(utf8.encode('alice:wrong'));
        final response = await http.get(
          Uri.parse('$url/dav/index.html'),
          headers: {'Authorization': 'Basic $auth'},
        );

        expect(response.statusCode, 401);
        expect(response.headers['www-authenticate'], contains('Basic'));
      } finally {
        await server.close();
      }
    });

    test('Anonymous access allowed', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        allowAnonymous: true,
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        // No auth header
        final response = await http.get(Uri.parse('$url/dav/index.html'));
        expect(response.statusCode, 200);
      } finally {
        await server.close();
      }
    });
  });

  group('Authorization with HTTP Server', () {
    test('Role-based - read-only user cannot write', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          users: {'bob': 'password'},
        ),
        authorizationProvider: const RoleBasedAuthorizationProvider(
          readOnlyUsers: {'bob'},
          allowAnonymousRead: false,
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final auth = base64.encode(utf8.encode('bob:password'));

        // Read should work
        final get = await http.get(
          Uri.parse('$url/dav/index.html'),
          headers: {'Authorization': 'Basic $auth'},
        );
        expect(get.statusCode, 200);

        // Write should fail
        final put = await http.put(
          Uri.parse('$url/dav/test.txt'),
          headers: {'Authorization': 'Basic $auth'},
          body: 'test',
        );
        expect(put.statusCode, 403); // Forbidden
      } finally {
        await server.close();
      }
    });

    test('Path-based - user can only access allowed paths', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      // Create additional directory
      await fs.directory('${root.path}/private').create();
      await fs.file('${root.path}/private/secret.txt').writeAsString('secret');

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          users: {'alice': 'secret', 'bob': 'password'},
        ),
        authorizationProvider: PathBasedAuthorizationProvider(
          pathPermissions: {
            '/': {'alice'}, // Only alice can access root
            '/dir': {'alice', 'bob'}, // Both can access /dir
          },
          allowAnonymousRead: false,
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final bobAuth = base64.encode(utf8.encode('bob:password'));

        // Bob can access /dir
        final allowed = await http.get(
          Uri.parse('$url/dav/dir/foo.txt'),
          headers: {'Authorization': 'Basic $bobAuth'},
        );
        expect(allowed.statusCode, 200);

        // Bob cannot access root
        final denied = await http.get(
          Uri.parse('$url/dav/index.html'),
          headers: {'Authorization': 'Basic $bobAuth'},
        );
        expect(denied.statusCode, 403);
      } finally {
        await server.close();
      }
    });
  });
}
