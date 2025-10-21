# shelf_dav Documentation

`shelf_dav` is a WebDAV server implementation for Dart, built on the [Shelf](https://pub.dev/packages/shelf) HTTP framework. It provides 
a complete WebDAV interface for file system operations over HTTP, enabling file sharing, collaboration, and 
remote file management.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Configuration](#configuration)
- [Authentication & Authorization](#authentication--authorization)
- [Property Storage](#property-storage)
- [Throttling & Rate Limiting](#throttling--rate-limiting)
- [WebDAV Methods](#webdav-methods)
- [Embedding in Applications](#embedding-in-applications)
- [Advanced Topics](#advanced-topics)

## Quick Start

```dart
import 'package:file/local.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

Future<void> main() async {
  final fs = const LocalFileSystem();
  final root = fs.directory('webdav_data');
  await root.create(recursive: true);

  final config = DAVConfig(
    root: root,
    prefix: '/dav',
    allowAnonymous: true,
  );

  final dav = ShelfDAV.withConfig(config);
  final server = await shelf_io.serve(dav.handler, '0.0.0.0', 8080);

  print('WebDAV server running at http://localhost:8080/dav');
}
```

## Installation

Add `shelf_dav` to your `pubspec.yaml`:

```yaml
dependencies:
  shelf_dav: ^1.0.0
  shelf: ^1.4.0
  file: ^7.0.0
```

Then run:

```bash
dart pub get
```

## Basic Usage

### Creating a Simple Server

The simplest way to create a WebDAV server is using the `DAVConfig` class:

```dart
import 'package:file/local.dart';
import 'package:shelf_dav/shelf_dav.dart';

final fs = const LocalFileSystem();
final root = fs.directory('/path/to/webdav/files');

final config = DAVConfig(
  root: root,
  prefix: '/dav',
  allowAnonymous: true,
);

final dav = ShelfDAV.withConfig(config);
```

### Serving Requests

Use Shelf's `serve` function to start the server:

```dart
import 'package:shelf/shelf_io.dart' as shelf_io;

final server = await shelf_io.serve(dav.handler, '0.0.0.0', 8080);
print('Serving at http://${server.address.host}:${server.port}/dav');
```

## Configuration

`DAVConfig` provides extensive configuration options:

```dart
final config = DAVConfig(
  // Required
  root: directory,                    // Root directory to serve
  prefix: '/dav',                     // URL prefix for WebDAV

  // Access Control
  allowAnonymous: true,               // Allow unauthenticated access
  readOnly: false,                    // Prevent write operations

  // Limits
  maxConcurrentRequests: 100,         // Max concurrent requests
  maxUploadSize: 100 * 1024 * 1024,   // Max upload size (bytes)

  // Features
  enableLocking: false,               // Enable LOCK/UNLOCK support
  enableThrottling: true,             // Enable rate limiting
  verbose: false,                     // Debug logging

  // Property Storage
  propertyStorageType: PropertyStorageType.memory,

  // Authentication
  authenticationProvider: null,       // Custom auth provider
  authorizationProvider: null,        // Custom authz provider

  // Throttling
  throttleConfig: ThrottleConfig(
    maxConcurrentRequests: 200,
    maxRequestsPerSecond: 20,
    rateLimitWindow: 1,
  ),

  // Metrics
  metrics: defaultMetrics,            // Custom metrics collector
);
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `root` | `Directory` | Required | Root directory to serve files from |
| `prefix` | `String` | Required | URL prefix for WebDAV endpoints |
| `allowAnonymous` | `bool` | `true` | Allow access without authentication |
| `maxConcurrentRequests` | `int?` | `null` | Maximum concurrent requests (null = unlimited) |
| `maxUploadSize` | `int?` | `null` | Maximum upload size in bytes (null = unlimited) |
| `enableLocking` | `bool` | `false` | Enable LOCK/UNLOCK operations |
| `readOnly` | `bool` | `false` | Prevent all write operations |
| `verbose` | `bool` | `false` | Enable detailed logging |
| `propertyStorageType` | `PropertyStorageType` | `memory` | How to store WebDAV properties |
| `enableThrottling` | `bool` | `true` | Enable request throttling |

## Authentication & Authorization

### No Authentication (Default)

By default, `shelf_dav` allows anonymous access:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  allowAnonymous: true,
);
```

### Basic Authentication

Use `BasicAuthenticationProvider` for HTTP Basic Authentication:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  allowAnonymous: false,
  authenticationProvider: BasicAuthenticationProvider.plaintext(
    realm: 'My WebDAV Server',
    users: {
      'alice': 'secret123',
      'bob': 'password456',
    },
  ),
);
```

Passwords are automatically hashed using SHA-256. For pre-hashed passwords, use the regular constructor:

```dart
final provider = BasicAuthenticationProvider(
  realm: 'My Server',
  users: {
    'alice': sha256Hash('secret123'),
  },
);
```

### Role-Based Authorization

`RoleBasedAuthorizationProvider` supports read-only and read-write users:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  allowAnonymous: false,
  authenticationProvider: BasicAuthenticationProvider.plaintext(
    realm: 'My WebDAV Server',
    users: {'alice': 'secret123', 'bob': 'password456'},
  ),
  authorizationProvider: RoleBasedAuthorizationProvider(
    readWriteUsers: {'alice'},
    readOnlyUsers: {'bob'},
    allowAnonymousRead: false,
  ),
);
```

### Path-Based Authorization

For fine-grained control, use `PathBasedAuthorizationProvider`:

```dart
final authzProvider = PathBasedAuthorizationProvider(
  rules: [
    PathRule(
      path: '/public',
      users: {},           // Allow all authenticated users
      readOnly: true,
    ),
    PathRule(
      path: '/admin',
      users: {'alice'},    // Only alice can access
      readOnly: false,
    ),
  ],
  defaultRule: PathRule(
    path: '/',
    users: {'alice', 'bob'},
    readOnly: false,
  ),
);
```

### Custom Authentication

Implement `AuthenticationProvider` for custom authentication:

```dart
class CustomAuthProvider implements AuthenticationProvider {
  @override
  Future<AuthenticationResult> authenticate(Request request) async {
    // Your custom authentication logic
    final token = request.headers['x-api-token'];

    if (token == null) {
      return AuthenticationResult.failure('Missing token');
    }

    // Validate token...
    if (isValid(token)) {
      return AuthenticationResult.success(
        AuthUser(username: 'user123'),
      );
    }

    return AuthenticationResult.failure('Invalid token');
  }

  @override
  String getChallenge() => 'Bearer realm="API"';
}
```

## Property Storage

WebDAV properties (custom metadata) can be stored in different backends:

### Memory Storage (Default)

Properties are stored in memory and lost on restart:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.memory,
);
```

### File Storage

Properties are persisted to hidden files alongside resources:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.file,
);
```

Properties are stored in files named `.webdav_props` in the same directory as the resource.

### Custom Storage

Implement `PropertyStorage` for custom backends (database, Redis, etc.):

```dart
class DatabasePropertyStorage implements PropertyStorage {
  @override
  Future<Map<String, String>> get(String path) async {
    // Load properties from database
  }

  @override
  Future<void> set(String path, Map<String, String> properties) async {
    // Save properties to database
  }

  @override
  Future<void> remove(String path, Set<String> keys) async {
    // Remove specific properties
  }

  @override
  Future<void> delete(String path) async {
    // Delete all properties for a resource
  }

  @override
  Future<void> close() async {
    // Clean up resources
  }
}

final config = DAVConfig(
  root: root,
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.custom,
  customPropertyStorage: DatabasePropertyStorage(),
);
```

## Throttling & Rate Limiting

Prevent abuse with built-in throttling:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  enableThrottling: true,
  throttleConfig: ThrottleConfig(
    maxConcurrentRequests: 200,      // Max concurrent connections
    maxRequestsPerSecond: 20,        // Max requests per second per IP
    rateLimitWindow: 1,              // Time window in seconds
  ),
);
```

When limits are exceeded, the server returns:
- `429 Too Many Requests` with `Retry-After` header
- `X-RateLimit-Limit` header with the limit
- `X-RateLimit-Remaining` header with remaining requests
- `X-RateLimit-Reset` header with reset timestamp

## Locking Support

WebDAV locking prevents concurrent modifications and supports collaborative editing:

```dart
final config = DAVConfig(
  root: root,
  prefix: '/dav',
  enableLocking: true,
  lockStorage: MemoryLockStorage(), // Optional: custom lock storage
);
```

### Lock Features

- **Exclusive and Shared Locks**: Supports both lock scopes per RFC 4918
- **Write Locks**: Prevents modifications to locked resources
- **Lock Refresh**: Extend lock timeouts before expiration
- **Depth Support**: Lock collections with Depth: 0 or infinity
- **Null Resource Locks**: Reserve names for future resource creation
- **Lock Discovery**: Query active locks via PROPFIND

When locking is disabled (default), LOCK/UNLOCK return `501 Not Implemented`.

## WebDAV Methods

`shelf_dav` implements standard WebDAV methods:

### Implemented Methods

| Method | Description | Status |
|--------|-------------|--------|
| `GET` | Download files, list directories | Full |
| `PUT` | Upload/update files | Full |
| `DELETE` | Delete files/directories | Full (207 on partial failure) |
| `HEAD` | Get file metadata | Full |
| `OPTIONS` | Get supported methods | Full |
| `PROPFIND` | Query properties | Full (Depth: 0, 1, infinity) |
| `PROPPATCH` | Modify properties | Full (207 Multi-Status) |
| `MKCOL` | Create directories | Full |
| `COPY` | Copy files/directories | Full (207 on partial failure) |
| `MOVE` | Move/rename files/directories | Full (207 on partial failure) |
| `LOCK` | Lock resources | Full (requires `enableLocking`) |
| `UNLOCK` | Unlock resources | Full (requires `enableLocking`) |

### RFC 4918 Compliance

`shelf_dav` follows RFC 4918 (WebDAV specification):

- **207 Multi-Status**: Operations on collections properly handle partial failures
- **Depth Header**: PROPFIND supports Depth: 0, 1, and infinity
- **Overwrite Header**: COPY and MOVE respect the Overwrite header
- **If-Match/If-None-Match**: ETag-based concurrency control
- **Destination Header**: COPY and MOVE use proper destination handling

### ETag Support

ETags enable optimistic concurrency control:

```http
PUT /dav/file.txt HTTP/1.1
If-Match: "abc123"
```

- Returns `412 Precondition Failed` if ETag doesn't match
- Returns `304 Not Modified` for GET/HEAD with matching If-None-Match
- ETags are generated from file size, modification time, and path

## Embedding in Applications

Mount WebDAV alongside other endpoints using `shelf_router`:

```dart
import 'package:shelf_router/shelf_router.dart';

final app = Router();

// Your API endpoints
app.get('/api/users', _handleUsers);
app.post('/api/login', _handleLogin);

// Mount WebDAV at /files
final dav = ShelfDAV.withConfig(config);
app.mount('/files', dav.handler);

// Serve the combined application
final handler = const Pipeline()
    .addMiddleware(logRequests())
    .addHandler(app.call);

await shelf_io.serve(handler, '0.0.0.0', 8080);
```

See `example/embedded.dart` for a complete example.

## Advanced Topics

### Metrics Collection

Track server performance with the built-in metrics system:

```dart
import 'package:shelf_dav/shelf_dav.dart';

// Access default metrics
final metrics = defaultMetrics;

// Get statistics
print('Total requests: ${metrics.requestCounts}');
print('Error rates: ${metrics.errorCounts}');
print('Response times: ${metrics.responseTimes}');

// Custom metrics implementation
class CustomMetrics implements Metrics {
  @override
  void recordRequest(String method) {
    // Send to monitoring system
  }

  @override
  void recordResponseTime(String method, Duration duration) {
    // Track performance
  }

  @override
  void recordError(String method, int statusCode) {
    // Alert on errors
  }

  // ... implement other methods
}

final config = DAVConfig(
  root: root,
  prefix: '/dav',
  metrics: CustomMetrics(),
);
```

### Resource Lifecycle

Understanding the resource types:

- **DavResource**: Base class for non-existent resources (handles PUT, MKCOL)
- **DavFileResource**: Handles operations on files
- **DavDirectoryResource**: Handles operations on directories/collections

The server automatically selects the appropriate resource type based on the filesystem state.

### Atomic Operations

`shelf_dav` uses atomic operations to prevent data corruption:

- **Atomic Writes**: PUT operations write to temporary files, then atomically rename
- **Atomic Moves**: MOVE attempts atomic rename first, falls back to copy+delete
- **Partial Failure Handling**: Collection operations continue even if some items fail

### Path Security

Multiple layers of path traversal protection:

1. Raw path checking before normalization
2. Prefix verification after normalization
3. Final path validation within root directory

All path traversal attempts are logged and return `403 Forbidden`.

### Shutdown Handling

Properly clean up resources:

```dart
final dav = ShelfDAV.withConfig(config);

// On shutdown
ProcessSignal.sigint.watch().listen((_) async {
  await dav.close();  // Closes storage, locks, throttling
  await server.close();
  exit(0);
});
```
