import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/dav_resource.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'package:shelf_dav/src/utils/http_status.dart';
import 'package:shelf_dav/src/locks/lock_validation.dart';
import 'package:shelf_dav/src/multi_status.dart';
import 'package:shelf_dav/src/utils/propfind_utils.dart';
import 'package:shelf_dav/src/webdav_constants.dart';
import 'package:xml/xml.dart';

import 'dav_utils.dart';

// This class is a good example of why WebDAV is a pretty terrible protocol...
class DavDirectoryResource extends DavResource {
  final Directory _dir;
  final Logger _logger = Logger('DirectoryResource');

  /// Note that if this constructor is called then the directory exists.
  DavDirectoryResource(
    super.context,
    super.root,
    this._dir,
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
        path: _dir.path,
        headers: request.headers,
      );

      final prepare = await prepareCopyMoveOperation(
        request,
        _dir.path,
        (fs, path) => fs.directory(path),
      );
      final headers = prepare.headers;
      final target = prepare.target as Directory;

      _logger.finer(
        'from: ${_dir.path} to: ${headers.destination} depth: ${headers.depth} overwrite: ${headers.overwrite}',
      );

      // RFC 4918: Depth must be 0 or infinity for COPY on collections
      if (headers.depth != 0 && headers.depth != WebDAVConstants.infinity) {
        return Response(
          HttpStatus.badRequest,
          body:
              'Invalid Depth header for COPY on collection. Must be 0 or infinity.',
        );
      }

