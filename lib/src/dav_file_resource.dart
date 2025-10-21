import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:mime_type/mime_type.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/dav_resource.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'package:shelf_dav/src/utils/etag.dart';
import 'package:shelf_dav/src/utils/http_status.dart';
import 'package:shelf_dav/src/locks/lock_validation.dart';
import 'package:shelf_dav/src/utils/propfind_utils.dart';
import 'package:shelf_dav/src/utils/validation_utils.dart';
import 'package:shelf_dav/src/utils/range.dart';
import 'package:xml/xml.dart';

import 'dav_utils.dart';
import 'utils/file_utils.dart'
    show UploadSizeLimitExceededException, writeToFile;

class DavFileResource extends DavResource {
  final File _file;
  final Logger _logger = Logger('FileResource');

  /// Note that if this constructor is called,then the file exists.
  DavFileResource(
    super.context,
    super.root,
    this._file,
    super.storage, [
    super.config,
    super.locks,
  ]);

  @override
  Future<Response> copy(Request request) async {
    _logger.info('COPY(${request.url})');

    try {
      ensureWritable();
      await ensureUnlocked(
        locks: locks,
        path: _file.path,
        headers: request.headers,
      );

      final prepare = await prepareCopyMoveOperation(
        request,
        _file.path,
        (fs, path) => fs.file(path),
      );
      final target = prepare.target as File;

      _logger.finer(
        'from: ${_file.path} to: ${prepare.headers.destination} overwrite: ${prepare.headers.overwrite}',
      );

      // Perform file copy
      if (!prepare.exists) {
        await target.create(recursive: true);
      }
      await _file.copy(target.path);
      await storage.copyProperties(_file.path, target.path);

      return buildCopyMoveResponse(
        destinationExisted: prepare.exists,
        target: target,
        destinationUri: prepare.headers.destination,
      );
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> delete(Request request) async {
    _logger.info('DELETE(${request.url})');

    try {
      ensureWritable();
      await ensureUnlocked(
        locks: locks,
        path: _file.path,
        headers: request.headers,
      );

      if (await _file.exists()) {
        await _file.delete();
        await storage.removeAllProperties(_file.path);
        return Response(HttpStatus.noContent, body: 'No content');
      }
      return Response.notFound('${request.url}');
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> get(Request request) async {
    _logger.info('GET(${request.url})');

    try {
      final metadata = await getMetadataAndETag(_file);
      ensureETagPreconditions(
        etag: metadata.etag,
        headers: request.headers,
      );

      final contentType = mime(_file.path) ?? 'application/octet-stream';

      // Check for Range request
      final range = parseRange(request.headers['range']);
      if (range != null) {
        // Validate range
        if (!range.isValid(metadata.length)) {
          return Response(
            HttpStatus.requestedRangeNotSatisfiable,
            body: 'Invalid range',
            headers: {
              'Content-Range': 'bytes */${metadata.length}',
              'Content-Type': contentType,
            },
          );
        }

        final start = range.start;
        final end = range.getEnd(metadata.length);
        final length = range.getLength(metadata.length);

        _logger.fine('Range request: bytes $start-$end/${metadata.length}');

        // Stream only the requested range
        final stream = createRangeStream(_file.openRead(), start, end);

        return Response(
          HttpStatus.partialContent,
          body: stream,
          headers: {
            'Content-Type': contentType,
            'Content-Length': length.toString(),
            'Content-Range': 'bytes $start-$end/${metadata.length}',
            'Accept-Ranges': 'bytes',
            'ETag': metadata.etag,
            'Last-Modified': buildMetadataHeaders(
              etag: metadata.etag,
              modified: metadata.modified,
            )['Last-Modified']!,
          },
        );
      }

      // No Range request - return full file
      final stream = _file.openRead();
      return Response.ok(
        stream,
        headers: {
          ...buildMetadataHeaders(
            etag: metadata.etag,
            modified: metadata.modified,
            length: metadata.length,
            contentType: contentType,
          ),
          'Accept-Ranges': 'bytes',
        },
      );
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> head(Request request) async {
    _logger.info('HEAD(${request.url})');

    try {
      final metadata = await getMetadataAndETag(_file);
      ensureETagPreconditions(
        etag: metadata.etag,
        headers: request.headers,
      );

      return Response.ok(
        '',
        headers: {
          ...buildMetadataHeaders(
            etag: metadata.etag,
            modified: metadata.modified,
            length: metadata.length,
            contentType: mime(_file.path) ?? 'application/octet-stream',
          ),
          'Accept-Ranges': 'bytes',
        },
      );
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> move(Request request) async {
    _logger.info('MOVE(${request.url})');

    try {
      ensureWritable();
      await ensureUnlocked(
        locks: locks,
        path: _file.path,
        headers: request.headers,
      );

      final prepare = await prepareCopyMoveOperation(
        request,
        _file.path,
        (fs, path) => fs.file(path),
      );
      final target = prepare.target as File;

      _logger.finer(
        'from: ${_file.path} to: ${prepare.headers.destination} overwrite: ${prepare.headers.overwrite}',
      );

      // Try atomic rename first, fall back to copy+delete
      try {
        await _file.rename(target.path);
        _logger.fine('Used atomic rename');
      } on FileSystemException {
        _logger.fine('Falling back to copy+delete (rename failed)');
        if (!prepare.exists) {
          await target.create(recursive: true);
        }
        await _file.copy(target.path);
        await _file.delete();
      }

      await storage.moveProperties(_file.path, target.path);

      return buildCopyMoveResponse(
        destinationExisted: prepare.exists,
        target: target,
        destinationUri: prepare.headers.destination,
      );
    } on DavValidationException catch (e) {
      return e.response;
    } on FileSystemException catch (e) {
      _logger.warning('MOVE failed - FileSystemException: $e');
      return Response(
        HttpStatus.forbidden,
        body: 'Permission denied or filesystem error: ${e.message}',
      );
    } catch (e) {
      _logger.warning('MOVE failed: $e');
      return Response(
        HttpStatus.internalServerError,
        body: 'Move operation failed: $e',
      );
    }
  }

  @override
  Future<Response> propfind(Request request) async {
    _logger.info('PROPFIND(${request.url})');

    final properties = await storage.getProperties(_file.path);
    final custom = <String, dynamic>{};
    for (final prop in properties.values) {
      custom[prop.name] = prop.value;
    }

    final response = XmlBuilder()..namespace('DAV:', 'D');

    await file(
      response,
      super.base,
      root,
      _file,
      customProperties: custom,
    );

    return buildPropfindResponse(response);
  }

  @override
  Future<Response> proppatch(Request request) async {
    _logger.info('PROPPATCH(${request.url})');

    try {
      ensureWritable();
      return handleProppatch(request, _file.path);
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> put(Request request) async {
    _logger.info('PUT(${request.url})');

    try {
      ensureWritable();
      await ensureUnlocked(
        locks: locks,
        path: _file.path,
        headers: request.headers,
      );

      ValidationUtils.ensureUploadSize(request, config);
      final maxSize = ValidationUtils.getUploadLimit(config);

      if (request.headers['If-None-Match'] == '*') {
        return Response(
          HttpStatus.preconditionFailed,
          body: 'Resource must exist for update',
        );
      }

      if (await _file.exists()) {
        final metadata = await getMetadataAndETag(_file);

        if (!validateIfMatch(metadata.etag, request.headers['If-Match'])) {
          return Response(
            HttpStatus.preconditionFailed,
            body: 'ETag does not match - file has been modified',
          );
        }
      }

      // writeToFile enforces maxSize during streaming to prevent OOM attacks
      await writeToFile(_file, maxSize, request.read());

      final metadata = await getMetadataAndETag(_file);

      return Response(
        HttpStatus.ok,
        body: 'Resource replaced',
        headers: buildMetadataHeaders(
          etag: metadata.etag,
          modified: metadata.modified,
        ),
      );
    } on DavValidationException catch (e) {
      return e.response;
    } on UploadSizeLimitExceededException catch (e) {
      _logger.warning('Upload size limit exceeded: $e');
      return Response(HttpStatus.requestEntityTooLarge, body: e.toString());
    } catch (e) {
      _logger.warning('PUT failed: $e');
      return Response(HttpStatus.internalServerError, body: e.toString());
    }
  }
}
