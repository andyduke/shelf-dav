import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:libdbm/libdbm.dart';

import '../webdav_constants.dart';
import 'lock_storage.dart';

/// DBM-based lock storage implementation using libdbm
///
/// Locks are persisted in a key-value database and survive server restarts.
/// This provides reliable lock management for production use.
class DbmLockStorage implements LockStorage {
  final PersistentMap<String, String> _db;
  final String _tokenPrefix;
  final String _pathPrefix;
  final bool _owned;
  Timer? _timer;

  /// Create a DBM lock storage
  /// [path] - path to the database file
  /// [tokenPrefix] - prefix for token keys
  /// [pathPrefix] - prefix for path index keys
  DbmLockStorage(
    final String path, {
    final String tokenPrefix = 'lock:token:',
    final String pathPrefix = 'lock:path:',
  })  : _db = PersistentMap<String, String>(
          HashDBM(File(path).openSync(mode: FileMode.append)),
          (key) => Uint8List.fromList(utf8.encode(key)),
          (bytes) => utf8.decode(bytes),
          (value) => Uint8List.fromList(utf8.encode(value)),
          (bytes) => utf8.decode(bytes),
        ),
        _tokenPrefix = tokenPrefix,
        _pathPrefix = pathPrefix,
        _owned = true {
    _startCleanup();
  }

  /// Create from existing PersistentMap instance (shared database)
  /// Note: When using fromDb, the database will NOT be closed by this instance
  DbmLockStorage.fromDb(
    this._db, {
    final String tokenPrefix = 'lock:token:',
    final String pathPrefix = 'lock:path:',
  })  : _tokenPrefix = tokenPrefix,
        _pathPrefix = pathPrefix,
        _owned = false {
    _startCleanup();
  }

  void _startCleanup() {
    // Periodic cleanup of expired locks every minute
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => removeExpiredLocks(),
    );
  }

  String _tokenKey(final String token) => '$_tokenPrefix$token';
  String _pathKey(final String path) => '$_pathPrefix$path';

  /// Generate a unique lock token
  String _generateToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch;
    final input = '$timestamp-$random';
    final hash = md5.convert(utf8.encode(input)).toString();
    return 'opaquelocktoken:$hash';
  }

  Map<String, dynamic> _serialize(final DavLock lock) => {
        'token': lock.token,
        'path': lock.path,
        'scope': lock.scope.name,
        'type': lock.type.name,
        'owner': lock.owner,
        'created': lock.created.toIso8601String(),
        'expires': lock.expires?.toIso8601String(),
        'depth': lock.depth,
      };

  DavLock? _deserialize(final String? data) {
    if (data == null) return null;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return DavLock(
        token: json['token'] as String,
        path: json['path'] as String,
        scope: LockScope.values.firstWhere(
          (s) => s.name == json['scope'],
          orElse: () => LockScope.exclusive,
        ),
        type: LockType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => LockType.write,
        ),
        owner: json['owner'] as String?,
        created: DateTime.parse(json['created'] as String),
        expires:
            json['expires'] != null ? DateTime.parse(json['expires']) : null,
        depth: json['depth'] as int? ?? 0,
      );
    } catch (e) {
      return null;
    }
  }

  List<String> _getPathTokens(final String path) {
    final data = _db[_pathKey(path)];
    if (data == null) return [];

    try {
      final list = jsonDecode(data) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      return [];
    }
  }

  void _setPathTokens(final String path, final List<String> tokens) {
    if (tokens.isEmpty) {
      _db.remove(_pathKey(path));
    } else {
      _db[_pathKey(path)] = jsonEncode(tokens);
    }
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

    // Store lock by token
    _db[_tokenKey(token)] = jsonEncode(_serialize(lock));

    // Add token to path index
    final tokens = _getPathTokens(path);
    tokens.add(token);
    _setPathTokens(path, tokens);

    return lock;
  }

  @override
  Future<DavLock?> getLock(final String token) async {
    final lock = _deserialize(_db[_tokenKey(token)]);
    if (lock != null && lock.isExpired) {
      await removeLock(token);
      return null;
    }
    return lock;
  }

  @override
  Future<List<DavLock>> getLocks(final String path) async {
    final tokens = <String>{..._getPathTokens(path)};
    final locks = <DavLock>[];

    // Include locks on ancestor paths that extend to this resource
    for (final key in _db.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith(_pathPrefix)) {
        final lockPath = keyStr.substring(_pathPrefix.length);
        if (lockPath != path && _isAncestor(lockPath, path)) {
          tokens.addAll(_getPathTokens(lockPath));
        }
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

    _db[_tokenKey(token)] = jsonEncode(_serialize(updated));
    return updated;
  }

  @override
  Future<bool> removeLock(final String token) async {
    final data = _db[_tokenKey(token)];
    if (data == null) return false;

    final lock = _deserialize(data);
    if (lock != null) {
      // Remove from token index
      _db.remove(_tokenKey(token));

      // Remove from path index
      final tokens = _getPathTokens(lock.path);
      tokens.remove(token);
      _setPathTokens(lock.path, tokens);

      return true;
    }
    return false;
  }

  @override
  Future<void> removeExpiredLocks() async {
    final expired = <String>[];

    for (final key in _db.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith(_tokenPrefix)) {
        final lock = _deserialize(_db[key]);
        if (lock != null && lock.isExpired) {
          expired.add(lock.token);
        }
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
    _timer?.cancel();
    // Only close database if we own it (not shared)
    if (_owned) {
      _db.close();
    }
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
