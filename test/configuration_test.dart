/// Comprehensive test suite for WebDAV configuration options.
///
/// This file consolidates all configuration-related tests including:
/// - Read-only mode (blocking write operations)
/// - Request throttling and rate limiting
/// - Concurrent request management
/// - Throttle configuration options
/// - Integration between auth and throttle middleware

library;

import 'dart:io' show HttpStatus;
import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
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
  group('Read-Only Mode Tests', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      // Create test file
      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content');

      // Create test directory
      final dir = fs.directory('/webdav_root/testdir');
      await dir.create();

      // Create ShelfDAV in read-only mode
      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        readOnly: true,
      );
      dav = ShelfDAV.withConfig(config);
    });

    tearDown(() async {
      await dav.close();
    });

    group('Read operations should succeed', () {
      test('GET file should succeed in read-only mode', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.ok));

        final content = await response.readAsString();
        expect(content, equals('Test content'));
      });

      test('HEAD file should succeed in read-only mode', () async {
        final request = Request(
          'HEAD',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.ok));
      });

      test('PROPFIND should succeed in read-only mode', () async {
        final request = Request(
          'PROPFIND',
          Uri.parse('http://localhost/dav/'),
          headers: {'Depth': '1'},
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.multiStatus));
      });

      test('OPTIONS should succeed in read-only mode', () async {
        final request = Request(
          'OPTIONS',
          Uri.parse('http://localhost/dav/'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.ok));
      });
    });

    group('Write operations should return 403 Forbidden', () {
      test('PUT should return 403 in read-only mode', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/newfile.txt'),
          body: 'new content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('PUT to existing file should return 403', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/test.txt'),
          body: 'updated content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('DELETE file should return 403 in read-only mode', () async {
        final request = Request(
          'DELETE',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('DELETE directory should return 403 in read-only mode', () async {
        final request = Request(
          'DELETE',
          Uri.parse('http://localhost/dav/testdir/'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('MKCOL should return 403 in read-only mode', () async {
        final request = Request(
          'MKCOL',
          Uri.parse('http://localhost/dav/newdir'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('COPY should return 403 in read-only mode', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Destination': 'http://localhost/dav/copy.txt'},
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('MOVE should return 403 in read-only mode', () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Destination': 'http://localhost/dav/moved.txt'},
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('PROPPATCH should return 403 in read-only mode', () async {
        final request = Request(
          'PROPPATCH',
          Uri.parse('http://localhost/dav/test.txt'),
          body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/">
  <D:set>
    <D:prop>
      <Z:author>Test</Z:author>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('LOCK should return 403 in read-only mode', () async {
        final request = Request(
          'LOCK',
          Uri.parse('http://localhost/dav/test.txt'),
          body: '''<?xml version="1.0"?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });
    });

    test('File system should remain unchanged in read-only mode', () async {
      // Try to PUT a new file
      final putRequest = Request(
        'PUT',
        Uri.parse('http://localhost/dav/should_not_exist.txt'),
        body: 'content',
      );
      await dav.handler(putRequest);

      // Verify file was not created
      final file = fs.file('/webdav_root/should_not_exist.txt');
      expect(await file.exists(), isFalse);
    });

    test('Existing files should not be modified in read-only mode', () async {
      // Try to update existing file
      final putRequest = Request(
        'PUT',
        Uri.parse('http://localhost/dav/test.txt'),
        body: 'modified content',
      );
      await dav.handler(putRequest);

      // Verify file content unchanged
      final file = fs.file('/webdav_root/test.txt');
      final content = await file.readAsString();
      expect(content, equals('Test content')); // Original content
    });
  });

  group('Throttle Tests', () {
    late MemoryFileSystem fs;
    late DAVConfig config;

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory('/webdav').createSync(recursive: true);
      fs.file('/webdav/test.txt').writeAsStringSync('test content');
    });

    test('Basic request succeeds', () async {
      final dav = ShelfDAV('/dav', fs.directory('/webdav'));
      addTearDown(() async => dav.close());
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );

      final response = await dav.handler(request);

      // Should succeed
      expect(response.statusCode, equals(200));
    });

    test('Multiple requests work correctly', () async {
      final dav = ShelfDAV('/dav', fs.directory('/webdav'));
      addTearDown(() async => dav.close());

      // Make multiple requests
      final responses = <Response>[];
      for (var i = 0; i < 3; i++) {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        responses.add(await dav.handler(request));
      }

      // All requests should succeed (within default limits)
      for (final response in responses) {
        expect(response.statusCode, equals(200));
      }
    });

    test('Throttling can be disabled', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        enableThrottling: false, // Disabled
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );

      final response = await dav.handler(request);

      // No rate limit headers when throttling is disabled
      expect(response.headers['x-ratelimit-limit'], isNull);
      expect(response.headers['x-ratelimit-remaining'], isNull);
      expect(response.headers['x-ratelimit-reset'], isNull);
    });

    test('Requests succeed with basic configuration', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        enableThrottling: true,
        throttleConfig: const ThrottleConfig(
          maxConcurrentRequests: 100,
          maxRequestsPerSecond: 100,
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());

      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);

      // Request should succeed
      expect(response.statusCode, equals(200));
    });
  });

  group('Combined Auth and Throttle Tests', () {
    late MemoryFileSystem fs;
    late DAVConfig config;

    setUp(() {
      fs = MemoryFileSystem();
      fs.directory('/webdav').createSync(recursive: true);
      fs.file('/webdav/test.txt').writeAsStringSync('test content');
    });

    test('Auth check happens before throttle', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        allowAnonymous: false,
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test',
          users: {'user': 'pass'},
        ),
        enableThrottling: true,
        throttleConfig: const ThrottleConfig(
          maxConcurrentRequests: 100,
          maxRequestsPerSecond: 10,
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());

      // Request without auth
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );

      final response = await dav.handler(request);

      // Should get 401 (auth failure) not 429 (throttle)
      expect(response.statusCode, equals(401));
      expect(response.headers['www-authenticate'], isNotNull);
    });

    test('Authenticated requests succeed', () async {
      config = DAVConfig(
        root: fs.directory('/webdav'),
        prefix: '/dav',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Test',
          users: {'user': 'pass'},
        ),
        enableThrottling: true,
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final credentials = 'Basic ${base64Encode(utf8.encode('user:pass'))}';

      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'authorization': credentials},
      );

      final response = await dav.handler(request);

      // Should succeed
      expect(response.statusCode, equals(200));
    });
  });

  group('Throttling with HTTP Server', () {
    test('Rate limiting headers present', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);

      final config = DAVConfig(
        root: root,
        prefix: '/dav',
        enableThrottling: true,
        throttleConfig: const ThrottleConfig(
          maxConcurrentRequests: 10,
          maxRequestsPerSecond: 5,
        ),
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final baseUrl = 'http://localhost:${server.port}';

      try {
        final response = await http.get(Uri.parse('$baseUrl/dav/index.html'));
        expect(response.statusCode, 200);
        expect(response.headers['x-ratelimit-limit'], '5');
        expect(response.headers['x-ratelimit-remaining'], isNotNull);
      } finally {
        await server.close();
      }
    });
  });
}
