import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/dav_config.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';
import 'package:shelf_dav/src/utils/http_status.dart';
import 'package:shelf_dav/src/locks/lock_storage.dart';
import 'package:shelf_dav/src/locks/lock_parser.dart';
import 'package:shelf_dav/src/locks/lock_validation.dart';
import 'package:shelf_dav/src/proppatch_parser.dart';
import 'package:shelf_dav/src/dav_utils.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'package:shelf_dav/src/utils/propfind_utils.dart';
import 'package:shelf_dav/src/utils/etag.dart';
import 'package:shelf_dav/src/utils/file_utils.dart'
    show UploadSizeLimitExceededException, writeToFile;
import 'package:shelf_dav/src/utils/validation.dart';
import 'package:shelf_dav/src/utils/validation_utils.dart';
import 'package:xml/xml.dart';

// WebDAV makes nothing easy...
class DavResource {
  final Logger _logger = Logger('DavResource');
  final Directory _root;
  final Context _base;
  final PropertyStorage _storage;
  final DAVConfig? _config;
  final LockStorage? _locks;

  /// This is called in all cases, but the methods in this class will only be
  /// called when a file or directory is missing
  DavResource(
    this._base,
    this._root,
    this._storage, [
    this._config,
    this._locks,
  ]);

  FileSystem get filesystem => _root.fileSystem;

  Directory get root => _root;

  Context get base => _base;

  PropertyStorage get storage => _storage;

  DAVConfig? get config => _config;

  LockStorage? get locks => _locks;

  /// Ensure server is not in read-only mode
  /// Throws ReadOnlyException if server is read-only
  void ensureWritable() {
    if (config?.readOnly == true) {
      throw ReadOnlyException();
    }
  }

  /// Check if server is in read-only mode
  /// Returns Response? for backward compatibility, or null if not read-only
  /// @deprecated Use ensureWritable() instead for consistent exception-based validation
  @Deprecated('Use ensureWritable() instead')
  Response? isReadOnly() {
    if (config?.readOnly == true) {
      return Response(
        HttpStatus.forbidden,
        body: 'Server is in read-only mode',
      );
    }
    return null;
  }

  /// Returns validation result with error if read-only, success otherwise
  /// @deprecated Use ensureWritable() instead for consistent exception-based validation
  @Deprecated('Use ensureWritable() instead')
  ValidationResult validateReadOnly() {
    if (config?.readOnly == true) {
      return failure(
        Response(
          HttpStatus.forbidden,
          body: 'Server is in read-only mode',
        ),
      );
    }
    return success();
  }

  /// Implements DELETE per RFC 4918 §9.6.
  /// Deletes the resource and all members (collections act as Depth: infinity).
  /// Returns 207 Multi-Status on partial failures to maintain namespace consistency.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.6
  Future<Response> delete(Request request) async =>
      Response.notFound('Resource does not exist');

  /// Implements GET per RFC 2616 §9.3.
  /// Retrieves the resource representation.
  /// See: https://datatracker.ietf.org/doc/html/rfc2616#section-9.3
  Future<Response> get(Request request) async =>
      Response.notFound('Resource does not exist');

  /// Implements HEAD per RFC 2616 §9.4.
  /// Returns metadata headers without message body.
  /// See: https://datatracker.ietf.org/doc/html/rfc2616#section-9.4
  Future<Response> head(Request request) async =>
      Response.notFound('Resource does not exist');

  /// Implements OPTIONS per RFC 2616 §9.2.
  /// Returns communication options (DAV compliance level, allowed methods).
  /// See: https://datatracker.ietf.org/doc/html/rfc2616#section-9.2
  Future<Response> options(Request request) async {
    _logger.info('options(${request.url})');
    return Response(
      200,
      headers: {
        'DAV': '1,2',
        'MS-Author-Via': 'DAV',
        'Allow':
            'GET, HEAD, PUT, DELETE, OPTIONS, PROPFIND, PROPPATCH, COPY, MOVE, LOCK, UNLOCK',
      },
    );
  }

  Future<Response> post(Request request) async =>
      Response(HttpStatus.notImplemented);

