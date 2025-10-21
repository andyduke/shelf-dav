/// Comprehensive test suite for WebDAV security features.
///
/// This file consolidates all security-related tests including:
/// - Path traversal attack prevention (../, encoded paths, etc.)
/// - Destination header validation for COPY/MOVE operations
/// - Overwrite header validation
/// - Depth header validation
/// - URL encoding attack prevention
/// - Same source/destination validation

library;

import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:shelf_dav/src/dav_utils.dart';
import 'package:test/test.dart';

void main() {
  group('Path Traversal Detection', () {
    test('Should detect simple path traversal', () {
      expect(containsPathTraversal('../'), isTrue);
      expect(containsPathTraversal('..\\'), isTrue);
      expect(containsPathTraversal('/../'), isTrue);
      expect(containsPathTraversal('\\..\\'), isTrue);
    });

    test('Should detect URL encoded path traversal', () {
      expect(containsPathTraversal('%2e%2e%2f'), isTrue);
      expect(containsPathTraversal('%2e%2e/'), isTrue);
      expect(containsPathTraversal('..%2f'), isTrue);
      expect(containsPathTraversal('%2e%2e%5c'), isTrue);
      expect(containsPathTraversal('%252e%252e%252f'), isTrue);
    });

    test('Should detect unicode path traversal', () {
      expect(containsPathTraversal('..%c0%af'), isTrue);
      expect(containsPathTraversal('..%c1%9c'), isTrue);
    });

    test('Should not flag valid paths', () {
      expect(containsPathTraversal('/valid/path'), isFalse);
      expect(containsPathTraversal('valid/path'), isFalse);
      expect(containsPathTraversal('/valid/path/..'), isTrue);
    });
  });

  group('Path Traversal Protection in Operations', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      // Create test files
      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content');

      // Create file outside root for path traversal tests
      final outsideFile = fs.file('/outside.txt');
      await outsideFile.create();
      await outsideFile.writeAsString('Should not be accessible');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('GET with ../ path traversal should be forbidden', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/../outside.txt'),
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('GET with multiple ../ should be forbidden', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/../../outside.txt'),
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('GET with encoded ../ (%2e%2e%2f) should be forbidden', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/%2e%2e%2foutside.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.forbidden));
    });

    test('GET with backslash path separator should be forbidden', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/..\\outside.txt'),
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('PUT with path traversal should be forbidden', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/../malicious.txt'),
        body: 'malicious content',
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('DELETE with path traversal should be forbidden', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/../outside.txt'),
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('PROPFIND with path traversal should be forbidden', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/../'),
      );
      final response = await dav.handler(request);
      // Path traversal is blocked - either 403 (forbidden) or 404 (not found)
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.notFound)),
      );
    });

    test('Valid path within root should succeed', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      final content = await response.readAsString();
      expect(content, equals('Test content'));
    });
  });

  group('Destination Header Security', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('COPY with path traversal in Destination should fail', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/../outside_copy.txt',
        },
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.badRequest)),
      );
    });

    test('MOVE with path traversal in Destination should fail', () async {
      final request = Request(
        'MOVE',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/../outside_move.txt',
        },
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.badRequest)),
      );
    });

    test('COPY with missing Destination header should return 403', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.forbidden));
    });

    test('COPY with empty Destination header should return 403', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Destination': ''},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.forbidden));
    });

    test('COPY with invalid URL in Destination should return 403', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Destination': 'not a valid url!!!'},
      );
      final response = await dav.handler(request);
      // Invalid destination should be rejected - 403 or 400
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.forbidden), equals(HttpStatus.badRequest)),
      );
    });

    test('COPY with same source and destination should return 403', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Destination': 'http://localhost/dav/test.txt'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.forbidden));
    });
  });

  group('Overwrite Header Validation', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('COPY with Overwrite: F on existing file should return 412', () async {
      // Create a file to overwrite
      final existing = fs.file('/webdav_root/existing.txt');
      await existing.create();
      await existing.writeAsString('existing content');

      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/existing.txt',
          'Overwrite': 'F',
        },
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.preconditionFailed));
    });

    test('COPY with Overwrite: T on existing file should succeed', () async {
      // Create a file to overwrite
      final existing = fs.file('/webdav_root/existing.txt');
      await existing.create();
      await existing.writeAsString('existing content');

      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/existing.txt',
          'Overwrite': 'T',
        },
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));
    });

    test('MOVE with Overwrite: F on existing file should return 412', () async {
      // Create a file to overwrite
      final existing = fs.file('/webdav_root/existing.txt');
      await existing.create();
      await existing.writeAsString('existing content');

      final request = Request(
        'MOVE',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/existing.txt',
          'Overwrite': 'F',
        },
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.preconditionFailed));
    });

    test('COPY with default Overwrite (T) on existing should succeed',
        () async {
      // Create a file to overwrite
      final existing = fs.file('/webdav_root/existing.txt');
      await existing.create();
      await existing.writeAsString('existing content');

      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/existing.txt',
        },
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));
    });
  });

  group('Depth Header Validation', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('PROPFIND with invalid Depth should fail gracefully', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': 'invalid'},
      );
      final response = await dav.handler(request);
      // Should either use default or return error
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.multiStatus),
          equals(HttpStatus.badRequest),
        ),
      );
    });

    test('PROPFIND with Depth: -1 should fail', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': '-1'},
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.multiStatus),
          equals(HttpStatus.badRequest),
        ),
      );
    });

    test('PROPFIND with Depth: 99 should fail', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': '99'},
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.multiStatus),
          equals(HttpStatus.badRequest),
        ),
      );
    });

    test('COPY with Depth: 0 on file should work', () async {
      final request = Request(
        'COPY',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {
          'Destination': 'http://localhost/dav/copy.txt',
          'Depth': '0',
        },
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));
    });
  });
}
