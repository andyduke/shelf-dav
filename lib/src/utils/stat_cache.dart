import 'package:file/file.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/utils/metrics.dart';
import 'package:shelf_dav/src/webdav_constants.dart';

/// Cache entry for file stat results
class _StatCacheEntry {
  final FileStat stat;
  final DateTime cached;

  _StatCacheEntry(this.stat) : cached = DateTime.now();

  bool isExpired(final Duration ttl) => DateTime.now().difference(cached) > ttl;
}

/// Request-scoped cache for file stat operations
///
/// Caches stat results during a single request to avoid repeated filesystem calls.
/// The cache is automatically cleared between requests.
class StatCache {
  final Map<String, _StatCacheEntry> _cache = {};
  final Duration _ttl;
  final Metrics _metrics;
  int _hits = 0;
  int _misses = 0;

  StatCache({
    final Duration ttl = const Duration(seconds: 1),
    final Metrics? metrics,
  })  : _ttl = ttl,
        _metrics = metrics ?? defaultMetrics;

  /// Get cached stat or perform stat and cache result
  Future<FileStat> stat(final FileSystemEntity entity) async {
    final path = entity.path;
    final entry = _cache[path];

    // Return cached if still valid
    if (entry != null && !entry.isExpired(_ttl)) {
      _hits++;
      _metrics.recordCacheHit();
      return entry.stat;
    }

    // Perform stat and cache
    _misses++;
    _metrics.recordCacheMiss();
    final stat = await entity.stat();
    _cache[path] = _StatCacheEntry(stat);
    return stat;
  }

  /// Invalidate cache entry for a path
  void invalidate(final String path) {
    _cache.remove(path);
  }

  /// Clear all cache entries
  void clear() {
    _cache.clear();
  }

  /// Get cache statistics for debugging
  ({int entries, int hits, int misses}) get stats =>
      (entries: _cache.length, hits: _hits, misses: _misses);
}

/// Helper to get StatCache from request context
StatCache? getStatCache(final Request request) =>
    request.context[ContextKeys.statCache] as StatCache?;

/// Perform stat with caching if available
Future<FileStat> cachedStat(
  final FileSystemEntity entity,
  final Request request,
) async {
  final cache = getStatCache(request);
  if (cache != null) {
    return cache.stat(entity);
  }
  // Fallback to direct stat if no cache
  return entity.stat();
}
