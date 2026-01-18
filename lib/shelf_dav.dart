import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_dav/src/dav_config.dart';
import 'package:shelf_dav/src/dav_resource.dart';
import 'package:shelf_dav/src/dav_utils.dart';
import 'package:shelf_dav/src/dav_directory_resource.dart';
import 'package:shelf_dav/src/dav_file_resource.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';
import 'package:shelf_dav/src/properties/memory_property_storage.dart';
import 'package:shelf_dav/src/properties/file_property_storage.dart';
import 'package:shelf_dav/src/locks/lock_storage.dart';
import 'package:shelf_dav/src/locks/memory_lock_storage.dart';
import 'package:shelf_dav/src/utils/throttle.dart';
import 'package:shelf_dav/src/auth/auth_providers.dart';
import 'package:shelf_dav/src/auth/auth_middleware.dart';
import 'package:shelf_dav/src/utils/stat_cache.dart';
import 'package:shelf_dav/src/utils/metrics.dart';
import 'package:shelf_dav/src/webdav_constants.dart';

export 'package:shelf_dav/src/dav_config.dart';
export 'package:shelf_dav/src/exceptions.dart';
export 'package:shelf_dav/src/properties/property_storage.dart';
export 'package:shelf_dav/src/properties/dbm_property_storage.dart';
export 'package:shelf_dav/src/locks/lock_storage.dart';
export 'package:shelf_dav/src/locks/memory_lock_storage.dart';
export 'package:shelf_dav/src/locks/dbm_lock_storage.dart';
export 'package:shelf_dav/src/multi_status.dart';
export 'package:shelf_dav/src/utils/throttle.dart';
export 'package:shelf_dav/src/auth/auth.dart';
export 'package:shelf_dav/src/auth/auth_providers.dart';
export 'package:shelf_dav/src/auth/auth_middleware.dart';
export 'package:shelf_dav/src/utils/metrics.dart';

class ShelfDAV {
  final Context _context;
  final Directory _root;
  final DAVConfig _config;
  final PropertyStorage _storage;
  final LockStorage? _locks;
  final ThrottleMiddleware? _throttle;
  final AuthMiddleware _auth;
  final Metrics _metrics;
  final Logger _logger = Logger('ShelfDAV');
  bool _closed = false;

  /// Create a WebDAV server with the specified prefix and root directory
  ShelfDAV(String prefix, Directory root)
      : _context = Context(style: Style.url, current: prefix),
        _root = root,
        _config = DAVConfig(prefix: prefix, root: root),
        _metrics = defaultMetrics,
        _storage = MemoryPropertyStorage(),
        _locks = null,
        _throttle = ThrottleMiddleware(const ThrottleConfig()),
        _auth = AuthMiddleware(
          authenticationProvider: const NoopAuthenticationProvider(),
          authorizationProvider: const AllowAllAuthorizationProvider(),
          prefix: prefix,
        );

  /// Create a WebDAV server with custom configuration
  ShelfDAV.withConfig(DAVConfig config)
      : _context = Context(style: Style.url, current: config.prefix),
        _root = config.root,
        _config = config,
        _storage = _createPropertyStorage(config),
        _locks = _createLockStorage(config),
        _throttle = config.enableThrottling
            ? ThrottleMiddleware(
                config.throttleConfig ??
                    ThrottleConfig(
                      maxConcurrentRequests:
                          config.maxConcurrentRequests ?? 100,
                    ),
              )
            : null,
        _auth = _createAuthMiddleware(config),
        _metrics = config.metrics ?? defaultMetrics;

  /// Get the current configuration
  DAVConfig get config => _config;

  /// Get the property storage
  PropertyStorage get storage => _storage;

  static PropertyStorage _createPropertyStorage(final DAVConfig config) {
    switch (config.propertyStorageType) {
      case PropertyStorageType.memory:
        return MemoryPropertyStorage();
      case PropertyStorageType.file:
        return FilePropertyStorage(config.root.fileSystem);
      case PropertyStorageType.custom:
        if (config.customPropertyStorage == null) {
          throw ArgumentError(
            'customPropertyStorage must be provided when using PropertyStorageType.custom',
          );
        }
        return config.customPropertyStorage!;
    }
  }

  static LockStorage? _createLockStorage(final DAVConfig config) {
    if (!config.enableLocking) return null;

    if (config.lockStorage != null) {
      return config.lockStorage;
    }

    // Default to memory storage
    return MemoryLockStorage();
  }

  static AuthMiddleware _createAuthMiddleware(final DAVConfig config) {
    // If no auth provider specified, check if anonymous access is allowed
    if (config.authenticationProvider == null) {
      if (config.allowAnonymous) {
        // Use NoAuthProvider for anonymous access
        return AuthMiddleware(
          authenticationProvider: const NoopAuthenticationProvider(),
          authorizationProvider: config.authorizationProvider ??
              const AllowAllAuthorizationProvider(),
          prefix: config.prefix,
        );
      }
      // No auth configured and anonymous not allowed - use DenyAllAuthProvider
      return AuthMiddleware(
        authenticationProvider: const DenyAllAuthProvider(),
        authorizationProvider: config.authorizationProvider ??
            const AllowAllAuthorizationProvider(),
        prefix: config.prefix,
      );
    }

    // Auth provider specified
    return AuthMiddleware(
      authenticationProvider: config.authenticationProvider!,
      authorizationProvider:
          config.authorizationProvider ?? const AllowAllAuthorizationProvider(),
      prefix: config.prefix,
    );
  }

