import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:file/file.dart';
import 'package:path/path.dart';
import 'package:shelf_dav/src/dav_utils.dart';

/// Stream-based XML generation for large PROPFIND responses
///
/// Generates XML incrementally to avoid loading entire directory tree into memory.
/// Uses streaming approach for directories with many children.
class XmlStreamBuilder {
  final StreamController<String> _controller = StreamController<String>();

  Stream<String> get stream => _controller.stream;

  /// Start the multistatus response
  void start() {
    _emit('<?xml version="1.0" encoding="utf-8"?>');
    _emit('<D:multistatus xmlns:D="DAV:">');
  }

  /// End the multistatus response
  void end() {
    _emit('</D:multistatus>');
    _controller.close();
  }

  /// Add a file response
  Future<void> addFile({
    required final String href,
    required final int size,
    required final DateTime modified,
    required final String etag,
    final Map<String, dynamic> custom = const {},
  }) async {
    _emit('  <D:response>');
    _emit('    <D:href>$href</D:href>');
    _emit('    <D:propstat>');
    _emit('      <D:prop>');
    _emit('        <D:getcontentlength>$size</D:getcontentlength>');
    _emit(
      '        <D:getlastmodified>${HttpDate.format(modified)}</D:getlastmodified>',
    );
    _emit('        <D:getetag>$etag</D:getetag>');
    _emit('        <D:resourcetype/>');

    for (final entry in custom.entries) {
      final value = _escapeXml(entry.value.toString());
      _emit('        <D:${entry.key}>$value</D:${entry.key}>');
    }

    _emit('      </D:prop>');
    _emit('      <D:status>HTTP/1.1 200 OK</D:status>');
    _emit('    </D:propstat>');
    _emit('  </D:response>');
  }

  /// Add a directory response
  Future<void> addDirectory({
    required final String href,
    required final DateTime modified,
    final Map<String, dynamic> custom = const {},
  }) async {
    _emit('  <D:response>');
    _emit('    <D:href>$href</D:href>');
    _emit('    <D:propstat>');
    _emit('      <D:prop>');
    _emit(
      '        <D:getlastmodified>${HttpDate.format(modified)}</D:getlastmodified>',
    );
    _emit('        <D:resourcetype><D:collection/></D:resourcetype>');

    for (final entry in custom.entries) {
      final value = _escapeXml(entry.value.toString());
      _emit('        <D:${entry.key}>$value</D:${entry.key}>');
    }

    _emit('      </D:prop>');
    _emit('      <D:status>HTTP/1.1 200 OK</D:status>');
    _emit('    </D:propstat>');
    _emit('  </D:response>');
  }

  /// Stream directory contents
  Stream<FileSystemEntity> streamDirectory(
    final Directory dir, {
    final int depth = 1,
  }) async* {
    if (depth == 0) return;

    await for (final entity in dir.list()) {
      yield entity;

      if (entity is Directory && depth > 1) {
        yield* streamDirectory(entity, depth: depth - 1);
      }
    }
  }

  void _emit(final String xml) {
    _controller.add(xml);
    _controller.add('\n');
  }

  String _escapeXml(final String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Create a streaming PROPFIND response
Stream<List<int>> createStreamingPropfind({
  required final Context base,
  required final Directory root,
  required final Directory dir,
  required final int depth,
  required final Future<Map<String, dynamic>> Function(String) getProps,
}) async* {
  final builder = XmlStreamBuilder();
  builder.start();

  await for (final xml in builder.stream) {
    yield utf8.encode(xml);
  }

  final baseHref = href(base, root, dir);
  final dirStat = await dir.stat();
  final dirModified = dirStat.modified;
  final dirProps = await getProps(dir.path);
  await builder.addDirectory(
    href: baseHref,
    modified: dirModified,
    custom: dirProps,
  );

  if (depth > 0) {
    await for (final entity in dir.list()) {
      final entityHref = href(base, root, entity);

      if (entity is File) {
        final stat = await entity.stat();
        final props = await getProps(entity.path);

        // Generate ETag
        final etag = '"${stat.size}-${stat.modified.millisecondsSinceEpoch}"';

        await builder.addFile(
          href: entityHref,
          size: stat.size,
          modified: stat.modified,
          etag: etag,
          custom: props,
        );
      } else if (entity is Directory && depth > 1) {
        yield* createStreamingPropfind(
          base: base,
          root: root,
          dir: entity,
          depth: depth - 1,
          getProps: getProps,
        );
      } else if (entity is Directory) {
        final stat = await entity.stat();
        final modified = stat.modified;
        final props = await getProps(entity.path);

        await builder.addDirectory(
          href: '$entityHref/',
          modified: modified,
          custom: props,
        );
      }
    }
  }

  builder.end();
}
