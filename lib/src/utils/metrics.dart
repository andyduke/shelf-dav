/// Metrics collector for WebDAV server operations
///
/// Tracks performance metrics including:
/// - Request counts by method
/// - Cache hit rates
/// - Response times
/// - Error rates
class Metrics {
  // Request counters
  final _requestCounts = <String, int>{};
  final _errorCounts = <String, int>{};

  // Response time tracking
  final _responseTimes = <String, List<Duration>>{};

  // Cache metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;

  // Timestamps
  final DateTime _startTime = DateTime.now();

  /// Record a request
  void recordRequest(final String method) {
    _requestCounts[method] = (_requestCounts[method] ?? 0) + 1;
  }

  /// Record an error response
  void recordError(final String method, final int statusCode) {
    final key = '$method:$statusCode';
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
  }

  /// Record response time
  void recordResponseTime(final String method, final Duration elapsed) {
    _responseTimes.putIfAbsent(method, () => []).add(elapsed);
  }

  /// Record cache hit
  void recordCacheHit() {
    _cacheHits++;
  }

  /// Record cache miss
  void recordCacheMiss() {
    _cacheMisses++;
  }

  /// Get total request count
  int get totalRequests =>
      _requestCounts.values.fold(0, (sum, count) => sum + count);

  /// Get request count by method
  int requestCount(final String method) => _requestCounts[method] ?? 0;

  /// Get total error count
  int get totalErrors =>
      _errorCounts.values.fold(0, (sum, count) => sum + count);

  /// Get cache hit rate (0.0 to 1.0)
  double get cacheHitRate {
    final total = _cacheHits + _cacheMisses;
    return total == 0 ? 0.0 : _cacheHits / total;
  }

  /// Get average response time for a method
  Duration? avgResponseTime(final String method) {
    final times = _responseTimes[method];
    if (times == null || times.isEmpty) return null;

    final total = times.fold(0, (sum, dur) => sum + dur.inMicroseconds);
    return Duration(microseconds: total ~/ times.length);
  }

  /// Get uptime
  Duration get uptime => DateTime.now().difference(_startTime);

  /// Get requests per second
  double get requestsPerSecond {
    final seconds = uptime.inSeconds;
    return seconds == 0 ? 0.0 : totalRequests / seconds;
  }

  /// Get snapshot of all metrics as a record
  MetricsSnapshot snapshot() => (
        totalRequests: totalRequests,
        totalErrors: totalErrors,
        requestsByMethod: Map.from(_requestCounts),
        errorsByType: Map.from(_errorCounts),
        cacheHits: _cacheHits,
        cacheMisses: _cacheMisses,
        cacheHitRate: cacheHitRate,
        uptime: uptime,
        requestsPerSecond: requestsPerSecond,
        avgResponseTimes: _computeAvgResponseTimes(),
      );

  Map<String, Duration> _computeAvgResponseTimes() {
    final result = <String, Duration>{};
    for (final entry in _responseTimes.entries) {
      if (entry.value.isEmpty) continue;
      final total = entry.value.fold(0, (sum, dur) => sum + dur.inMicroseconds);
      result[entry.key] = Duration(microseconds: total ~/ entry.value.length);
    }
    return result;
  }

  /// Reset all metrics
  void reset() {
    _requestCounts.clear();
    _errorCounts.clear();
    _responseTimes.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  /// Format metrics as human-readable string
  String format() {
    final snapshot = this.snapshot();
    final buffer = StringBuffer();

    buffer.writeln('=== WebDAV Server Metrics ===');
    buffer.writeln('Uptime: ${_formatDuration(snapshot.uptime)}');
    buffer.writeln('Total Requests: ${snapshot.totalRequests}');
    buffer.writeln('Total Errors: ${snapshot.totalErrors}');
    buffer.writeln(
      'Requests/sec: ${snapshot.requestsPerSecond.toStringAsFixed(2)}',
    );
    buffer.writeln();

    buffer.writeln('Requests by Method:');
    for (final entry in snapshot.requestsByMethod.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    buffer.writeln('Cache Performance:');
    buffer.writeln('  Hits: ${snapshot.cacheHits}');
    buffer.writeln('  Misses: ${snapshot.cacheMisses}');
    buffer.writeln(
      '  Hit Rate: ${(snapshot.cacheHitRate * 100).toStringAsFixed(1)}%',
    );
    buffer.writeln();

    buffer.writeln('Avg Response Times:');
    for (final entry in snapshot.avgResponseTimes.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value.inMilliseconds}ms');
    }

    return buffer.toString();
  }

  String _formatDuration(final Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

/// Snapshot of metrics at a point in time
typedef MetricsSnapshot = ({
  int totalRequests,
  int totalErrors,
  Map<String, int> requestsByMethod,
  Map<String, int> errorsByType,
  int cacheHits,
  int cacheMisses,
  double cacheHitRate,
  Duration uptime,
  double requestsPerSecond,
  Map<String, Duration> avgResponseTimes,
});

/// Shared default metrics instance for backward compatibility
/// Use DAVConfig.metrics to provide per-instance metrics
final defaultMetrics = Metrics();
