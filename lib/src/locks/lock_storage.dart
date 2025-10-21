import 'dart:async';

/// WebDAV lock scope
enum LockScope {
  exclusive,
  shared,
}

/// WebDAV lock type
enum LockType {
  write,
}

/// Represents a WebDAV lock on a resource
class DavLock {
  final String token;
  final String path;
  final LockScope scope;
  final LockType type;
  final String? owner;
  final DateTime created;
  final DateTime? expires;
  final int depth;

  const DavLock({
    required this.token,
    required this.path,
    required this.scope,
    required this.type,
    this.owner,
    required this.created,
    this.expires,
    this.depth = 0,
  });

  /// Check if lock has expired
  bool get isExpired {
    if (expires == null) return false;
    return DateTime.now().isAfter(expires!);
  }

  /// Check if lock is still valid
  bool get isValid => !isExpired;

  @override
  String toString() =>
      'DavLock(token: $token, path: $path, scope: $scope, owner: $owner)';
}

/// Abstract interface for storing and managing WebDAV locks
///
/// Implementations can store locks in memory, files, database, etc.
abstract class LockStorage {
  /// Create a new lock on a resource
  /// Returns the lock if successful, null if resource is already locked
  Future<DavLock?> createLock({
    required final String path,
    required final LockScope scope,
    required final LockType type,
    final String? owner,
    final Duration? timeout,
    final int depth = 0,
  });

  /// Get a lock by token
  Future<DavLock?> getLock(final String token);

  /// Get all locks for a resource path
  Future<List<DavLock>> getLocks(final String path);

  /// Refresh a lock's timeout
  /// Returns the updated lock, or null if not found
  Future<DavLock?> refreshLock(final String token, final Duration? timeout);

  /// Remove a lock by token
  /// Returns true if lock existed and was removed
  Future<bool> removeLock(final String token);

  /// Remove all expired locks (cleanup)
  Future<void> removeExpiredLocks();

  /// Check if a resource is locked
  Future<bool> isLocked(final String path);

  /// Check if a token can modify a resource (owns the lock or no lock exists)
  Future<bool> canModify(final String path, final String? lockToken);

  /// Close/cleanup the storage
  Future<void> close();
}