  Future<Response> put(Request request) async {
    _logger.info("put(${request.url})");

    try {
      ensureWritable();

      // PUT on non-existent resource creates a new file
      // Get the file path from the request
      final uri = canonical(_base, request.requestedUri);
      final path = local(root.fileSystem, uri, rootPath: root.path);

      // Check if path refers to a directory (ends with / or is an existing directory)
      if (request.requestedUri.path.endsWith('/')) {
        return Response(
          HttpStatus.conflict,
          body: 'Cannot PUT to a collection (directory path)',
        );
      }

      // Check if it's an existing directory
      final dir = root.fileSystem.directory(path);
      if (await dir.exists()) {
        return Response(
          HttpStatus.methodNotAllowed,
          body: 'Cannot PUT to an existing collection',
        );
      }

      final file = root.fileSystem.file(path);
      await ensureParentExists(file);

      await ensureUnlocked(
        locks: locks,
        path: path,
        headers: request.headers,
      );

      ValidationUtils.ensureUploadSize(request, config);
      final maxSize = ValidationUtils.getUploadLimit(config);

      // Check If-None-Match: * (only create if doesn't exist)
      if (request.headers['If-None-Match'] == '*') {
        if (await file.exists()) {
          return Response(412, body: 'Resource already exists');
        }
      }

      // Write request body to file
      await writeToFile(file, maxSize, request.read());

      final metadata = await getMetadataAndETag(file);
      return Response(
        HttpStatus.created,
        body: 'Created',
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

  Future<Response> trace(Request request) async =>
      Response(HttpStatus.notImplemented);

  // WebDAV extensions
  /// Implements COPY per RFC 4918 §9.8.
  /// Duplicates resource to Destination header URI. Collections support Depth 0 or infinity.
  /// Returns 207 Multi-Status on partial failures for collections.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.8
  Future<Response> copy(Request request) async =>
      Response(HttpStatus.notImplemented);

  /// Implements LOCK per RFC 4918 §9.10.
  /// Creates exclusive/shared write locks. Supports null-resource locks and lock refresh.
  /// Returns Lock-Token header for new locks. Locks may expire per Timeout header.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.10
  Future<Response> lock(Request request) async {
    _logger.info('lock(${request.url})');

    try {
      ensureWritable();

      // Check if locking is enabled
      if (locks == null) {
        return Response(
          HttpStatus.methodNotAllowed,
          body: 'Locking not supported',
        );
      }

      try {
        final body = await request.readAsString();
        final hasBody = body.trim().isNotEmpty;
        final uri = canonical(_base, request.requestedUri);
        final path = local(root.fileSystem, uri, rootPath: root.path);
        final timeout = LockParser.parseTimeout(request.headers['Timeout']);

        if (!hasBody) {
          final token = extractToken(request.headers);
          if (token == null) {
            return Response(
              HttpStatus.badRequest,
              body: 'LOCK refresh requires lock token',
            );
          }

          final refreshed = await locks!.refreshLock(token, timeout);
          if (refreshed == null || !_lockCoversPath(refreshed, path)) {
            return Response(
              HttpStatus.preconditionFailed,
              body: 'Lock token not found or does not cover resource',
            );
          }

          final xml =
              LockParser.generateLockDiscovery(refreshed, request.url.path);

          return Response(
            200,
            body: xml,
            headers: {
              'Content-Type': 'application/xml; charset=utf-8',
              'Lock-Token': '<${refreshed.token}>',
            },
          );
        }

        final doc = XmlDocument.parse(body);
        final scope = LockParser.parseScope(doc) ?? LockScope.exclusive;
        final type = LockParser.parseType(doc) ?? LockType.write;
        final owner = LockParser.parseOwner(doc);
        final depth = parseDepth(request.headers['Depth']) ?? 0;

        // Note: WebDAV RFC 4918 Section 7.3 allows locking non-existent resources
        // These are called "null-resource locks" and reserve the name for future creation
        final lock = await locks!.createLock(
          path: path,
          scope: scope,
          type: type,
          owner: owner,
          timeout: timeout,
          depth: depth,
        );

        if (lock == null) {
          return Response(423, body: 'Resource is locked');
        }

        try {
          final xml = LockParser.generateLockDiscovery(lock, request.url.path);

          return Response(
            200,
            body: xml,
            headers: {
              'Content-Type': 'application/xml; charset=utf-8',
              'Lock-Token': '<${lock.token}>',
            },
          );
        } catch (e) {
          _logger
              .warning('LOCK response generation failed, cleaning up lock: $e');
          await locks!.removeLock(lock.token);
          rethrow;
        }
      } catch (e) {
        _logger.warning('LOCK failed: $e');
        return Response(
          HttpStatus.badRequest,
          body: 'Invalid LOCK request: $e',
        );
      }
    } on DavValidationException catch (e) {
      return e.response;
    }
  }

  bool _lockCoversPath(final DavLock lock, final String path) {
    if (lock.path == path) {
      return true;
    }
    if (lock.depth == 0) {
      return false;
    }

    final separator = root.fileSystem.path.separator;
    final normalized =
        lock.path.endsWith(separator) ? lock.path : '${lock.path}$separator';
    return path.startsWith(normalized);
  }

  /// Implements MKCOL per RFC 4918 §9.3.
  /// Creates new collection. Parent collection must exist (returns 409 if not).
  /// Returns 405 if resource already exists at URI.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.3
  Future<Response> mkcol(Request request) async {
    _logger.info('mkcol(${request.url})');

    try {
      ensureWritable();

      // Get the directory path from the request
      final uri = canonical(_base, request.requestedUri);
      final path = local(root.fileSystem, uri, rootPath: root.path);
      final dir = root.fileSystem.directory(path);

      await ensureParentExists(dir);

      await dir.create(recursive: false);
      // Return absolute URI in Location header per RFC 4918
      final location = request.requestedUri.toString();
      return Response(HttpStatus.created, headers: {'Location': location});
    } on DavValidationException catch (e) {
      return e.response;
    } catch (e) {
      _logger.warning('MKCOL failed: $e');
      return Response(
        HttpStatus.methodNotAllowed,
        body: 'Failed to create collection',
      );
    }
  }

  /// Implements MOVE per RFC 4918 §9.9.
  /// Atomically moves resource to Destination URI (copy + delete). Collections act as Depth: infinity.
  /// Returns 207 Multi-Status on partial failures. Properties move with resource.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.9
  Future<Response> move(Request request) async =>
      Response(HttpStatus.notImplemented);

  /// Implements PROPFIND per RFC 4918 §9.1.
  /// Retrieves properties for resource and members (supports Depth 0, 1, infinity).
  /// Returns 207 Multi-Status with property values or errors.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.1
  Future<Response> propfind(Request request) async =>
      Response.notFound('Resource does not exist');

  /// Centralized PROPPATCH handler to avoid code duplication
  /// Can be called by FileResource and DirectoryResource
  Future<Response> handleProppatch(
    final Request request,
    final String resourcePath,
  ) async {
    _logger.info("handleProppatch($resourcePath)");

    try {
      ensureWritable();
      final body = await request.readAsString();
      if (body.isEmpty) {
        return Response(HttpStatus.badRequest, body: 'Empty request body');
      }

      // Parse PROPPATCH operations
      final operations = PropPatchParser.parse(body);
      if (operations.isEmpty) {
        return Response(
          HttpStatus.badRequest,
          body: 'Invalid PROPPATCH request',
        );
      }

      // Execute operations and collect results
      final results = <PropertyOperationResult>[];
      for (final op in operations) {
        try {
          if (op.isSet) {
            // Set property
            final property = DavProperty(
              namespace: op.namespace,
              name: op.name,
              value: op.value ?? '',
            );
            final success = await _storage.setProperty(
              resourcePath,
              property,
            );
            results.add(
              success
                  ? PropertyOperationResult.success(op.namespace, op.name)
                  : PropertyOperationResult.failure(
                      op.namespace,
                      op.name,
                      500,
                      'Failed to set property',
                    ),
            );
          } else {
            final success = await _storage.removeProperty(
              resourcePath,
              op.namespace,
              op.name,
            );
            results.add(
              success
                  ? PropertyOperationResult.success(op.namespace, op.name)
                  : PropertyOperationResult.failure(
                      op.namespace,
                      op.name,
                      404,
                      'Property not found',
                    ),
            );
          }
        } catch (e) {
          _logger.warning('Property operation failed: $e');
          results.add(
            PropertyOperationResult.failure(
              op.namespace,
              op.name,
              500,
              'Operation failed: $e',
            ),
          );
        }
      }

      // Generate 207 Multi-Status response
      final href = request.requestedUri.path;
      final result = PropPatchParser.generateMultiStatusResponse(
        href,
        results,
      );

      return Response(
        207,
        body: result,
        headers: {'Content-Type': 'application/xml; charset=utf-8'},
      );
    } on DavValidationException catch (e) {
      return e.response;
    } catch (e) {
      _logger.warning('PROPPATCH failed: $e');
      return Response(
        HttpStatus.internalServerError,
        body: 'PROPPATCH failed: $e',
      );
    }
  }

  /// Build successful COPY/MOVE response.
  /// Returns 201 Created if destination was new, 204 No Content if replaced existing.
  /// For file resources, includes ETag and modified headers.
  Future<Response> buildCopyMoveResponse({
    required final bool destinationExisted,
    required final FileSystemEntity target,
    required final Uri destinationUri,
  }) async {
    if (destinationExisted) {
      return Response(HttpStatus.noContent, body: 'Resource replaced');
    }

    // For files, include metadata in response
    if (target is File) {
      final metadata = await getMetadataAndETag(target);
      return Response(
        HttpStatus.created,
        body: 'Created',
        headers: buildMetadataHeaders(
          etag: metadata.etag,
          modified: metadata.modified,
          location: '$destinationUri',
        ),
      );
    }

    // For directories, simple 201 Created
    return Response(HttpStatus.created, body: 'Created');
  }

  /// Shared preparation logic for COPY and MOVE operations.
  ///
  /// Parses headers, resolves destination paths, validates overwrite rules,
  /// and ensures the destination parent exists.
  Future<
      ({
        CopyMoveHeaders headers,
        String uri,
        String path,
        bool exists,
        FileSystemEntity target,
      })> prepareCopyMoveOperation(
    final Request request,
    final String source,
    final FileSystemEntity Function(FileSystem fs, String path) builder,
  ) async {
    final headers = parseCopyMoveHeadersOrThrow(
      request.headers,
      uri: request.requestedUri,
      prefix: _base.current,
    );

    final fs = root.fileSystem;
    final uri = canonical(_base, headers.destination);
    final path = local(fs, uri, rootPath: root.path);
    final target = builder(fs, path);
    final exists = await target.exists();

    ensureCopyMove(
      uri: headers.destination,
      source: source,
      destination: path,
      exists: exists,
      overwrite: headers.overwrite,
    );

    await ensureParentExists(target);

    return (
      headers: headers,
      uri: uri,
      path: path,
      exists: exists,
      target: target,
    );
  }

  /// Implements PROPPATCH per RFC 4918 §9.2.
  /// Sets/removes properties atomically (all-or-nothing). Returns 207 Multi-Status.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.2
  Future<Response> proppatch(Request request) async =>
      Response.notFound('Resource does not exist');

  /// Implements UNLOCK per RFC 4918 §9.11.
  /// Removes lock identified by Lock-Token header. All locked resources must unlock atomically.
  /// See: https://datatracker.ietf.org/doc/html/rfc4918#section-9.11
  Future<Response> unlock(Request request) async {
    _logger.info('unlock(${request.url})');

    // Check if locking is enabled
    if (locks == null) {
      return Response(
        HttpStatus.methodNotAllowed,
        body: 'Locking not supported',
      );
    }

    // Get lock token from header (format: <opaquelocktoken:...>)
    final header = request.headers['Lock-Token'];
    if (header == null || header.isEmpty) {
      return Response(HttpStatus.badRequest, body: 'Missing Lock-Token header');
    }

    // Remove angle brackets from token
    var token = header.trim();
    if (token.startsWith('<') && token.endsWith('>')) {
      token = token.substring(1, token.length - 1);
    }

    // Verify lock exists
    final lock = await locks!.getLock(token);
    if (lock == null) {
      return Response(
        HttpStatus.conflict,
        body: 'Lock token not found or invalid',
      );
    }

    // Remove lock
    final removed = await locks!.removeLock(token);
    if (!removed) {
      return Response(
        HttpStatus.internalServerError,
        body: 'Failed to remove lock',
      );
    }

    return Response(HttpStatus.noContent, body: 'No Content');
  }
}
