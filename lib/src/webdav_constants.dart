/// WebDAV-specific constants
///
/// Provides constants for WebDAV operations and limits.
class WebDAVConstants {
  /// Maximum depth for recursive operations
  ///
  /// Prevents stack overflow in deeply nested directory structures.
  /// Per RFC 4918, "infinity" is valid but we limit it for safety.
  static const maxDepth = 10;

  /// Infinity constant for depth header
  ///
  /// RFC 4918 defines "infinity" for unlimited depth.
  /// Represented as max 32-bit signed integer.
  static const infinity = 0x7fffffff;

  /// Default namespace for DAV properties
  static const davNamespace = 'DAV:';

  /// Common WebDAV headers
  static const depthHeader = 'Depth';
  static const destinationHeader = 'Destination';
  static const overwriteHeader = 'Overwrite';
  static const ifHeader = 'If';
  static const lockTokenHeader = 'Lock-Token';
  static const timeoutHeader = 'Timeout';

  // Private constructor to prevent instantiation
  WebDAVConstants._();
}

/// Context key constants for Shelf request context
class ContextKeys {
  /// Key for stat cache in request context
  static const statCache = 'stat_cache';

  /// Key for authenticated user in request context
  static const authUser = 'auth_user';

  /// Key for connection info (Shelf standard)
  static const connectionInfo = 'shelf.io.connection_info';

  // Private constructor to prevent instantiation
  ContextKeys._();
}
