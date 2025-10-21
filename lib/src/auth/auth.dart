import 'package:shelf/shelf.dart';

/// Represents an authenticated user
class AuthUser {
  final String username;
  final Map<String, dynamic> metadata;

  const AuthUser({
    required this.username,
    this.metadata = const {},
  });

  @override
  String toString() => 'AuthUser($username)';
}

/// Result of an authentication attempt
class AuthenticationResult {
  final bool authenticated;
  final AuthUser? user;
  final String? error;

  const AuthenticationResult.success(this.user)
      : authenticated = true,
        error = null;

  const AuthenticationResult.failure(this.error)
      : authenticated = false,
        user = null;

  const AuthenticationResult.anonymous()
      : authenticated = true,
        user = null,
        error = null;
}

/// WebDAV operations that can be authorized
enum Action {
  read, // GET, HEAD, PROPFIND, OPTIONS
  write, // PUT, DELETE, COPY, MOVE, MKCOL, PROPPATCH
  lock, // LOCK, UNLOCK
}

/// Result of an authorization check
class AuthorizationResult {
  final bool authorized;
  final String? reason;

  const AuthorizationResult.allowed()
      : authorized = true,
        reason = null;

  const AuthorizationResult.denied(this.reason) : authorized = false;
}

/// Authentication provider interface
///
/// Implement this interface to create custom authentication providers.
abstract class AuthenticationProvider {
  /// Authenticate a request
  ///
  /// Returns AuthResult.success with user info if authenticated,
  /// AuthResult.failure with error message if authentication failed,
  /// or AuthResult.anonymous if anonymous access is allowed.
  Future<AuthenticationResult> authenticate(Request request);

  /// Get the authentication challenge to send in WWW-Authenticate header
  ///
  /// For example: "Basic realm=\"WebDAV Server\""
  String getChallenge();
}

/// Authorization provider interface
///
/// Implement this interface to create custom authorization providers.
abstract class AuthorizationProvider {
  /// Check if a user is authorized to perform an operation on a resource
  ///
  /// [user] - The authenticated user (null for anonymous)
  /// [operation] - The operation being performed
  /// [path] - The resource path (relative to WebDAV root)
  Future<AuthorizationResult> authorize(
    final AuthUser? user,
    final Action operation,
    final String path,
  );
}

/// Determine operation type from HTTP method
Action operationFromMethod(final String method) {
  switch (method.toUpperCase()) {
    case 'GET':
    case 'HEAD':
    case 'PROPFIND':
    case 'OPTIONS':
      return Action.read;
    case 'PUT':
    case 'DELETE':
    case 'COPY':
    case 'MOVE':
    case 'MKCOL':
    case 'PROPPATCH':
    case 'POST':
    case 'TRACE':
      return Action.write;
    case 'LOCK':
    case 'UNLOCK':
      return Action.lock;
    default:
      return Action.read;
  }
}
