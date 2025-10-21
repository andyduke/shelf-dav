import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Comprehensive negative tests to ensure exceptions capture correct error semantics
void main() {
  group('Error Semantics Tests', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      // Create directory structure for tests
      final dir = fs.directory('/webdav_root/subdir');
      await dir.create();

      final file = fs.file('/webdav_root/test.txt');
      await file.writeAsString('test content');

      final nested = fs.file('/webdav_root/subdir/nested.txt');
      await nested.writeAsString('nested content');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    group('Parent Directory Validation (409 Conflict)', () {
      test('PUT to file with missing parent directory returns 409', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/missing/file.txt'),
          body: 'content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.conflict));
        final body = await response.readAsString();
        expect(body, contains('Parent collection does not exist'));
      });

      test('MKCOL with missing parent directory returns 409', () async {
        final request = Request(
          'MKCOL',
          Uri.parse('http://localhost/dav/missing/newdir'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.conflict));
        final body = await response.readAsString();
        expect(body, contains('Parent collection does not exist'));
      });

      test('COPY to destination with missing parent returns 409', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/missing/copy.txt',
            'Overwrite': 'T',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.conflict));
        final body = await response.readAsString();
        expect(body, contains('Parent collection does not exist'));
      });

      test('MOVE to destination with missing parent returns 409', () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/missing/moved.txt',
            'Overwrite': 'T',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.conflict));
        final body = await response.readAsString();
        expect(body, contains('Parent collection does not exist'));
      });
    });

    group('COPY/MOVE Validation Errors (403/412)', () {
      test('COPY without Destination header returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('MOVE without Destination header returns 403', () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('COPY with empty Destination header returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Destination': ''},
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('COPY to same source/destination returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/test.txt',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('Source and destination are the same'));
      });

      test('COPY with Overwrite=F when destination exists returns 412',
          () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/subdir/nested.txt',
            'Overwrite': 'F',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.preconditionFailed));
        final body = await response.readAsString();
        expect(body, contains('Overwrite is F'));
      });

      test('MOVE with Overwrite=F when destination exists returns 412',
          () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/subdir/nested.txt',
            'Overwrite': 'F',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.preconditionFailed));
        final body = await response.readAsString();
        expect(body, contains('Overwrite is F'));
      });

      test('COPY with path traversal in Destination returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/../outside.txt',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });

      test('COPY with invalid Destination URL returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'not a valid URL!!!',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
      });
    });

    group('ETag Validation Errors (304/412)', () {
      test('GET with If-None-Match matching ETag returns 304', () async {
        // First GET to obtain ETag
        final request1 = Request(
          'GET',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response1 = await dav.handler(request1);
        expect(response1.statusCode, equals(HttpStatus.ok));
        final etag = response1.headers['ETag'];
        expect(etag, isNotNull);

        // Second GET with If-None-Match
        final request2 = Request(
          'GET',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'If-None-Match': etag!},
        );
        final response2 = await dav.handler(request2);
        expect(response2.statusCode, equals(HttpStatus.notModified));
      });

      test('PUT with If-Match not matching ETag returns 412', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'If-Match': '"wrong-etag"'},
          body: 'new content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.preconditionFailed));
        final body = await response.readAsString();
        expect(body, contains('ETag does not match'));
      });

      test('PUT with If-None-Match: * on existing file returns 412', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'If-None-Match': '*'},
          body: 'new content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.preconditionFailed));
        final body = await response.readAsString();
        expect(body, contains('Resource must exist for update'));
      });
    });

    group('Read-Only Mode Errors (403)', () {
      late ShelfDAV readOnlyDav;

      setUp(() {
        final config = DAVConfig(
          root: root,
          prefix: '/dav',
          readOnly: true,
        );
        readOnlyDav = ShelfDAV.withConfig(config);
      });

      tearDown(() async {
        await readOnlyDav.close();
      });

      test('PUT in read-only mode returns 403', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/new.txt'),
          body: 'content',
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });

      test('DELETE in read-only mode returns 403', () async {
        final request = Request(
          'DELETE',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });

      test('MKCOL in read-only mode returns 403', () async {
        final request = Request(
          'MKCOL',
          Uri.parse('http://localhost/dav/newdir'),
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });

      test('COPY in read-only mode returns 403', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/copy.txt',
          },
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });

      test('MOVE in read-only mode returns 403', () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {
            'Destination': 'http://localhost/dav/moved.txt',
          },
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });

      test('PROPPATCH in read-only mode returns 403', () async {
        final request = Request(
          'PROPPATCH',
          Uri.parse('http://localhost/dav/test.txt'),
          body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:">
  <D:set>
    <D:prop>
      <D:displayname>New Name</D:displayname>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
        );
        final response = await readOnlyDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.forbidden));
        final body = await response.readAsString();
        expect(body, contains('read-only'));
      });
    });

    group('Upload Size Limit Errors (413)', () {
      late ShelfDAV limitedDav;

      setUp(() {
        final config = DAVConfig(
          root: root,
          prefix: '/dav',
          maxUploadSize: 100, // 100 bytes limit
        );
        limitedDav = ShelfDAV.withConfig(config);
      });

      tearDown(() async {
        await limitedDav.close();
      });

      test('PUT exceeding size limit returns 413', () async {
        final largeContent = 'x' * 200; // 200 bytes, exceeds 100 byte limit
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/large.txt'),
          headers: {'Content-Length': '200'},
          body: largeContent,
        );
        final response = await limitedDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.requestEntityTooLarge));
        final body = await response.readAsString();
        expect(body, contains('Upload size exceeds maximum'));
      });

      test('PUT at exact limit succeeds', () async {
        final exactContent = 'x' * 100; // Exactly 100 bytes
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/exact.txt'),
          headers: {'Content-Length': '100'},
          body: exactContent,
        );
        final response = await limitedDav.handler(request);
        expect(response.statusCode, equals(HttpStatus.created));
      });
    });

    group('Method Not Allowed Errors (405)', () {
      test('MKCOL on existing directory returns 405', () async {
        final request = Request(
          'MKCOL',
          Uri.parse('http://localhost/dav/subdir'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
      });

      test('MKCOL on existing file returns 405', () async {
        final request = Request(
          'MKCOL',
          Uri.parse('http://localhost/dav/test.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
      });

      test('PUT to existing directory returns 405', () async {
        final request = Request(
          'PUT',
          Uri.parse('http://localhost/dav/subdir'),
          body: 'content',
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
        final body = await response.readAsString();
        expect(body, contains('Cannot PUT to an existing collection'));
      });
    });

    group('Not Found Errors (404)', () {
      test('GET on non-existent file returns 404', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/dav/nonexistent.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.notFound));
      });

      test('DELETE on non-existent file returns 404', () async {
        final request = Request(
          'DELETE',
          Uri.parse('http://localhost/dav/nonexistent.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.notFound));
      });

      test('HEAD on non-existent file returns 404', () async {
        final request = Request(
          'HEAD',
          Uri.parse('http://localhost/dav/nonexistent.txt'),
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.notFound));
      });

      test('COPY on non-existent source returns 501 (not implemented)',
          () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/nonexistent.txt'),
          headers: {
            'Destination': 'http://localhost/dav/copy.txt',
          },
        );
        final response = await dav.handler(request);
        // Non-existent resources use base DavResource which returns 501
        expect(response.statusCode, equals(HttpStatus.notImplemented));
      });

      test('MOVE on non-existent source returns 501 (not implemented)',
          () async {
        final request = Request(
          'MOVE',
          Uri.parse('http://localhost/dav/nonexistent.txt'),
          headers: {
            'Destination': 'http://localhost/dav/moved.txt',
          },
        );
        final response = await dav.handler(request);
        // Non-existent resources use base DavResource which returns 501
        expect(response.statusCode, equals(HttpStatus.notImplemented));
      });
    });

    group('PROPFIND Depth Header Handling', () {
      test('PROPFIND with invalid Depth header uses default (graceful)',
          () async {
        final request = Request(
          'PROPFIND',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Depth': 'invalid'},
        );
        final response = await dav.handler(request);
        // Invalid Depth gracefully defaults, returns 207 Multi-Status
        expect(response.statusCode, equals(HttpStatus.multiStatus));
      });

      test('PROPFIND with negative Depth uses default (graceful)', () async {
        final request = Request(
          'PROPFIND',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Depth': '-1'},
        );
        final response = await dav.handler(request);
        // Invalid Depth gracefully defaults, returns 207 Multi-Status
        expect(response.statusCode, equals(HttpStatus.multiStatus));
      });

      test('PROPFIND with excessive Depth uses default (graceful)', () async {
        final request = Request(
          'PROPFIND',
          Uri.parse('http://localhost/dav/test.txt'),
          headers: {'Depth': '999'},
        );
        final response = await dav.handler(request);
        // Invalid Depth gracefully defaults, returns 207 Multi-Status
        expect(response.statusCode, equals(HttpStatus.multiStatus));
      });
    });

    group('COPY Depth Validation for Collections (400)', () {
      test('COPY directory with Depth=1 returns 400', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/subdir'),
          headers: {
            'Destination': 'http://localhost/dav/copydir',
            'Depth': '1',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.badRequest));
        final body = await response.readAsString();
        expect(body, contains('Depth header'));
        expect(body, contains('0 or infinity'));
      });

      test('COPY directory with invalid Depth returns 400', () async {
        final request = Request(
          'COPY',
          Uri.parse('http://localhost/dav/subdir'),
          headers: {
            'Destination': 'http://localhost/dav/copydir',
            'Depth': '5',
          },
        );
        final response = await dav.handler(request);
        expect(response.statusCode, equals(HttpStatus.badRequest));
        final body = await response.readAsString();
        expect(body, contains('Depth header'));
      });
    });
  });
}
