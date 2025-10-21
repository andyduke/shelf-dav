# shelf_dav

A WebDAV server implementation for Dart using [package:shelf](https://pub.dev/packages/shelf).

## Features

- **Full WebDAV Level 1 Support:** GET, PUT, DELETE, COPY, MOVE, MKCOL, PROPFIND, PROPPATCH, OPTIONS
- **Property Storage:** Pluggable storage backends (memory, file-based, or custom)
- **RFC 4918 Compliance:** Full 207 Multi-Status support for partial failures
- **ETag Support:** Optimistic concurrency control with If-Match/If-None-Match headers
- **Authentication:** HTTP Basic Auth with pluggable providers (Basic, anonymous, or custom)
- **Authorization:** Role-based and path-based access control with pluggable providers
- **Request Throttling:** Concurrent request limiting and per-IP rate limiting for high-traffic scenarios
- **Async File Operations:** Non-blocking I/O for better performance
- **Configurable:** Directory serving, property storage, auth, concurrency limits, throttling, read-only mode
- **Atomic Operations:** Safe file replacement and directory moves
- **Depth Support:** PROPFIND and COPY support depth headers (0, 1, infinity)
- **In-Memory Testing:** Uses `package:file` for easy testing with memory filesystems

## Usage

### Basic Setup

```dart
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';
import 'package:file/local.dart';

void main() async {
  final fs = const LocalFileSystem();
  final dav = ShelfDAV('/dav', fs.directory('/path/to/files'));

  final server = await shelf_io.serve(
    dav.handler,
    'localhost',
    8080,
  );

  print('WebDAV server at http://${server.address.host}:${server.port}/dav');
}
```

### With Configuration

```dart
import 'package:shelf_dav/shelf_dav.dart';

void main() async {
  final config = DAVConfig(
    root: fs.directory('/path/to/files'),
    prefix: '/dav',
    allowAnonymous: true,
    maxConcurrentRequests: 100,
    maxUploadSize: 100 * 1024 * 1024,  // 100MB
    readOnly: false,
    enableLocking: true,  // Enable WebDAV locking support
    propertyStorageType: PropertyStorageType.file,  // Persist properties to disk
  );

  final dav = ShelfDAV.withConfig(config);
  final server = await shelf_io.serve(dav.handler, 'localhost', 8080);
}
```

### High-Concurrency Configuration

For production deployments supporting hundreds of concurrent users:

```dart
final config = DAVConfig(
  root: fs.directory('/path/to/files'),
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.file,
  enableThrottling: true,
  enableLocking: true,
  throttleConfig: ThrottleConfig(
    maxConcurrentRequests: 200,    // Support 200 simultaneous requests
    maxRequestsPerSecond: 20,      // 20 requests per second per IP
    rateLimitWindow: 1,            // 1 second rate limit window
  ),
);
```

### Authentication & Authorization

```dart
// Basic HTTP authentication with role-based authorization
final config = DAVConfig(
  root: fs.directory('/path/to/files'),
  prefix: '/dav',
  enableLocking: true,
  authenticationProvider: BasicAuthenticationProvider.plaintext(
    realm: 'My WebDAV Server',
    users: {
      'alice': 'secret123',
      'bob': 'password456',
    },
  ),
  authorizationProvider: RoleBasedAuthorizationProvider(
    readWriteUsers: {'alice'},
    readOnlyUsers: {'bob'},
    allowAnonymousRead: false,
  ),
);

// Path-based authorization (fine-grained control)
// Note: Paths in pathPermissions are relative to the mount point (prefix is stripped)
final config2 = DAVConfig(
  root: fs.directory('/path/to/files'),
  prefix: '/dav',
  enableLocking: true,
  authenticationProvider: BasicAuthenticationProvider.plaintext(
    users: {'alice': 'secret', 'bob': 'pass'},
  ),
  authorizationProvider: PathBasedAuthorizationProvider(
    pathPermissions: {
      '/public': {'alice', 'bob'},    // Both users can access /dav/public
      '/private': {'alice'},           // Only alice can access /dav/private
    },
    allowAnonymousRead: false,
  ),
);

// Anonymous access (no authentication)
final config3 = DAVConfig(
  root: fs.directory('/path/to/files'),
  prefix: '/dav',
  allowAnonymous: true,  // Default: uses NoAuthProvider
);
```

### Property Storage Options

```dart
// In-memory storage (default, properties lost on restart)
final config1 = DAVConfig(
  root: fs.directory('/path'),
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.memory,
);

// File-based storage (properties persisted to hidden JSON files)
final config2 = DAVConfig(
  root: fs.directory('/path'),
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.file,
);

// Custom storage (implement PropertyStorage interface)
class DatabasePropertyStorage implements PropertyStorage {
  // Your database implementation
}

final config3 = DAVConfig(
  root: fs.directory('/path'),
  prefix: '/dav',
  propertyStorageType: PropertyStorageType.custom,
  customPropertyStorage: DatabasePropertyStorage(),
);
```

### Mount in Router

```dart
import 'package:shelf_router/shelf_router.dart';

final router = Router()
  ..get('/api/info', infoHandler)
  ..mount('/dav/', dav.router);

final server = await shelf_io.serve(router, 'localhost', 8080);
```

## Mounting the WebDAV Server

Once your WebDAV server is running, you can mount it as a network drive on macOS and Linux.

### macOS

#### Using Finder (GUI)
1. Open **Finder**
2. Press `⌘K` (Command+K) or select **Go → Connect to Server**
3. Enter the server URL: `http://localhost:8080/dav`
4. Click **Connect**
5. If authentication is enabled, enter username and password
6. The WebDAV share will mount and appear in Finder sidebar

#### Using Command Line
```bash
# Create mount point
mkdir -p ~/webdav-mount

# Mount with authentication
mount_webdav -i http://localhost:8080/dav ~/webdav-mount

# Mount without authentication (for anonymous servers)
mount_webdav http://localhost:8080/dav ~/webdav-mount

# Unmount when done
umount ~/webdav-mount
```

#### Using AppleScript (for automation)
```applescript
-- Mount WebDAV server automatically
tell application "Finder"
    mount volume "http://localhost:8080/dav"
end tell
```

### Linux

#### Using File Manager (GUI)

**GNOME Files (Nautilus):**
1. Open **Files**
2. Click **Other Locations** in sidebar
3. At the bottom, enter: `dav://localhost:8080/dav`
4. Press Enter
5. Enter credentials if prompted

**KDE Dolphin:**
1. Open **Dolphin**
2. Press `Ctrl+L` to show location bar
3. Enter: `webdav://localhost:8080/dav`
4. Press Enter
5. Enter credentials if prompted

#### Using Command Line with davfs2

```bash
# Install davfs2
sudo apt-get install davfs2          # Debian/Ubuntu
sudo dnf install davfs2              # Fedora
sudo pacman -S davfs2                # Arch Linux

# Create mount point
sudo mkdir -p /mnt/webdav

# Mount WebDAV server
sudo mount -t davfs http://localhost:8080/dav /mnt/webdav

# For authentication, create /etc/davfs2/secrets
# Format: <mount_point> <username> <password>
echo "/mnt/webdav alice secret123" | sudo tee -a /etc/davfs2/secrets
sudo chmod 600 /etc/davfs2/secrets

# Mount with credentials
sudo mount -t davfs http://localhost:8080/dav /mnt/webdav

# Unmount when done
sudo umount /mnt/webdav
```

#### Auto-mount on Boot (Linux)

Add to `/etc/fstab`:
```
http://localhost:8080/dav /mnt/webdav davfs user,noauto,uid=1000,gid=1000 0 0
```

Then mount with:
```bash
mount /mnt/webdav
```

#### Using gvfs (GNOME Virtual File System)

```bash
# Mount via gvfs
gio mount dav://localhost:8080/dav

# With authentication
gio mount dav://alice@localhost:8080/dav

# Access files
cd ~/.gvfs/dav:host=localhost,port=8080,ssl=false/dav/

# Unmount
gio mount -u dav://localhost:8080/dav
```

### Testing the Mount

Once mounted, test with standard file operations:

```bash
# List files
ls /mnt/webdav

# Create directory
mkdir /mnt/webdav/test

# Copy file
cp document.txt /mnt/webdav/

# Move file
mv /mnt/webdav/old.txt /mnt/webdav/new.txt

# Remove file
rm /mnt/webdav/test.txt
```

### Troubleshooting

**macOS: "There was a problem connecting to the server"**
- Verify server is running: `curl http://localhost:8080/dav`
- Check firewall settings
- Use IP address instead of localhost if needed: `http://127.0.0.1:8080/dav`

**Linux: "mount.davfs: mounting failed"**
- Check if davfs2 is installed: `which mount.davfs`
- Verify user is in `davfs2` group: `sudo usermod -aG davfs2 $USER`
- Check server logs for authentication errors
- Test with curl: `curl -u alice:secret123 http://localhost:8080/dav`

**Permission denied errors:**
- Ensure user has read/write permissions on the server's data directory
- Check server configuration for `readOnly` flag
- Verify authorization settings in `DAVConfig`

## Testing

```bash
# Run all tests
dart test

# Run a single test file
dart test test/server_test.dart

# Run with verbose output
dart test --reporter=expanded
```

## Docker Deployment

### Quick Start with Docker Compose

```bash
# Start anonymous WebDAV server
docker-compose up -d

# Start with authentication enabled
docker-compose --profile auth up -d webdav-auth

# Stop services
docker-compose down
```

The server will be available at `http://localhost:8080/dav`

### Manual Docker Build

```bash
# Build image
docker build -t shelf-webdav .

# Run with anonymous access
docker run -d -p 8080:8080 -v $(pwd)/data:/data shelf-webdav

# Run with authentication
docker run -d -p 8080:8080 \
  -e ALLOW_ANONYMOUS=false \
  -e DAV_USERNAME=admin \
  -e DAV_PASSWORD=secret \
  -v $(pwd)/data:/data \
  shelf-webdav
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `HOST` | `0.0.0.0` | Bind address |
| `DATA_DIR` | `/data` | WebDAV root directory |
| `DAV_PREFIX` | `/dav` | URL prefix for WebDAV |
| `ALLOW_ANONYMOUS` | `true` | Allow unauthenticated access |
| `DAV_USERNAME` | - | Username for Basic Auth |
| `DAV_PASSWORD` | - | Password for Basic Auth |
| `MAX_CONCURRENT` | `100` | Max concurrent requests |
| `MAX_REQ_PER_SEC` | `10` | Max requests per second per IP |

### Volumes

Mount your data directory to `/data` in the container:

```bash
docker run -v /path/on/host:/data shelf-webdav
```

## WebDAV Compliance

This implementation follows [RFC 4918](https://datatracker.ietf.org/doc/html/rfc4918) (WebDAV Level 1):

### Core Features

- ✅ **HTTP Methods:** GET, PUT, DELETE, HEAD, OPTIONS
- ✅ **WebDAV Methods:** COPY, MOVE, MKCOL, PROPFIND, PROPPATCH
- ✅ **Headers:** Depth, Overwrite, Destination, If-Match, If-None-Match, ETag, Authorization
- ✅ **Property Storage:** Dead properties with pluggable backends
- ✅ **207 Multi-Status:** Partial failure handling per RFC 4918
- ✅ **Concurrency Control:** ETags for optimistic locking
- ✅ **Throttling:** Request rate limiting and concurrent request control
- ✅ **Authentication:** Pluggable authentication providers (Basic Auth, custom, or anonymous)
- ✅ **Authorization:** Pluggable authorization providers (role-based, path-based, custom)
- ✅ **LOCK/UNLOCK:** Full WebDAV locking support with exclusive and shared locks

### RFC 4918 Features

**207 Multi-Status Responses:**
- DELETE on collections continues on failure, returns 207 with detailed status
- COPY with depth continues on failure, returns 207 with detailed status
- MOVE (copy+delete) continues on failure, returns 207 with detailed status
- PROPPATCH returns 207 grouped by status code per property

**Property Management:**
- Full PROPPATCH support with XML parsing
- Namespace-aware property storage
- Multiple storage backends (memory, file, custom)
- Properties automatically copied/moved with resources

**Atomic Operations:**
- File MOVE uses atomic rename when possible
- PUT operations use temporary files with atomic replacement
- Safe handling of concurrent operations

**Concurrency & Performance:**
- ETag generation based on file metadata (size, mtime, path hash)
- If-Match validation for conditional PUT/DELETE (prevents lost updates)
- If-None-Match validation for conditional GET/HEAD (enables caching, returns 304)
- Request throttling with configurable concurrent request limits
- Per-IP rate limiting with automatic cleanup
- 429 Too Many Requests responses with Retry-After and X-RateLimit-* headers

**Security:**
- HTTP Basic Authentication with SHA-256 hashed passwords
- Pluggable authentication providers (implement `AuthProvider` interface)
- Role-based authorization (read-only vs read-write users)
- Path-based authorization (fine-grained per-directory permissions)
- Pluggable authorization providers (implement `AuthzProvider` interface)
- 401 Unauthorized responses with WWW-Authenticate challenge
- 403 Forbidden responses for insufficient permissions
- Anonymous access support (configurable)

## License

See LICENSE file.
