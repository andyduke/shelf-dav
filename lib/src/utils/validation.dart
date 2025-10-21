import 'package:shelf/shelf.dart';

/// Result of a validation check using Dart 3 records
typedef ValidationResult = ({bool ok, Response? error});

/// Create a successful validation result
ValidationResult success() => (ok: true, error: null);

/// Create a failed validation result with error response
ValidationResult failure(final Response error) => (ok: false, error: error);

/// Helper to check validation result and return early if failed
///
/// Example usage:
/// ```dart
/// final check = validateReadOnly();
/// if (!check.ok) return check.error!;
/// ```
extension ValidationExt on ValidationResult {
  /// Returns error if validation failed, null if ok
  Response? get orNull => ok ? null : error;
}
