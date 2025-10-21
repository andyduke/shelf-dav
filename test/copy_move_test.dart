import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

/// Tests for COPY and MOVE WebDAV operations on files and directories
/// Covers RFC 4918 compliance, Depth header support, and property preservation

Future<Directory> prepareFilesystem(final FileSystem fs) async {
  final root = fs.directory('/test_root');
  await root.create(recursive: true);

  await fs.file('${root.path}/file1.txt').writeAsString('content1');
  await fs.file('${root.path}/file2.txt').writeAsString('content2');

  await fs.directory('${root.path}/source').create();
  await fs.file('${root.path}/source/a.txt').writeAsString('a');
  await fs.file('${root.path}/source/b.txt').writeAsString('b');

  await fs.directory('${root.path}/source/sub').create();
  await fs.file('${root.path}/source/sub/c.txt').writeAsString('c');

  return root;
}

void main() {
  group('COPY Method - Files', () {
    test('COPY file to same location fails (403 Forbidden)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/file1.txt';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 403);
      } finally {
        await server.close();
      }
    });

    test('COPY file without Destination header fails (400 or 403)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        );

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, anyOf(400, 403));
      } finally {
        await server.close();
      }
    });

    test('COPY file with Overwrite=F to existing file fails (412)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )
          ..headers['Destination'] = '$url/dav/file2.txt'
          ..headers['Overwrite'] = 'F';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 412);
      } finally {
        await server.close();
      }
    });

    test('COPY file with Overwrite=T replaces existing file', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )
          ..headers['Destination'] = '$url/dav/file2.txt'
          ..headers['Overwrite'] = 'T';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 204);

        final getRes = await http.get(Uri.parse('$url/dav/file2.txt'));
        expect(getRes.body, 'content1');
      } finally {
        await server.close();
      }
    });

    test('COPY file to non-existent parent fails (409 Conflict)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/nonexistent/file.txt';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 409);
      } finally {
        await server.close();
      }
    });

    test('COPY file preserves content', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/copy.txt';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 201);

        final original = await http.get(Uri.parse('$url/dav/file1.txt'));
        final copy = await http.get(Uri.parse('$url/dav/copy.txt'));

        expect(original.body, 'content1');
        expect(copy.body, 'content1');
      } finally {
        await server.close();
      }
    });

    test('COPY file preserves custom properties', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final proppatchReq = http.Request(
          'PROPPATCH',
          Uri.parse('$url/dav/file1.txt'),
        )..body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/">
  <D:set>
    <D:prop>
      <Z:author>John Doe</Z:author>
    </D:prop>
  </D:set>
</D:propertyupdate>''';

        await (await proppatchReq.send()).stream.drain();

        final copyReq = http.Request(
          'COPY',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/copy.txt';

        final copyRes = await http.Response.fromStream(await copyReq.send());
        expect(copyRes.statusCode, 201);

        final propfindReq = http.Request(
          'PROPFIND',
          Uri.parse('$url/dav/copy.txt'),
        )
          ..headers['Depth'] = '0'
          ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:" xmlns:Z="http://example.com/">
  <D:prop>
    <Z:author/>
  </D:prop>
</D:propfind>''';

        final propfindRes =
            await http.Response.fromStream(await propfindReq.send());
        expect(propfindRes.statusCode, 207);
        expect(propfindRes.body, contains('author'));
        expect(propfindRes.body, contains('John Doe'));
      } finally {
        await server.close();
      }
    });
  });

  group('COPY Method - Directories', () {
    test('COPY directory with invalid Depth header fails (400)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/source/'),
        )
          ..headers['Destination'] = '$url/dav/dest/'
          ..headers['Depth'] = '1';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 400);
      } finally {
        await server.close();
      }
    });

    test('COPY directory Depth 0 does not copy members', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/source/'),
        )
          ..headers['Destination'] = '$url/dav/dest/'
          ..headers['Depth'] = '0';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 201);

        final destDir = fs.directory('${root.path}/dest');
        expect(await destDir.exists(), isTrue);

        final memberA = fs.file('${root.path}/dest/a.txt');
        expect(await memberA.exists(), isFalse);
      } finally {
        await server.close();
      }
    });

    test('COPY directory Depth infinity copies all members', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'COPY',
          Uri.parse('$url/dav/source/'),
        )
          ..headers['Destination'] = '$url/dav/dest/'
          ..headers['Depth'] = 'infinity';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 201);

        expect(await fs.file('${root.path}/dest/a.txt').exists(), isTrue);
        expect(await fs.file('${root.path}/dest/b.txt').exists(), isTrue);
        expect(
          await fs.directory('${root.path}/dest/sub').exists(),
          isTrue,
        );
        expect(await fs.file('${root.path}/dest/sub/c.txt').exists(), isTrue);

        final content =
            await fs.file('${root.path}/dest/sub/c.txt').readAsString();
        expect(content, 'c');
      } finally {
        await server.close();
      }
    });
  });

  group('MOVE Method - Files', () {
    test('MOVE file to same location fails (403 Forbidden)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/file1.txt';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 403);
      } finally {
        await server.close();
      }
    });

    test('MOVE file with Overwrite=F to existing file fails (412)', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/file1.txt'),
        )
          ..headers['Destination'] = '$url/dav/file2.txt'
          ..headers['Overwrite'] = 'F';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 412);
      } finally {
        await server.close();
      }
    });

    test('MOVE file removes source and creates destination', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/moved.txt';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 201);

        expect(await fs.file('${root.path}/file1.txt').exists(), isFalse);

        final content = await fs.file('${root.path}/moved.txt').readAsString();
        expect(content, 'content1');
      } finally {
        await server.close();
      }
    });

    test('MOVE file within same directory', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        await fs
            .file('${root.path}/index.html')
            .writeAsString('<html>Test</html>');

        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/index.html'),
        )..headers['Destination'] = '$url/dav/newfile.html';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);
        expect(res.statusCode, anyOf(201, 204));

        final getOld = await http.get(Uri.parse('$url/dav/index.html'));
        expect(getOld.statusCode, 404);

        final getNew = await http.get(Uri.parse('$url/dav/newfile.html'));
        expect(getNew.statusCode, 200);
      } finally {
        await server.close();
      }
    });

    test('MOVE with Overwrite=T replaces existing file', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/file1.txt'),
        )
          ..headers['Destination'] = '$url/dav/file2.txt'
          ..headers['Overwrite'] = 'T';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 204);

        expect(await fs.file('${root.path}/file1.txt').exists(), isFalse);

        final content = await fs.file('${root.path}/file2.txt').readAsString();
        expect(content, 'content1');
      } finally {
        await server.close();
      }
    });

    test('MOVE file moves custom properties', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final proppatchReq = http.Request(
          'PROPPATCH',
          Uri.parse('$url/dav/file1.txt'),
        )..body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/">
  <D:set>
    <D:prop>
      <Z:category>Important</Z:category>
    </D:prop>
  </D:set>
</D:propertyupdate>''';

        await (await proppatchReq.send()).stream.drain();

        final moveReq = http.Request(
          'MOVE',
          Uri.parse('$url/dav/file1.txt'),
        )..headers['Destination'] = '$url/dav/moved.txt';

        final moveRes = await http.Response.fromStream(await moveReq.send());
        expect(moveRes.statusCode, 201);

        final propfindReq = http.Request(
          'PROPFIND',
          Uri.parse('$url/dav/moved.txt'),
        )
          ..headers['Depth'] = '0'
          ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:" xmlns:Z="http://example.com/">
  <D:prop>
    <Z:category/>
  </D:prop>
</D:propfind>''';

        final propfindRes =
            await http.Response.fromStream(await propfindReq.send());
        expect(propfindRes.statusCode, 207);
        expect(propfindRes.body, contains('category'));
        expect(propfindRes.body, contains('Important'));
      } finally {
        await server.close();
      }
    });
  });

  group('MOVE Method - Directories', () {
    test('MOVE directory moves all members', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/source/'),
        )..headers['Destination'] = '$url/dav/moved/';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);

        expect(res.statusCode, 201);

        expect(await fs.directory('${root.path}/source').exists(), isFalse);

        expect(await fs.file('${root.path}/moved/a.txt').exists(), isTrue);
        expect(await fs.file('${root.path}/moved/b.txt').exists(), isTrue);
        expect(
          await fs.directory('${root.path}/moved/sub').exists(),
          isTrue,
        );
        expect(await fs.file('${root.path}/moved/sub/c.txt').exists(), isTrue);
      } finally {
        await server.close();
      }
    });

    test('MOVE directory with PROPFIND verification', () async {
      final fs = MemoryFileSystem();
      final root = await prepareFilesystem(fs);
      await fs.directory('${root.path}/dir').create();
      await fs.file('${root.path}/dir/foo.txt').writeAsString('foo');

      final dav = ShelfDAV('/dav', root);
      addTearDown(() async => dav.close());
      final server = await shelf_io.serve(dav.handler, 'localhost', 0);
      final url = 'http://localhost:${server.port}';

      try {
        final request = http.Request(
          'MOVE',
          Uri.parse('$url/dav/dir/'),
        )..headers['Destination'] = '$url/dav/newdir/';

        final streamedResponse = await request.send();
        final res = await http.Response.fromStream(streamedResponse);
        expect(res.statusCode, anyOf(201, 204));

        final request2 = http.Request(
          'PROPFIND',
          Uri.parse('$url/dav/newdir/'),
        )..headers['Depth'] = '1';

        final streamedResponse2 = await request2.send();
        final propRes = await http.Response.fromStream(streamedResponse2);
        expect(propRes.statusCode, 207);
        expect(propRes.body, contains('foo.txt'));
      } finally {
        await server.close();
      }
    });
  });
}
