/// Result of a file system operation (copy, move, delete).
/// Used to decouple operation execution from response building.
typedef FileOperationResult = ({
  String href,
  bool success,
  int statusCode,
  String? error,
});

/// Create a success result
FileOperationResult success(final String href) => (
      href: href,
      success: true,
      statusCode: 200,
      error: null,
    );

/// Create a failure result
FileOperationResult failure(
  final String href,
  final int statusCode, {
  final String? error,
}) =>
    (
      href: href,
      success: false,
      statusCode: statusCode,
      error: error,
    );
