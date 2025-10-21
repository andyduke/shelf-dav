import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/auth/auth.dart';
import 'package:crypto/crypto.dart';

/// No-op authentication provider that allows all requests
///
/// Use this for development or when authentication is handled elsewhere
class NoopAuthenticationProvider implements AuthenticationProvider {
  const NoopAuthenticationProvider();

  @override
  Future<AuthenticationResult> authenticate(final Request request) async =>
      const AuthenticationResult.anonymous();

  @override
  String getChallenge() => '';
}

/// HTTP Basic Authentication provider
///
/// Validates username/password against a configured map.
/// Passwords are stored as SHA-256 hashes.
class BasicAuthenticationProvider implements AuthenticationProvider {
  final String realm;
  final Map<String, String> _users; // username -> SHA-256 hash

  BasicAuthenticationProvider({
    this.realm = 'WebDAV Server',
    required Map<String, String> users,
  }) : _users = users;

  /// Create a BasicAuthProvider with plaintext passwords (hashed automatically)
  factory BasicAuthenticationProvider.plaintext({
    final String realm = 'WebDAV Server',
    required Map<String, String> users,
  }) {
    final hashed = <String, String>{};
    for (final entry in users.entries) {
      hashed[entry.key] = _hashPassword(entry.value);
    }
    return BasicAuthenticationProvider(realm: realm, users: hashed);
  }

  @override
  Future<AuthenticationResult> authenticate(final Request request) async {
    final header = request.headers['authorization'];

    if (header == null || !header.startsWith('Basic ')) {
      return const AuthenticationResult.failure(
        'Missing or invalid Authorization header',
      );
    }

    final encoded = header.substring(6); // Remove "Basic "
    final decoded = utf8.decode(base64.decode(encoded));
    final parts = decoded.split(':');

    if (parts.length != 2) {
      return const AuthenticationResult.failure(
        'Invalid Authorization header format',
      );
    }

    final username = parts[0];
    final password = parts[1];

    final expected = _users[username];
    if (expected == null) {
      return const AuthenticationResult.failure('Invalid username or password');
    }

    final hash = _hashPassword(password);
    if (hash != expected) {
      return const AuthenticationResult.failure('Invalid username or password');
    }

    return AuthenticationResult.success(AuthUser(username: username));
  }

  @override
  String getChallenge() => 'Basic realm="$realm"';

  static String _hashPassword(final String password) =>
      sha256.convert(utf8.encode(password)).toString();
}

/// Simple role-based authorization provider
///
/// Supports read-only users and read-write users.
class RoleBasedAuthorizationProvider implements AuthorizationProvider {
  final Set<String> _readOnlyUsers;
  final Set<String> _readWriteUsers;
  final bool _allowAnonymousRead;

  const RoleBasedAuthorizationProvider({
    Set<String> readOnlyUsers = const {},
    Set<String> readWriteUsers = const {},
    bool allowAnonymousRead = true,
  })  : _readOnlyUsers = readOnlyUsers,
        _readWriteUsers = readWriteUsers,
        _allowAnonymousRead = allowAnonymousRead;

  @override
  Future<AuthorizationResult> authorize(
    final AuthUser? user,
    final Action operation,
    final String path,
  ) async {
    if (user == null) {
      if (operation == Action.read && _allowAnonymousRead) {
        return const AuthorizationResult.allowed();
      }
      return const AuthorizationResult.denied('Anonymous users not allowed');
    }

    if (_readWriteUsers.contains(user.username)) {
      return const AuthorizationResult
          .allowed(); // Read-write users can do anything
    }

    if (_readOnlyUsers.contains(user.username)) {
      if (operation == Action.read) {
        return const AuthorizationResult.allowed();
      }
      return const AuthorizationResult.denied('User has read-only access');
    }

    return const AuthorizationResult.denied('User not authorized');
  }
}

/// Path-based authorization provider
///
/// Allows fine-grained control over which users can access which paths.
class PathBasedAuthorizationProvider implements AuthorizationProvider {
  final bool _allowAnonymousRead;
  final List<MapEntry<String, Set<String>>>
      _permissions; // pre-sorted by path length desc

  PathBasedAuthorizationProvider({
    Map<String, Set<String>> pathPermissions = const {},
    bool allowAnonymousRead = false,
  })  : _allowAnonymousRead = allowAnonymousRead,
        _permissions = pathPermissions.entries.toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));

  @override
  Future<AuthorizationResult> authorize(
    final AuthUser? user,
    final Action operation,
    final String path,
  ) async {
    if (user == null) {
      if (operation == Action.read && _allowAnonymousRead) {
        return const AuthorizationResult.allowed();
      }
      return const AuthorizationResult.denied('Authentication required');
    }

    // Check if user has access to this path or parent paths using pre-sorted entries
    for (final entry in _permissions) {
      final base = entry.key;
      final users = entry.value;

      // Check if path matches (exact match or is under allowed path)
      if (path == base || path.startsWith('$base/')) {
        if (users.contains(user.username)) {
          return const AuthorizationResult.allowed();
        }
        // User matched path but not in allowed list - deny immediately
        return AuthorizationResult.denied(
          'User ${user.username} not in allowed list for path: $base',
        );
      }
    }

    return AuthorizationResult.denied('User not authorized for path: $path');
  }
}

/// Allow-all authorization provider
///
/// Grants all authenticated users full access to all resources.
class AllowAllAuthorizationProvider implements AuthorizationProvider {
  const AllowAllAuthorizationProvider();

  @override
  Future<AuthorizationResult> authorize(
    final AuthUser? user,
    final Action operation,
    final String path,
  ) async =>
      const AuthorizationResult.allowed();
}

/// Deny-all authentication provider
///
/// Always denies authentication. Used when authentication is required
/// but no provider is configured.
class DenyAllAuthProvider implements AuthenticationProvider {
  const DenyAllAuthProvider();

  @override
  Future<AuthenticationResult> authenticate(final Request request) async =>
      const AuthenticationResult.failure('Authentication required');

  @override
  String getChallenge() => 'Basic realm="WebDAV Server"';
}
