import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/dav_config.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'package:shelf_dav/src/utils/http_status.dart';

/// Validation utilities for WebDAV operations
///
/// Provides reusable validation methods to eliminate code duplication
/// across resource classes.
class ValidationUtils {
  // Private constructor to prevent instantiation
  ValidationUtils._();

  /// Validate upload size against configured limit
  ///
  /// Checks Content-Length header against maxUploadSize in config.
  /// Returns null if validation passes, Response with 413 status if size exceeds limit.
  ///
  /// If maxUploadSize is null, no limit is enforced (unlimited uploads).
  static Response? validateUploadSize(
    final Request request,
    final DAVConfig? config,
  ) {
    final length = int.tryParse(request.headers['Content-Length'] ?? '') ?? 0;
    final limit = config?.maxUploadSize;

    if (limit != null && length > limit) {
      return Response(
        HttpStatus.requestEntityTooLarge,
        body: 'Upload size exceeds maximum allowed ($limit bytes)',
      );
    }

    return null;
  }

  /// Ensure upload size is within configured limit
  ///
  /// Checks Content-Length header against maxUploadSize in config.
  /// Throws UploadSizeLimitException if size exceeds limit.
  ///
  /// If maxUploadSize is null, no limit is enforced (unlimited uploads).
  static void ensureUploadSize(
    final Request request,
    final DAVConfig? config,
  ) {
    final length = int.tryParse(request.headers['Content-Length'] ?? '') ?? 0;
    final limit = config?.maxUploadSize;

    if (limit != null && length > limit) {
      throw UploadSizeLimitException(limit);
    }
  }

  /// Get the effective upload limit
  ///
  /// Returns the configured maxUploadSize, or 0 if unlimited.
  /// The value 0 signals unlimited uploads to downstream processing.
  static int getUploadLimit(final DAVConfig? config) =>
      config?.maxUploadSize ?? 0;
}
