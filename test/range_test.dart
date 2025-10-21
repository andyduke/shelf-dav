import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Tests for HTTP Range request support (RFC 7233)
void main() {
  group('Range Request Support', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      // Create a test file with 100 bytes (0-99)
      final file = fs.file('/webdav_root/test.bin');
      await file.create();
      await file.writeAsBytes(List.generate(100, (i) => i));

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('GET without Range header returns full file with Accept-Ranges',
        () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['accept-ranges'], equals('bytes'));
      expect(response.headers['content-length'], equals('100'));

      final body = await response.readAsString();
      expect(body.codeUnits.length, equals(100));
    });

    test('HEAD includes Accept-Ranges header', () async {
      final request = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.bin'),
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['accept-ranges'], equals('bytes'));
      expect(response.headers['content-length'], equals('100'));
    });

    test('Range request for bytes 10-19 returns 206 Partial Content', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=10-19'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 10-19/100'));
      expect(response.headers['content-length'], equals('10'));
      expect(response.headers['accept-ranges'], equals('bytes'));

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();
      expect(bytes, equals([10, 11, 12, 13, 14, 15, 16, 17, 18, 19]));
    });

    test('Range request from start to end (bytes=0-9)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=0-9'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 0-9/100'));
      expect(response.headers['content-length'], equals('10'));

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();
      expect(bytes, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
    });

    test('Range request to end of file (bytes=90-)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=90-'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 90-99/100'));
      expect(response.headers['content-length'], equals('10'));

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();
      expect(bytes, equals([90, 91, 92, 93, 94, 95, 96, 97, 98, 99]));
    });

    test('Range request for single byte (bytes=50-50)', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=50-50'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 50-50/100'));
      expect(response.headers['content-length'], equals('1'));

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();
      expect(bytes, equals([50]));
    });

    test('Range request beyond file size returns 416', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=200-299'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(416));
      expect(response.headers['content-range'], equals('bytes */100'));
    });

    test('Invalid Range request (end < start) returns 416', () async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=50-40'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(416));
      expect(response.headers['content-range'], equals('bytes */100'));
    });

    test('Range request works with PDF files', () async {
      // Create a minimal PDF
      final pdfFile = fs.file('/webdav_root/test.pdf');
      await pdfFile.create();
      final pdfBytes = List.generate(1000, (i) => i % 256);
      await pdfFile.writeAsBytes(pdfBytes);

      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.pdf'),
        headers: {'Range': 'bytes=0-99'},
      );
      final response = await dav.handler(request);

      expect(response.statusCode, equals(206));
      expect(response.headers['content-type'], equals('application/pdf'));
      expect(response.headers['content-range'], equals('bytes 0-99/1000'));
      expect(response.headers['content-length'], equals('100'));

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();
      expect(bytes, equals(pdfBytes.sublist(0, 100)));
    });

    test('Range request preserves ETag', () async {
      // First get the ETag
      final headRequest = Request(
        'HEAD',
        Uri.parse('http://localhost/dav/test.bin'),
      );
      final headResponse = await dav.handler(headRequest);
      final etag = headResponse.headers['etag'];

      // Then make a Range request
      final rangeRequest = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=0-9'},
      );
      final rangeResponse = await dav.handler(rangeRequest);

      expect(rangeResponse.statusCode, equals(206));
      expect(rangeResponse.headers['etag'], equals(etag));
    });

    test('Multi-range requests are not supported (returns full file)',
        () async {
      // Multi-range like "bytes=0-10,20-30" should be ignored
      final request = Request(
        'GET',
        Uri.parse('http://localhost/dav/test.bin'),
        headers: {'Range': 'bytes=0-10,20-30'},
      );
      final response = await dav.handler(request);

      // Should return full file since multi-range isn't supported
      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.headers['content-length'], equals('100'));
    });
  });
}
