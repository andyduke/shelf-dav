import 'package:shelf/shelf.dart';

/// Base class for WebDAV validation exceptions
/// These exceptions are converted to HTTP responses by middleware
abstract class DavValidationException implements Exception {
  final Response response;

  const DavValidationException(this.response);

  @override
  String toString() => 'DavValidationException: ${response.statusCode}';
}

/// Thrown when server is in read-only mode
class ReadOnlyException extends DavValidationException {
  ReadOnlyException()
      : super(Response(403, body: 'Server is in read-only mode'));
}

/// Thrown when resource is locked
class ResourceLockedException extends DavValidationException {
  ResourceLockedException()
      : super(
          Response(
            423,
            body: 'Resource is locked. Provide valid lock token in If header.',
          ),
        );
}

/// Thrown when upload size exceeds limit
class UploadSizeLimitException extends DavValidationException {
  UploadSizeLimitException(final int limit)
      : super(
          Response(
            413,
            body: 'Upload size exceeds maximum allowed ($limit bytes)',
          ),
        );
}

/// Thrown when ETag validation fails
class ETagValidationException extends DavValidationException {
  ETagValidationException.notModified() : super(Response.notModified());

  ETagValidationException.preconditionFailed()
      : super(Response(412, body: 'ETag does not match'));
}

/// Thrown when COPY/MOVE validation fails
class CopyMoveValidationException extends DavValidationException {
  CopyMoveValidationException.missingDestination()
      : super(Response(403, body: 'Missing Destination header'));

  CopyMoveValidationException.sameSourceDestination()
      : super(Response(403, body: 'Source and destination are the same'));

  CopyMoveValidationException.destinationExists()
      : super(Response(412, body: 'Destination exists and Overwrite is F'));

  CopyMoveValidationException.invalidDestination()
      : super(Response(403, body: 'Invalid or missing Destination header'));
}

/// Thrown when parent directory validation fails
class ParentValidationException extends DavValidationException {
  ParentValidationException()
      : super(Response(409, body: 'Parent collection does not exist'));
}