      try {
        if (prepare.exists) {
          await target.delete(recursive: true);
        }
        await target.create(recursive: true);

        if (headers.depth == 0) {
          _logger.fine('Depth 0: copying directory only');
          await storage.copyProperties(_dir.path, target.path);
        } else {
          _logger.fine('Depth infinity: copying recursively');
          final status = MultiStatusBuilder();

          final success = await _copyDirectoryWithTracking(
            _dir,
            target,
            headers.destination.path,
            status,
          );

          if (!success) {
            return Response(
              HttpStatus.multiStatus,
              body: status.build(),
              headers: {'Content-Type': 'application/xml; charset=utf-8'},
            );
          }
        }

        return Response(HttpStatus.created, body: 'Collection copied');
      } catch (e) {
        _logger.warning('COPY failed: $e');
        return Response(
          HttpStatus.internalServerError,
          body: 'Copy operation failed: $e',
        );
      }
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  @override
  Future<Response> delete(Request request) async {
    _logger.info('DELETE(${request.url})');

    try {
      ensureWritable();

      if (_dir.path == root.path) {
        return Response(
          HttpStatus.forbidden,
          body: 'Cannot delete the WebDAV root collection',
        );
      }

      await ensureUnlocked(
        locks: locks,
        path: _dir.path,
        headers: request.headers,
      );

      // Per RFC 4918: DELETE on collection MUST act as if Depth: infinity
      final status = MultiStatusBuilder();
      final href = request.requestedUri.path;

      await _deleteRecursive(_dir, href, status);

      if (status.hasFailures) {
        _logger.warning('DELETE had ${status.count} failures');
        return Response(
          HttpStatus.multiStatus,
          body: status.build(),
          headers: {'Content-Type': 'application/xml; charset=utf-8'},
        );
      }

      return Response(HttpStatus.noContent, body: 'Collection deleted');
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  /// Recursively delete directory contents, tracking failures
  Future<bool> _deleteRecursive(
    final Directory dir,
    final String base,
    final MultiStatusBuilder status,
  ) async {
    try {
      final entities = await dir.list(recursive: false).toList();
      var allSucceeded = true;

      for (final entity in entities) {
        final path = entity.path.substring(dir.path.length);
        final href = '$base$path';

        try {
          if (entity is File) {
            await entity.delete();
            await storage.removeAllProperties(entity.path);
            // Don't add to multiStatus for individual successes to keep response small
          } else if (entity is Directory) {
            final success = await _deleteRecursive(
              entity,
              '$href/',
              status,
            );
            if (!success) {
              allSucceeded = false;
            }
          }
        } catch (e) {
          _logger.warning('Failed to delete $href: $e');
          status.addFailure(
            href,
            403,
            error: 'Failed to delete: $e',
          );
          allSucceeded = false;
        }
      }

      if (allSucceeded) {
        try {
          await dir.delete();
          await storage.removeAllProperties(dir.path);
          return true;
        } catch (e) {
          _logger.warning('Failed to delete directory ${dir.path}: $e');
          status.addFailure(
            base,
            403,
            error: 'Failed to delete directory: $e',
          );
          return false;
        }
      }

      return false;
    } catch (e) {
      _logger.warning('Error during recursive delete: $e');
      status.addFailure(
        base,
        500,
        error: 'Internal error: $e',
      );
      return false;
    }
  }

  @override
  Future<Response> get(Request request) async {
    _logger.info('GET(${request.url})');
    return Response.ok('');
  }

  @override
  Future<Response> head(Request request) async {
    _logger.info('HEAD(${request.url})');
    return Response.ok('');
  }

  @override
  Future<Response> move(Request request) async {
    _logger.info('MOVE(${request.url})');

    try {
      ensureWritable();
      await ensureUnlocked(
        locks: locks,
        path: _dir.path,
        headers: request.headers,
      );

      final prepare = await prepareCopyMoveOperation(
        request,
        _dir.path,
        (fs, path) => fs.directory(path),
      );
      final target = prepare.target as Directory;

      _logger.finer(
        'from: ${_dir.path} to: ${prepare.headers.destination} overwrite: ${prepare.headers.overwrite}',
      );

      try {
        if (prepare.exists) {
          await target.delete(recursive: true);
        }

        // Try atomic rename first
        try {
          await _dir.rename(target.path);
          _logger.fine('Used atomic rename');
          await storage.moveProperties(_dir.path, target.path);
          return Response(HttpStatus.created, body: 'Collection moved');
        } on FileSystemException {
          // Fall back to copy+delete with failure tracking
          _logger.fine('Falling back to copy+delete (rename failed)');

          final status = MultiStatusBuilder();

          await target.create(recursive: true);
          final copied = await _copyDirectoryWithTracking(
            _dir,
            target,
            prepare.headers.destination.path,
            status,
          );

          if (!copied) {
            return Response(
              HttpStatus.multiStatus,
              body: status.build(),
              headers: {'Content-Type': 'application/xml; charset=utf-8'},
            );
          }

          // Copy succeeded, delete source
          final deleted = await _deleteRecursive(
            _dir,
            request.requestedUri.path,
            status,
          );

          if (!deleted) {
            return Response(
              HttpStatus.multiStatus,
              body: status.build(),
              headers: {'Content-Type': 'application/xml; charset=utf-8'},
            );
          }

          await storage.moveProperties(_dir.path, target.path);
          return Response(HttpStatus.created, body: 'Collection moved');
        }
      } catch (e) {
        _logger.warning('MOVE failed: $e');
        return Response(
          HttpStatus.internalServerError,
          body: 'Move operation failed: $e',
        );
      }
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  Future<bool> _copyDirectoryWithTracking(
    final Directory source,
    final Directory destination,
    final String base,
    final MultiStatusBuilder status,
  ) async {
    try {
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }
      await storage.copyProperties(source.path, destination.path);

      final entities = await source.list(recursive: false).toList();
      var allSucceeded = true;

      for (final entity in entities) {
        final path = entity.basename;
        final href = '$base$path';

        try {
          if (entity is File) {
            final target =
                destination.fileSystem.file('${destination.path}/$path');
            await entity.copy(target.path);
            await storage.copyProperties(entity.path, target.path);
          } else if (entity is Directory) {
            final target =
                destination.fileSystem.directory('${destination.path}/$path');
            final childSuccess = await _copyDirectoryWithTracking(
              entity,
              target,
              '$href/',
              status,
            );
            if (!childSuccess) {
              allSucceeded = false;
            }
          }
        } catch (e) {
          _logger.warning('Failed to copy $href: $e');
          status.addFailure(
            href,
            403,
            error: 'Failed to copy: $e',
          );
          allSucceeded = false;
          // Continue with other files per RFC 4918
        }
      }

      return allSucceeded;
    } catch (e) {
      _logger.warning('Error during copy: $e');
      status.addFailure(
        base,
        500,
        error: 'Internal error: $e',
      );
      return false;
    }
  }

  @override
  Future<Response> propfind(Request request) async {
    _logger.info('PROPFIND(${request.url})');
    final responses = XmlBuilder()..namespace('DAV:', 'D');

    // Per RFC 4918, PROPFIND defaults to infinity when no Depth header is provided
    await directory(
      responses,
      super.base,
      root,
      _dir,
      true,
      depth(request.headers['Depth'], defaultValue: WebDAVConstants.infinity),
    );

    return buildPropfindResponse(responses);
  }

  @override
  Future<Response> proppatch(Request request) async {
    _logger.info('PROPPATCH(${request.url})');

    try {
      ensureWritable();
      return handleProppatch(request, _dir.path);
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  /// MKCOL on existing collection returns 405 per RFC 4918
  @override
  Future<Response> mkcol(Request request) async {
    _logger.info('MKCOL(${request.url})');
    // Per RFC 4918: MKCOL on an existing collection is not allowed
    return Response(
      HttpStatus.methodNotAllowed,
      body: 'Collection already exists',
    );
  }
}
