import 'dart:async';
import 'dart:io' show HttpConnectionInfo;
import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';

/// Configuration for request throttling
class ThrottleConfig {
  /// Maximum number of concurrent requests (0 = unlimited)
  final int maxConcurrentRequests;

  /// Maximum requests per second per IP (0 = unlimited)
  final int maxRequestsPerSecond;

  /// Time window for rate limiting in seconds
  final int rateLimitWindow;

  const ThrottleConfig({
    this.maxConcurrentRequests = 100,
    this.maxRequestsPerSecond = 500,
    this.rateLimitWindow = 1,
  });

  const ThrottleConfig.unlimited()
      : maxConcurrentRequests = 0,
        maxRequestsPerSecond = 0,
        rateLimitWindow = 1;
}

/// Request throttling middleware
///
/// Provides:
/// - Concurrent request limiting
/// - Per-IP rate limiting
/// - 429 Too Many Requests responses when limits exceeded
class ThrottleMiddleware {
  final ThrottleConfig _config;
  final Logger _logger = Logger('ThrottleMiddleware');

  int _currentRequests = 0;
  final _concurrentLock = Lock();
  final _rateLimits = <String, List<DateTime>>{};
  final _rateLimitLock = Lock();

  Timer? _cleanupTimer;
  ThrottleMiddleware(this._config) {
    _cleanupTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _cleanup());
  }

  /// Create throttling middleware
  Handler call(Handler handler) => (Request request) async {
        if (_config.maxConcurrentRequests > 0) {
          final allowed = await _concurrentLock.synchronized(() {
            if (_currentRequests >= _config.maxConcurrentRequests) {
              return false;
            }
            _currentRequests++;
            return true;
          });

          if (!allowed) {
            _logger.warning(
              'Concurrent request limit reached: $_currentRequests/${_config.maxConcurrentRequests}',
            );
            return Response(
              429,
              body: 'Too many concurrent requests',
              headers: {
                'Retry-After': '1',
                'X-RateLimit-Limit': _config.maxConcurrentRequests.toString(),
                'X-RateLimit-Remaining': '0',
              },
            );
          }
        } else {
          await _concurrentLock.synchronized(() => _currentRequests++);
        }

        final ip = _getClientIp(request);
        if (_config.maxRequestsPerSecond > 0 && ip != null) {
          final allowed = await _checkRateLimit(ip);
          if (!allowed) {
            final remaining = await _getRemainingRequests(ip);
            _logger.warning('Rate limit exceeded for $ip');

            // Decrement concurrent counter since we're rejecting
            await _concurrentLock.synchronized(() => _currentRequests--);

            return Response(
              429,
              body: 'Rate limit exceeded',
              headers: {
                'Retry-After': _config.rateLimitWindow.toString(),
                'X-RateLimit-Limit': _config.maxRequestsPerSecond.toString(),
                'X-RateLimit-Remaining': remaining.toString(),
                'X-RateLimit-Reset':
                    (DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                            _config.rateLimitWindow)
                        .toString(),
              },
            );
          }
        }

        try {
          // Process request
          final response = await handler(request);

          // Add rate limit headers to successful responses
          if (ip != null && _config.maxRequestsPerSecond > 0) {
            final remaining = await _getRemainingRequests(ip);
            return response.change(
              headers: {
                'X-RateLimit-Limit': _config.maxRequestsPerSecond.toString(),
                'X-RateLimit-Remaining': remaining.toString(),
              },
            );
          }

          return response;
        } finally {
          // Decrement concurrent counter (synchronized)
          await _concurrentLock.synchronized(() => _currentRequests--);
        }
      };

  /// Check if request is within rate limit (synchronized)
  Future<bool> _checkRateLimit(final String ip) async =>
      _rateLimitLock.synchronized(() {
        final now = DateTime.now();
        final cutoff = now.subtract(Duration(seconds: _config.rateLimitWindow));

        // Get or create request list for this IP
        final requests = _rateLimits.putIfAbsent(ip, () => <DateTime>[]);

        // Remove old requests outside the window
        requests.removeWhere((time) => time.isBefore(cutoff));

        // Check if under limit
        if (requests.length >= _config.maxRequestsPerSecond) {
          return false;
        }

        // Add this request
        requests.add(now);
        return true;
      });

  /// Get remaining requests for IP (synchronized)
  Future<int> _getRemainingRequests(final String ip) async =>
      _rateLimitLock.synchronized(() {
        final now = DateTime.now();
        final cutoff = now.subtract(Duration(seconds: _config.rateLimitWindow));
        final requests = _rateLimits[ip] ?? [];
        final recent = requests.where((time) => time.isAfter(cutoff)).length;
        return (_config.maxRequestsPerSecond - recent)
            .clamp(0, _config.maxRequestsPerSecond);
      });

  /// Get client IP from request
  String? _getClientIp(final Request request) {
    // Check X-Forwarded-For header (if behind proxy)
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }

    // Check X-Real-IP header
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.isNotEmpty) {
      return realIp;
    }

    // Fall back to connection info (may be null in some contexts)
    final connection = request.context['shelf.io.connection_info'];
    if (connection is HttpConnectionInfo) {
      final address = connection.remoteAddress;
      return address.address;
    }
    return connection?.toString();
  }

  /// Cleanup old rate limit entries (synchronized)
  void _cleanup() {
    _rateLimitLock.synchronized(() {
      final now = DateTime.now();
      final cutoff =
          now.subtract(Duration(seconds: _config.rateLimitWindow * 2));

      _rateLimits.removeWhere((ip, requests) {
        requests.removeWhere((time) => time.isBefore(cutoff));
        return requests.isEmpty;
      });

      _logger.fine('Cleanup: ${_rateLimits.length} IPs tracked');
    });
  }

  /// Dispose of resources
  void dispose() {
    _cleanupTimer?.cancel();
    _rateLimits.clear();
  }
}
