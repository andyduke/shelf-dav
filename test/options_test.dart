import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

void main() {
  group('OPTIONS Method Tests', () {
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
      await file.writeAsString('content');

      // Create test directory
      final dir = fs.directory('/webdav_root/testdir');
      await dir.create();

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('OPTIONS on root should return 200 OK', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('OPTIONS should include DAV compliance class headers', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(response.headers['dav'], isNotNull);
      expect(response.headers['dav'], contains('1'));
      expect(response.headers['dav'], contains('2'));
    });

    test('OPTIONS should include Allow header with supported methods',
        () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      final allow = response.headers['allow'];
      expect(allow, isNotNull);

      // Check for required WebDAV methods
      expect(allow, contains('OPTIONS'));
      expect(allow, contains('GET'));
      expect(allow, contains('HEAD'));
      expect(allow, contains('PUT'));
      expect(allow, contains('DELETE'));
      expect(allow, contains('PROPFIND'));
      expect(allow, contains('PROPPATCH'));
      expect(allow, contains('COPY'));
      expect(allow, contains('MOVE'));
      expect(allow, contains('LOCK'));
      expect(allow, contains('UNLOCK'));
    });

    test('OPTIONS should include MS-Author-Via header', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(response.headers['ms-author-via'], equals('DAV'));
    });

    test('OPTIONS on file should return same headers', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['dav'], isNotNull);
      expect(response.headers['allow'], isNotNull);
    });

    test('OPTIONS on directory should return same headers', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/testdir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['dav'], isNotNull);
      expect(response.headers['allow'], isNotNull);
    });

    test('OPTIONS on non-existent resource should still return 200', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['dav'], isNotNull);
    });

    test('OPTIONS with Depth header should be ignored', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': '1'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('OPTIONS response should have no body', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-length'], equals('0'));
    });

    test('OPTIONS should work with trailing slash', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost/dav/test.txt/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });
  });
}
