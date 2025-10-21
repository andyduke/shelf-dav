import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';
import 'package:shelf_dav/src/auth/auth.dart';

/// Authentication and authorization middleware
///
/// Handles authentication via pluggable AuthProvider and authorization
/// via pluggable AuthzProvider.
class AuthMiddleware {
  final AuthenticationProvider _authenticationProvider;
  final AuthorizationProvider _authorizationProvider;
  final String? _prefix;
  final Logger _logger;

  AuthMiddleware({
    required AuthenticationProvider authenticationProvider,
    required AuthorizationProvider authorizationProvider,
    String? prefix,
  })  : _authenticationProvider = authenticationProvider,
        _authorizationProvider = authorizationProvider,
        _prefix = prefix,
        _logger = Logger('AuthMiddleware');

  /// Create middleware handler
  Handler call(final Handler handler) => (Request request) async {
        final authenticationResult =
            await _authenticationProvider.authenticate(request);
        if (!authenticationResult.authenticated) {
          _logger.warning(
            'Authentication failed: ${authenticationResult.error} for ${request.requestedUri}',
          );
          return Response(
            HttpStatus.unauthorized,
            body: authenticationResult.error ?? 'Authentication required',
            headers: {
              'WWW-Authenticate': _authenticationProvider.getChallenge(),
            },
          );
        }

        // Determine operation and canonicalized path (strip prefix for authz)
        final operation = operationFromMethod(request.method);
        var path = request.url.path;
        if (!path.startsWith('/')) {
          path = '/$path';
        }
        if (_prefix != null &&
            _prefix!.isNotEmpty &&
            path.startsWith(_prefix!)) {
          path = path.substring(_prefix!.length);
          if (!path.startsWith('/')) {
            path = '/$path';
          }
        }

        final authorizationResult = await _authorizationProvider.authorize(
          authenticationResult.user,
          operation,
          path,
        );

        if (!authorizationResult.authorized) {
          _logger.warning(
              'Authorization failed for ${authenticationResult.user?.username ?? "anonymous"}: '
              '${authorizationResult.reason} (${request.method} $path)');
          return Response(
            HttpStatus.forbidden,
            body: authorizationResult.reason ?? 'Access denied',
          );
        }
        final updated = request.change(
          context: {
            ...request.context,
            'auth_user': authenticationResult.user,
          },
        );
        if (authenticationResult.user != null) {
          _logger.fine(
            'Authorized ${authenticationResult.user!.username} for ${request.method} $path',
          );
        }

        return handler(updated);
      };
}

/// Helper to extract authenticated user from request context
AuthUser? getAuthUser(final Request request) =>
    request.context['auth_user'] as AuthUser?;
