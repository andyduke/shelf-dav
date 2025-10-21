import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'lock_storage.dart';

/// Validate that a request has permission to modify a locked resource
/// Returns null if validation passes, Response if locked
Future<Response?> canLock({
  required final LockStorage? locks,
  required final String path,
  required final Map<String, String> headers,
}) async {
  if (locks == null) return null;

  final isLocked = await locks.isLocked(path);
  if (!isLocked) return null;

  final token = extractToken(headers);

  final canModify = await locks.canModify(path, token);
  if (!canModify) {
    return Response(
      423,
      body: 'Resource is locked. Provide valid lock token in If header.',
    );
  }

  return null;
}

/// Ensure request has permission to modify a locked resource
/// Throws ResourceLockedException if resource is locked without valid token
Future<void> ensureUnlocked({
  required final LockStorage? locks,
  required final String path,
  required final Map<String, String> headers,
}) async {
  if (locks == null) return;

  final isLocked = await locks.isLocked(path);
  if (!isLocked) return;

  final token = extractToken(headers);

  final canModify = await locks.canModify(path, token);
  if (!canModify) {
    throw ResourceLockedException();
  }
}

/// Extract and clean lock token from headers
/// Removes angle bracket wrapper: `<token>` -> token
/// Tries If header first (RFC 4918), then Lock-Token header
String? extractToken(final Map<String, String> headers) {
  // Try If header first (RFC 4918 Section 10.4)
  // Format: (<opaquelocktoken:...>) or </resource> (<opaquelocktoken:...>)
  var token = headers['If']?.trim();

  if (token != null && token.isNotEmpty) {
    // Parse If header - extract token from within parentheses and angle brackets
    // Example: "(<opaquelocktoken:xxx>)" -> "opaquelocktoken:xxx"
    final match = RegExp(r'\(<([^>]+)>\)').firstMatch(token);
    if (match != null) {
      return match.group(1);
    }
  }

  // Fall back to Lock-Token header
  token = headers['Lock-Token']?.trim();

  if (token == null || token.isEmpty) return null;

  // Strip angle brackets from Lock-Token header
  if (token.startsWith('<') && token.endsWith('>')) {
    token = token.substring(1, token.length - 1);
  }

  return token;
}
