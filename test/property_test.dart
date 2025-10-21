/// Comprehensive test suite for WebDAV property operations (PROPFIND and PROPPATCH).
///
/// This file consolidates all property-related tests including:
/// - PROPFIND operations with different Depth values (0, 1, infinity)
/// - PROPFIND on files, directories, and collections
/// - PROPPATCH set and remove operations
/// - Custom property persistence
/// - Property XML response generation
/// - Multi-namespace property support

library;

import 'dart:io' show HttpStatus;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:shelf_dav/src/dav_utils.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  group('PROPFIND Tests', () {
    late MemoryFileSystem fs;
    late Directory root;
    late ShelfDAV dav;

    setUp(() async {
      fs = MemoryFileSystem();
      root = fs.directory('/webdav_root');
      await root.create(recursive: true);

      // Create directory structure
      final dir1 = fs.directory('/webdav_root/dir1');
      await dir1.create();

      final dir2 = fs.directory('/webdav_root/dir1/dir2');
      await dir2.create();

      // Create files
      final file1 = fs.file('/webdav_root/file1.txt');
      await file1.create();
      await file1.writeAsString('content1');

      final file2 = fs.file('/webdav_root/dir1/file2.txt');
      await file2.create();
      await file2.writeAsString('content2');

      final file3 = fs.file('/webdav_root/dir1/dir2/file3.txt');
      await file3.create();
      await file3.writeAsString('content3');

      dav = ShelfDAV('/dav', root);
    });

    tearDown(() async {
      await dav.close();
    });

    test('PROPFIND with Depth: 0 on file returns only file', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should contain file1.txt
      expect(body, contains('file1.txt'));
      // Should not contain other files
      expect(body, isNot(contains('file2.txt')));
      expect(body, isNot(contains('dir1')));
    });

    test('PROPFIND with Depth: 0 on directory returns only directory',
        () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/dir1/'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should contain dir1
      expect(body, contains('<D:collection'));
      // Should not contain children
      expect(body, isNot(contains('file2.txt')));
      expect(body, isNot(contains('dir2')));
    });

    test('PROPFIND with Depth: 1 on directory returns immediate children',
        () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/dir1/'),
        headers: {'Depth': '1'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should contain dir1
      expect(body, contains('dir1'));
      // Should contain immediate children
      expect(body, contains('file2.txt'));
      expect(body, contains('dir2'));
      // Should not contain nested children
      expect(body, isNot(contains('file3.txt')));
    });

    test('PROPFIND with Depth: infinity returns all descendants', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/dir1/'),
        headers: {'Depth': 'infinity'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should contain everything
      expect(body, contains('dir1'));
      expect(body, contains('file2.txt'));
      expect(body, contains('dir2'));
      expect(body, contains('file3.txt'));
    });

    test(
        'PROPFIND with no Depth header defaults to Depth: infinity per RFC 4918',
        () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/dir1/'),
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Per RFC 4918, should return dir1 and all children recursively
      expect(body, contains('<D:collection'));
      // Should contain immediate children
      expect(body, contains('file2.txt'));
      expect(body, contains('dir2'));
      // Should contain nested children
      expect(body, contains('file3.txt'));
    });

    test('PROPFIND on non-existent resource returns 404', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('PROPFIND response has correct Content-Type', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
      expect(response.headers['content-type'], contains('xml'));
    });

    test('PROPFIND returns standard DAV properties', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();

      // Should contain standard properties
      expect(body, contains('displayname'));
      expect(body, contains('getlastmodified'));
      expect(body, contains('getcontentlength'));
      expect(body, contains('getcontenttype'));
      expect(body, contains('resourcetype'));
    });

    test('PROPFIND on collection includes collection resourcetype', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/dir1/'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();

      // Should indicate it's a collection
      expect(body, contains('<D:collection'));
      expect(body, contains('resourcetype'));
    });

    test('PROPFIND on file does not include collection resourcetype', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();

      // Should have empty resourcetype for file
      expect(body, contains('resourcetype'));
      // But not a collection
      expect(body, isNot(contains('<D:collection')));
    });

    test('PROPFIND returns 200 OK status in prop stat', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();

      expect(body, contains('HTTP/1.1 200 OK'));
    });

    test('PROPFIND with trailing slash on file should work', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/file1.txt/'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      // Should handle gracefully
      expect(
        response.statusCode,
        anyOf(equals(HttpStatus.multiStatus), equals(HttpStatus.notFound)),
      );
    });

    test('PROPFIND on root returns root collection', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      expect(body, contains('<D:collection'));
    });

    test('PROPFIND Depth: 1 on root lists immediate children', () async {
      final request = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/'),
        headers: {'Depth': '1'},
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should contain top-level items
      expect(body, contains('file1.txt'));
      expect(body, contains('dir1'));
      // Should not contain nested items
      expect(body, isNot(contains('file2.txt')));
    });
  });

  group('PROPPATCH Tests', () {
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

    test('PROPPATCH set property returns 207 Multi-Status', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:author>Jane Doe</Z:author>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
    });

    test('PROPPATCH set property returns correct XML response', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:status>draft</Z:status>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      final body = await response.readAsString();

      // Should be valid XML with multistatus
      expect(body, contains('<?xml'));
      expect(body, contains('<D:multistatus'));
      expect(body, contains('<D:response'));
      expect(body, contains('<D:propstat'));
      expect(body, contains('HTTP/1.1 200'));
    });

    test('PROPPATCH remove property succeeds', () async {
      // First set a property
      final setRequest = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:removeme>value</Z:removeme>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      await dav.handler(setRequest);

      // Now remove it
      final removeRequest = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:remove>
    <D:prop>
      <Z:removeme/>
    </D:prop>
  </D:remove>
</D:propertyupdate>''',
      );
      final response = await dav.handler(removeRequest);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      expect(body, contains('HTTP/1.1 200'));
    });

    test('PROPPATCH remove non-existent property returns appropriate status',
        () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:remove>
    <D:prop>
      <Z:nonexistent/>
    </D:prop>
  </D:remove>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));

      final body = await response.readAsString();
      // Should indicate failure for non-existent property
      expect(
        body,
        anyOf(contains('HTTP/1.1 404'), contains('HTTP/1.1 200')),
      );
    });

    test('PROPPATCH set multiple properties', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:author>Jane Doe</Z:author>
      <Z:title>My Document</Z:title>
      <Z:category>Important</Z:category>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
    });

    test('PROPPATCH mixed set and remove operations', () async {
      // First set some properties
      final setRequest = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:prop1>value1</Z:prop1>
      <Z:prop2>value2</Z:prop2>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      await dav.handler(setRequest);

      // Now mix set and remove
      final mixedRequest = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:prop3>value3</Z:prop3>
    </D:prop>
  </D:set>
  <D:remove>
    <D:prop>
      <Z:prop1/>
    </D:prop>
  </D:remove>
</D:propertyupdate>''',
      );
      final response = await dav.handler(mixedRequest);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
    });

    test('PROPPATCH with empty body returns 400', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.badRequest));
    });

    test('PROPPATCH with invalid XML returns 400', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '<not valid xml',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.badRequest));
    });

    test('PROPPATCH on non-existent resource returns 404', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:author>Test</Z:author>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
    });

    test('PROPPATCH on directory succeeds', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/testdir/'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:description>Test Directory</Z:description>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
    });

    test('PROPPATCH properties persist after set', () async {
      // Set a property
      final setRequest = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:testprop>testvalue</Z:testprop>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      await dav.handler(setRequest);

      // Verify with PROPFIND
      final propfindRequest = Request(
        'PROPFIND',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Depth': '0'},
      );
      final response = await dav.handler(propfindRequest);
      final body = await response.readAsString();

      // Should contain the custom property
      expect(body, contains('testprop'));
      expect(body, contains('testvalue'));
    });

    test('PROPPATCH with different namespace', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:custom="http://custom.example.com/">
  <D:set>
    <D:prop>
      <custom:field>value</custom:field>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.statusCode, equals(HttpStatus.multiStatus));
    });

    test('PROPPATCH response has correct Content-Type', () async {
      final request = Request(
        'PROPPATCH',
        Uri.parse('http://localhost/dav/test.txt'),
        body: '''<?xml version="1.0"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
  <D:set>
    <D:prop>
      <Z:test>value</Z:test>
    </D:prop>
  </D:set>
</D:propertyupdate>''',
      );
      final response = await dav.handler(request);
      expect(response.headers['content-type'], contains('xml'));
    });
  });

  group('Property Builder Tests', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
      fs.file('/file.txt').createSync();
      fs.directory('/dir').createSync();
      fs.file('/dir/foo.txt').createSync();
      fs.directory('dir/bar').createSync();
      fs.file('dir/bar/foo.txt').createSync();
      fs.file('dir/bar/bar.txt').createSync();
      fs.directory('dir/bar/baz').createSync();
    });

    test('simple property', () async {
      final builder = XmlBuilder()..namespace('DAV:', 'D');
      property(builder, 'foo', 'bar');
      expect(
        builder.buildDocument().toXmlString(),
        equals('<D:foo>bar</D:foo>'),
      );
    });

    test('file properties', () async {
      final builder = XmlBuilder()..namespace('DAV:', 'D');
      await file(
        builder,
        p.Context(current: '/dav'),
        fs.directory('/'),
        fs.file('/dir/foo.txt'),
      );
      final result = builder.buildDocument().toXmlString(pretty: true);
      expect(result, contains('<D:displayname>foo.txt</D:displayname>'));
      expect(result, contains('<D:href>/dav/dir/foo.txt</D:href>'));
    });

    test('relative file properties', () async {
      final builder = XmlBuilder()..namespace('DAV:', 'D');
      await file(
        builder,
        p.Context(current: '/dav'),
        fs.directory('/dir'),
        fs.file('/dir/foo.txt'),
      );
      final result = builder.buildDocument().toXmlString(pretty: true);
      expect(result, contains('<D:displayname>foo.txt</D:displayname>'));
      expect(result, contains('<D:href>/dav/foo.txt</D:href>'));
    });

    test('a directory properties', () async {
      final builder = XmlBuilder()..namespace('DAV:', 'D');
      await directory(
        builder,
        p.Context(current: '/dav'),
        fs.directory('/'),
        fs.directory('/'),
        true,
        1,
      );
      final result = builder.buildDocument().toXmlString(pretty: true);
      // With Depth 1, should return root and its immediate children only
      expect(result, contains('<D:href>/dav/file.txt</D:href>'));
      expect(result, contains('<D:href>/dav/dir/</D:href>'));
      // Should NOT contain grandchildren (dir/foo.txt, etc) with Depth 1
      expect(result, isNot(contains('<D:href>/dav/dir/foo.txt</D:href>')));
      expect(result, isNot(contains('<D:href>/dav/dir/bar/foo.txt</D:href>')));
      expect(result, isNot(contains('<D:href>/dav/dir/bar/bar.txt</D:href>')));
      expect(result, contains('<D:displayname></D:displayname>'));
      expect(result, contains('<D:displayname>file.txt</D:displayname>'));
    });

    test('relative directory properties', () async {
      final builder = XmlBuilder()..namespace('DAV:', 'D');
      await directory(
        builder,
        p.Context(current: '/dav'),
        fs.directory('/dir/bar'),
        fs.directory('/dir/bar'),
        true,
        1,
      );
      final result = builder.buildDocument().toXmlString(pretty: true);
      expect(result, contains('<D:href>/dav/foo.txt</D:href>'));
      expect(result, contains('<D:href>/dav/bar.txt</D:href>'));
      expect(result, contains('<D:href>/dav/baz/</D:href>'));
      expect(result, contains('<D:displayname></D:displayname>'));
      expect(result, contains('<D:displayname>foo.txt</D:displayname>'));
      expect(result, contains('<D:displayname>bar.txt</D:displayname>'));
    });
  });
}
