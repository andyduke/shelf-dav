import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../webdav_constants.dart';
import 'lock_storage.dart';

/// In-memory implementation of LockStorage
///
/// Locks are stored in memory and lost on server restart.
/// Suitable for development and testing.
class MemoryLockStorage implements LockStorage {
  final Map<String, DavLock> _locksByToken = {};
  final Map<String, List<String>> _locksByPath = {};
  Timer? _cleanupTimer;

  MemoryLockStorage() {
    // Periodic cleanup of expired locks every minute
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => removeExpiredLocks(),
    );
  }

  /// Generate a unique lock token
  String _generateToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch;
    final input = '$timestamp-$random';
    final hash = md5.convert(utf8.encode(input)).toString();
    return 'opaquelocktoken:$hash';
  }

  @override
  Future<DavLock?> createLock({
    required final String path,
    required final LockScope scope,
    required final LockType type,
    final String? owner,
    final Duration? timeout,
    final int depth = 0,
  }) async {
    final existing = await getLocks(path);
    for (final lock in existing) {
      if (!lock.isExpired) {
        // Exclusive locks conflict with any other lock
        if (lock.scope == LockScope.exclusive || scope == LockScope.exclusive) {
          return null; // Conflict
        }
      }
    }

    final token = _generateToken();
    final expires = timeout != null ? DateTime.now().add(timeout) : null;
    final lock = DavLock(
      token: token,
      path: path,
      scope: scope,
      type: type,
      owner: owner,
      created: DateTime.now(),
      expires: expires,
      depth: depth,
    );

    _locksByToken[token] = lock;
    _locksByPath.putIfAbsent(path, () => []).add(token);

    return lock;
  }

  @override
  Future<DavLock?> getLock(final String token) async {
    final lock = _locksByToken[token];
    if (lock != null && lock.isExpired) {
      await removeLock(token);
      return null;
    }
    return lock;
  }

  @override
  Future<List<DavLock>> getLocks(final String path) async {
    final tokens = <String>{...(_locksByPath[path] ?? const <String>[])};
    final locks = <DavLock>[];

    // Include locks on ancestor paths that extend to this resource
    for (final entry in _locksByPath.entries) {
      if (entry.key == path) continue;
      if (_isAncestor(entry.key, path)) {
        tokens.addAll(entry.value);
      }
    }

    for (final token in tokens) {
      final lock = await getLock(token);
      if (lock != null && _covers(lock, path)) {
        locks.add(lock);
      }
    }

    return locks;
  }

  @override
  Future<DavLock?> refreshLock(
    final String token,
    final Duration? timeout,
  ) async {
    final lock = await getLock(token);
    if (lock == null) return null;

    final expires = timeout != null ? DateTime.now().add(timeout) : null;
    final updated = DavLock(
      token: lock.token,
      path: lock.path,
      scope: lock.scope,
      type: lock.type,
      owner: lock.owner,
      created: lock.created,
      expires: expires,
      depth: lock.depth,
    );

    _locksByToken[token] = updated;
    return updated;
  }

  @override
  Future<bool> removeLock(final String token) async {
    final lock = _locksByToken.remove(token);
    if (lock != null) {
      final pathLocks = _locksByPath[lock.path];
      pathLocks?.remove(token);
      if (pathLocks?.isEmpty ?? false) {
        _locksByPath.remove(lock.path);
      }
      return true;
    }
    return false;
  }

  @override
  Future<void> removeExpiredLocks() async {
    final expired = <String>[];
    for (final entry in _locksByToken.entries) {
      if (entry.value.isExpired) {
        expired.add(entry.key);
      }
    }
    for (final token in expired) {
      await removeLock(token);
    }
  }

  @override
  Future<bool> isLocked(final String path) async {
    final locks = await getLocks(path);
    return locks.isNotEmpty;
  }

  @override
  Future<bool> canModify(final String path, final String? lockToken) async {
    final locks = await getLocks(path);

    if (locks.isEmpty) return true; // No locks

    if (lockToken == null) return false; // Locked but no token provided

    // Check if provided token matches any lock on this resource
    return locks.any((lock) => lock.token == lockToken);
  }

  @override
  Future<void> close() async {
    _cleanupTimer?.cancel();
    _locksByToken.clear();
    _locksByPath.clear();
  }

  bool _isAncestor(final String parent, final String child) {
    if (child == parent) return false;
    final separator = _separatorFor(parent);
    final normalized =
        parent.endsWith(separator) ? parent : '$parent$separator';
    return child.startsWith(normalized);
  }

  bool _covers(final DavLock lock, final String path) {
    if (lock.path == path) {
      return true;
    }
    if (lock.depth == 0) {
      return false;
    }
    if (lock.depth != WebDAVConstants.infinity && lock.depth <= 0) {
      return false;
    }

    return _isAncestor(lock.path, path);
  }

  String _separatorFor(final String path) => path.contains('\\') ? '\\' : '/';
}
