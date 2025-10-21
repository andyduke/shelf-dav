import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Tests for file-level WebDAV operations: GET, HEAD, PUT, DELETE
void main() {
  group('GET Method', () {
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

      final htmlFile = fs.file('/webdav_root/index.html');
      await htmlFile.create();
      await htmlFile.writeAsString('<html>Root Index</html>');

      final gifFile = fs.file('/webdav_root/test.gif');
      await gifFile.create();
      await gifFile.writeAsBytes([0x47, 0x49, 0x46]);

      final jpegFile = fs.file('/webdav_root/test.jpeg');
      await jpegFile.create();
      await jpegFile.writeAsBytes([0xFF, 0xD8, 0xFF]);

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('GET file returns 200 OK with content', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(await response.readAsString(), equals('Test content'));
    });

    test('GET HTML file returns correct content', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/index.html'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(await response.readAsString(), contains('Root Index'));
    });

    test('GET image file returns correct Content-Type (GIF)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.gif'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-type'], equals('image/gif'));
    });

    test('GET image file returns correct Content-Type (JPEG)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.jpeg'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-type'], equals('image/jpeg'));
    });

    test('GET non-existent file returns 404', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('GET includes ETag header', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['etag'], isNot(isEmpty));
    });

    test('GET includes Last-Modified header', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.headers['last-modified'], isNotNull);
    });

    test('GET with If-None-Match matching ETag returns 304', () async {
      final request1 = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response1 = await dav.handler(request1);
      final etag = response1.headers['etag']!;

      final request2 = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-None-Match': etag},
      );
      final response2 = await dav.handler(request2);
      expect(response2.statusCode, equals(HttpStatus.notModified));
    });

    test('GET with If-None-Match not matching returns 200', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-None-Match': '"different-etag"'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('GET with If-Match matching ETag returns 200', () async {
      final request1 = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response1 = await dav.handler(request1);
      final etag = response1.headers['etag']!;

      final request2 = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-Match': etag},
      );
      final response2 = await dav.handler(request2);
      expect(response2.statusCode, equals(HttpStatus.ok));
    });

    test('GET with If-Match not matching returns 412', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-Match': '"wrong-etag"'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.preconditionFailed));
    });
  });

  group('HEAD Method', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/test.txt');
      await file.create();
      await file.writeAsString('Test content for HEAD method');

      final largeFile = fs.file('/webdav_root/large.txt');
      await largeFile.create();
      await largeFile.writeAsString('x' * 10000);

      final pdfFile = fs.file('/webdav_root/test.pdf');
      await pdfFile.create();
      await pdfFile.writeAsBytes([0x25, 0x50, 0x44, 0x46]); // %PDF header

      final dir = fs.directory('/webdav_root/testdir');
      await dir.create();

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('HEAD on file returns 200 OK', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('HEAD does not return body', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();
      expect(body, isEmpty);
    });

    test('HEAD includes Content-Length header', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.headers['content-length'], isNotNull);
      expect(response.headers['content-length'], equals('28'));
    });

    test('HEAD includes ETag header', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['etag'], isNot(isEmpty));
    });

    test('HEAD includes Last-Modified header', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response = await dav.handler(request);
      expect(response.headers['last-modified'], isNotNull);
    });

    test('HEAD and GET return same headers', () async {
      final headRequest = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final headResponse = await dav.handler(headRequest);

      final getRequest = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final getResponse = await dav.handler(getRequest);

      expect(
        headResponse.headers['content-length'],
        equals(getResponse.headers['content-length']),
      );
      expect(
        headResponse.headers['etag'],
        equals(getResponse.headers['etag']),
      );
      expect(
        headResponse.headers['last-modified'],
        equals(getResponse.headers['last-modified']),
      );
      expect(
        headResponse.headers['content-type'],
        equals(getResponse.headers['content-type']),
      );
    });

    test('HEAD on PDF file includes correct Content-Type', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.pdf'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-type'], equals('application/pdf'));
    });

    test('HEAD on non-existent file returns 404', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('HEAD with If-None-Match matching ETag returns 304', () async {
      final headRequest1 = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response1 = await dav.handler(headRequest1);
      final etag = response1.headers['etag']!;

      final headRequest2 = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-None-Match': etag},
      );
      final response2 = await dav.handler(headRequest2);
      expect(response2.statusCode, equals(HttpStatus.notModified));
    });

    test('HEAD with If-None-Match not matching returns 200', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-None-Match': '"different-etag"'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('HEAD on directory returns 200', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/testdir/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('HEAD on large file returns quickly', () async {
      final startTime = DateTime.now();

      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/large.txt'),
      );
      final response = await dav.handler(request);

      final duration = DateTime.now().difference(startTime);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-length'], equals('10000'));
      expect(duration.inMilliseconds, lessThan(1000));
    });

    test('HEAD with trailing slash on file works', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });

    test('HEAD with If-Match matching ETag returns 200', () async {
      final headRequest1 = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
      );
      final response1 = await dav.handler(headRequest1);
      final etag = response1.headers['etag']!;

      final headRequest2 = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-Match': etag},
      );
      final response2 = await dav.handler(headRequest2);
      expect(response2.statusCode, equals(HttpStatus.ok));
    });

    test('HEAD with If-Match not matching returns 412', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'If-Match': '"wrong-etag"'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.preconditionFailed));
    });
  });

  group('PUT Method', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/existing.txt');
      await file.create();
      await file.writeAsString('old content');

      final dir = fs.directory('/webdav_root/dir');
      await dir.create();

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('PUT creating new file returns 201 Created', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/newfile.txt'),
        body: 'new content',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));

      final file = fs.file('/webdav_root/newfile.txt');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), equals('new content'));
    });

    test('PUT updating existing file returns 200 OK', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/existing.txt'),
        body: 'updated content',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));

      final file = fs.file('/webdav_root/existing.txt');
      expect(await file.readAsString(), equals('updated content'));
    });

    test('PUT and GET round-trip preserves content', () async {
      final putRequest = Request(
        'PUT',
        Uri.parse('http://localhost/dav/roundtrip.txt'),
        headers: {'Content-Type': 'text/html'},
        body: '<html>foo</html>',
      );
      final putResponse = await dav.handler(putRequest);
      expect(putResponse.statusCode, equals(HttpStatus.created));

      final getRequest = Request(
        'GET',
        Uri.parse('http://localhost/dav/roundtrip.txt'),
      );
      final getResponse = await dav.handler(getRequest);
      expect(getResponse.statusCode, equals(HttpStatus.ok));
      expect(await getResponse.readAsString(), equals('<html>foo</html>'));
    });

    test('PUT includes ETag header in response', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/test.txt'),
        body: 'content',
      );
      final response = await dav.handler(request);
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['etag'], isNot(isEmpty));
    });

    test('PUT includes Last-Modified header', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/test2.txt'),
        body: 'content',
      );
      final response = await dav.handler(request);
      expect(response.headers['last-modified'], isNotNull);
    });

    test('PUT to non-existent parent directory returns 409 Conflict', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/nonexistent/file.txt'),
        body: 'content',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.conflict));
    });

    test('PUT with If-Match and correct ETag succeeds', () async {
      final put1 = Request(
        'PUT',
        Uri.parse('http://localhost/dav/existing.txt'),
        body: 'content1',
      );
      final response1 = await dav.handler(put1);
      final etag = response1.headers['etag']!;

      final put2 = Request(
        'PUT',
        Uri.parse('http://localhost/dav/existing.txt'),
        body: 'content2',
        headers: {'If-Match': etag},
      );
      final response2 = await dav.handler(put2);
      expect(response2.statusCode, equals(HttpStatus.ok));
    });

    test('PUT with If-Match and wrong ETag returns 412', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/existing.txt'),
        body: 'content',
        headers: {'If-Match': '"wrong-etag"'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.preconditionFailed));
    });

    test('PUT with If-None-Match: * on new file succeeds', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/brand_new.txt'),
        body: 'content',
        headers: {'If-None-Match': '*'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.created));
    });

    test('PUT with empty body creates empty file', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/empty.txt'),
        body: '',
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.created), equals(HttpStatus.ok)),
      );

      final file = fs.file('/webdav_root/empty.txt');
      expect(await file.exists(), isTrue);
    });

    test('PUT with Content-Length header is validated', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/test3.txt'),
        body: 'short',
        headers: {'Content-Length': '5'},
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.created), equals(HttpStatus.ok)),
      );
    });

    test('PUT on directory path fails', () async {
      final request = Request(
        'PUT',
        Uri.parse('http://localhost/dav/dir/'),
        body: 'content',
      );
      final response = await dav.handler(request);
      expect(
        response.statusCode,
        anyOf(
          equals(HttpStatus.methodNotAllowed),
          equals(HttpStatus.conflict),
        ),
      );
    });
  });

  group('DELETE Method on Files', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      final file = fs.file('/webdav_root/deleteme.txt');
      await file.create();
      await file.writeAsString('content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('DELETE file returns 204 No Content', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/deleteme.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final file = fs.file('/webdav_root/deleteme.txt');
      expect(await file.exists(), isFalse);
    });

    test('DELETE non-existent file returns 404', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('DELETE file without trailing slash works', () async {
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/deleteme.txt'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.noContent));
    });

    test('DELETE removes properties', () async {
      final putRequest = Request(
        'PUT',
        Uri.parse('http://localhost/dav/propfile.txt'),
        body: 'content',
      );
      await dav.handler(putRequest);

      final proppatch = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/propfile.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:author>Test Author</Z:author>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      await dav.handler(proppatch);

      final deleteRequest = Request(
        'DELETE',
        Uri.parse('http://localhost/dav/propfile.txt'),
      );
      final response = await dav.handler(deleteRequest);
      expect(response.statusCode, equals(HttpStatus.noContent));

      final putRequest2 = Request(
        'PUT',
        Uri.parse('http://localhost/dav/propfile.txt'),
        body: 'content',
      );
      await dav.handler(putRequest2);

      final propfind = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/propfile.txt'),
      );
      final propfindResponse = await dav.handler(propfind);
      final body = await propfindResponse.readAsString();
      expect(body, isNot(contains('author')));
    });
  });
}
