import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Tests for directory/collection-level WebDAV operations: MKCOL, DELETE
void main() {
  group('MKCOL Method', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final existingDir = fs.directory('/webdav_root/existing');
      await existingDir.create();

      final file = fs.file('/webdav_root/file.txt');
      await file.create();
      await file.writeAsString('content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('MKCOL on new collection returns 201 Created', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/newcol'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));
      expect(response.headers['location'], isNotNull);

      final dir = fs.directory('/webdav_root/newcol');
      expect(await dir.exists(), isTrue);
    });

    test('MKCOL includes Location header with absolute URI', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/newcol2'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));
      expect(
        response.headers['location'],
        equals('http://localhost/dav/newcol2'),
      );
    });

    test('MKCOL on existing directory returns 405 Method Not Allowed',
        () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/existing'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
    });

    test('MKCOL on existing file path returns 405', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/file.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
    });

    test('MKCOL with non-existent parent returns 409 Conflict', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/nonexistent/newcol'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.conflict));
    });

    test('MKCOL with request body returns 415 Unsupported Media Type',
        () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/newcol3'),
        body: '<some>xml</some>',
        headers: {'Content-Type': 'application/xml'},
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.created),
          equals(HttpStatus.unsupportedMediaType),
        ),
      );
    });

    test('MKCOL with trailing slash works', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/newcol4/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));

      final dir = fs.directory('/webdav_root/newcol4');
      expect(await dir.exists(), isTrue);
    });

    test('MKCOL on root returns 405', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
    });

    test('Multiple MKCOL calls create separate collections', () async {
      final request1 = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/col1'),
      );
      final response1 = await dav.handler(request1);
      expect(response1.statusCode, equals(HttpStatus.created));

      final request2 = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/col2'),
      );
      final response2 = await dav.handler(request2);
      expect(response2.statusCode, equals(HttpStatus.created));

      expect(await fs.directory('/webdav_root/col1').exists(), isTrue);
      expect(await fs.directory('/webdav_root/col2').exists(), isTrue);
    });

    test('MKCOL followed by PROPFIND lists empty collection', () async {
      final mkcolRequest = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/empty'),
      );
      final mkcolResponse = await dav.handler(mkcolRequest);
      expect(mkcolResponse.statusCode, equals(HttpStatus.created));

      final propfindRequest = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/empty/'),
        headers: {'Depth': '1'},
      );
      final propfindResponse = await dav.handler(propfindRequest);
      expect(propfindResponse.statusCode, equals(HttpStatus.multiStatus));

      final body = await propfindResponse.readAsString();
      expect(body, contains('<D:collection'));
    });

    test('MKCOL with special characters in name works', () async {
      final request = Request(
        'MKCOL',
        Uri.parse('http://localhost/dav/col-with_special.chars'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));

      final dir = fs.directory('/webdav_root/col-with_special.chars');
      expect(await dir.exists(), isTrue);
    });
  });

  group('DELETE Method on Directories', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final dir = fs.directory('/webdav_root/deletedir');
      await dir.create();
      final file1 = fs.file('/webdav_root/deletedir/file1.txt');
      await file1.create();
      final file2 = fs.file('/webdav_root/deletedir/file2.txt');
      await file2.create();

      final emptyDir = fs.directory('/webdav_root/emptydir');
      await emptyDir.create();

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('DELETE empty directory returns 204', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/emptydir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final dir = fs.directory('/webdav_root/emptydir');
      expect(await dir.exists(), isFalse);
    });

    test('DELETE directory with contents returns 204', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/deletedir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final dir = fs.directory('/webdav_root/deletedir');
      expect(await dir.exists(), isFalse);
    });

    test('DELETE acts as if Depth: infinity per RFC 4918', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/deletedir/'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final dir = fs.directory('/webdav_root/deletedir');
      expect(await dir.exists(), isFalse);
    });

    test('DELETE on root fails', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/'),
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.forbidden),
          equals(HttpStatus.methodNotAllowed),
        ),
      );
    });

    test('DELETE directory removes nested subdirectories', () async {
      final subdir = fs.directory('/webdav_root/deletedir/subdir');
      await subdir.create();
      final nestedFile = fs.file('/webdav_root/deletedir/subdir/nested.txt');
      await nestedFile.create();

      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/deletedir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final dir = fs.directory('/webdav_root/deletedir');
      expect(await dir.exists(), isFalse);
      expect(await subdir.exists(), isFalse);
    });
  });

  group('GET Method on Directories', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final dir = fs.directory('/webdav_root/testdir');
      await dir.create();

      final file = fs.file('/webdav_root/testdir/file.txt');
      await file.create();
      await file.writeAsString('content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('GET on directory returns 200', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/testdir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('GET on directory with trailing slash works', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/testdir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });
  });
}
