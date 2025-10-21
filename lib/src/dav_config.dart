import 'package:file/file.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';
import 'package:shelf_dav/src/locks/lock_storage.dart';
import 'package:shelf_dav/src/utils/throttle.dart';
import 'package:shelf_dav/src/auth/auth.dart';
import 'package:shelf_dav/src/utils/metrics.dart';

/// Property storage backend type
enum PropertyStorageType {
  /// Store properties in memory (lost on restart)
  memory,

  /// Store properties in hidden files next to resources
  file,

  /// Custom storage implementation
  custom,
}

/// Configuration options for ShelfDAV server
class DAVConfig {
  /// The root directory to serve
  final Directory root;

  /// The URL prefix for the WebDAV server
  final String prefix;

  /// Whether to allow anonymous access (no authentication required)
  final bool allowAnonymous;

  /// Maximum number of concurrent requests to process
  /// If null, no limit is imposed
  final int? maxConcurrentRequests;

  /// Maximum upload size in bytes
  /// If null, no limit is imposed
  final int? maxUploadSize;

  /// Whether locking is enabled (LOCK/UNLOCK operations)
  final bool enableLocking;

  /// Custom lock storage implementation
  /// If null and enableLocking is true, uses MemoryLockStorage
  final LockStorage? lockStorage;

  /// Whether the server is read-only (no PUT, DELETE, MOVE, COPY, MKCOL)
  final bool readOnly;

  /// Whether to log detailed debug information
  final bool verbose;

  /// Property storage backend type
  final PropertyStorageType propertyStorageType;

  /// Custom property storage implementation
  /// Only used when propertyStorageType is PropertyStorageType.custom
  final PropertyStorage? customPropertyStorage;

  /// Throttle configuration for rate limiting and concurrency control
  /// If null, uses default throttling (100 concurrent, 10 req/sec)
  final ThrottleConfig? throttleConfig;

  /// Whether to enable request throttling
  final bool enableThrottling;

  /// Authentication provider
  /// If null and allowAnonymous is true, no authentication is required
  final AuthenticationProvider? authenticationProvider;

  /// Authorization provider
  /// If null, all authenticated users have full access
  final AuthorizationProvider? authorizationProvider;

  /// Metrics collector for server operations
  /// If null, uses the global defaultMetrics instance
  final Metrics? metrics;

  const DAVConfig({
    required this.root,
    required this.prefix,
    this.allowAnonymous = true,
    this.maxConcurrentRequests,
    this.maxUploadSize,
    this.enableLocking = false,
    this.lockStorage,
    this.readOnly = false,
    this.verbose = false,
    this.propertyStorageType = PropertyStorageType.memory,
    this.customPropertyStorage,
    this.throttleConfig,
    this.enableThrottling = true,
    this.authenticationProvider,
    this.authorizationProvider,
    this.metrics,
  });

  /// Create a copy of this config with some fields replaced
  DAVConfig copyWith({
    final Directory? root,
    final String? prefix,
    final bool? allowAnonymous,
    final int? maxConcurrentRequests,
    final int? maxUploadSize,
    final bool? enableLocking,
    final LockStorage? lockStorage,
    final bool? readOnly,
    final bool? verbose,
    final PropertyStorageType? propertyStorageType,
    final PropertyStorage? customPropertyStorage,
    final ThrottleConfig? throttleConfig,
    final bool? enableThrottling,
    final AuthenticationProvider? authenticationProvider,
    final AuthorizationProvider? authorizationProvider,
    final Metrics? metrics,
  }) =>
      DAVConfig(
        root: root ?? this.root,
        prefix: prefix ?? this.prefix,
        allowAnonymous: allowAnonymous ?? this.allowAnonymous,
        maxConcurrentRequests:
            maxConcurrentRequests ?? this.maxConcurrentRequests,
        maxUploadSize: maxUploadSize ?? this.maxUploadSize,
        enableLocking: enableLocking ?? this.enableLocking,
        lockStorage: lockStorage ?? this.lockStorage,
        readOnly: readOnly ?? this.readOnly,
        verbose: verbose ?? this.verbose,
        propertyStorageType: propertyStorageType ?? this.propertyStorageType,
        customPropertyStorage:
            customPropertyStorage ?? this.customPropertyStorage,
        throttleConfig: throttleConfig ?? this.throttleConfig,
        enableThrottling: enableThrottling ?? this.enableThrottling,
        authenticationProvider:
            authenticationProvider ?? this.authenticationProvider,
        authorizationProvider:
            authorizationProvider ?? this.authorizationProvider,
        metrics: metrics ?? this.metrics,
      );
}