  // By exposing a [Router] for an object, it can be mounted in other routers.
  Router get router {
    final router = Router();

    router.all('/<ignored|.*>', _handle);

    return router;
  }

  Handler get handler {
    Handler h = _handle;

    // Wrap with throttle middleware first (innermost)
    if (_throttle != null) {
      h = _throttle!.call(h);
    }

    // Then wrap with auth middleware (outermost)
    // Auth runs first to reject unauthorized requests before throttling
    h = _auth.call(h);

    return h;
  }

  /// Release resources associated with this ShelfDAV instance.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _storage.close();
    if (_locks != null) {
      await _locks!.close();
    }
    _throttle?.dispose();
  }

  // Method handlers map for Open/Closed Principle
  static final _methodHandlers = <String, Function(DavResource, Request)>{
    'DELETE': (resource, request) => resource.delete(request),
    'GET': (resource, request) => resource.get(request),
    'HEAD': (resource, request) => resource.head(request),
    'OPTIONS': (resource, request) => resource.options(request),
    'POST': (resource, request) => resource.post(request),
    'PUT': (resource, request) => resource.put(request),
    'TRACE': (resource, request) => resource.trace(request),
    'COPY': (resource, request) => resource.copy(request),
    'LOCK': (resource, request) => resource.lock(request),
    'MKCOL': (resource, request) => resource.mkcol(request),
    'MOVE': (resource, request) => resource.move(request),
    'PROPFIND': (resource, request) => resource.propfind(request),
    'PROPPATCH': (resource, request) => resource.proppatch(request),
    'UNLOCK': (resource, request) => resource.unlock(request),
  };

  Future<Response> _handle(Request request) async {
    final startTime = DateTime.now();
    final method = request.method;

    _logger.info('$method ${request.requestedUri}');

    // Record request
    _metrics.recordRequest(method);

    final fs = _root.fileSystem;

    // Create request-scoped stat cache
    final cache = StatCache(metrics: _metrics);
    request = request.change(
      context: {...request.context, ContextKeys.statCache: cache},
    );
    // Security: Check for path traversal before normalization
    final rawPath = Uri.decodeComponent(request.requestedUri.path);
    if (containsPathTraversal(rawPath)) {
      _logger.warning('Path traversal attempt detected in: $rawPath');
      return Response.forbidden('Access denied');
    }

    // Security: Verify path starts with our prefix
    // This catches paths like /dav/../ which normalize to / (outside prefix)
    if (!rawPath.startsWith(_context.current)) {
      _logger.warning(
        'Path outside WebDAV prefix: $rawPath (prefix: ${_context.current})',
      );
      return Response.forbidden('Access denied');
    }

    final uriPath = canonical(_context, request.requestedUri);
    final fsPath = local(fs, uriPath, rootPath: _root.path);
    _logger
        .info('context: ${_context.current} uriPath: $uriPath fsPath: $fsPath');

    // Security: Validate final path is within root directory
    if (!isPathWithinRoot(fs, fsPath, _root.path)) {
      _logger.warning(
        'Path traversal attempt: $fsPath outside root ${_root.path}',
      );
      return Response.forbidden('Access denied');
    }

    // Optimize: single stat call to determine resource type (with caching)
    DavResource resource;
    final entity = fs.file(fsPath);
    final stat = await cache.stat(entity);

    if (stat.type == FileSystemEntityType.file) {
      resource = DavFileResource(
        _context,
        _root,
        entity,
        _storage,
        _config,
        _locks,
      );
    } else if (stat.type == FileSystemEntityType.directory) {
      final dir = fs.directory(fsPath);
      resource = DavDirectoryResource(
        _context,
        _root,
        dir,
        _storage,
        _config,
        _locks,
      );
    } else {
      resource = DavResource(_context, _root, _storage, _config, _locks);
    }

    _logger.info('resource: $resource');

    // Dispatch using method handlers map
    final methodUpper = request.method.toUpperCase();
    final handler = _methodHandlers[methodUpper];

    if (handler == null) {
      final allowHeader = _methodHandlers.keys.join(', ');
      return Response(
        405,
        body: 'Method not allowed: ${request.method}',
        headers: {'Allow': allowHeader},
      );
    }

    try {
      final response = await handler(resource, request);

      // Record response time and errors
      final elapsed = DateTime.now().difference(startTime);
      _metrics.recordResponseTime(method, elapsed);

      if (response.statusCode >= 400) {
        _metrics.recordError(method, response.statusCode);
      }

      return response;
    } catch (e) {
      // Record unexpected errors
      _metrics.recordError(method, 500);
      rethrow;
    }
  }
}
