import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/exceptions.dart';

/// Generate an ETag for a file based on its metadata
///
/// ETags are used for cache validation and concurrency control.
/// Format: "size-mtime-hash" where hash is MD5 of the combined values
///
/// Example: "1234-1704067200000-a3f8b9c2"
String generateETag(final File file, final int size, final DateTime modified) {
  final timestamp = modified.millisecondsSinceEpoch;
  final input = '$size-$timestamp-${file.path}';
  final hash = md5.convert(utf8.encode(input)).toString().substring(0, 8);
  return '"$size-$timestamp-$hash"';
}

/// Parse ETag from header value
/// Returns null if invalid format
String? parseETag(final String? header) {
  if (header == null || header.isEmpty) return null;

  // Remove W/ prefix for weak ETags
  final value = header.startsWith('W/') ? header.substring(2) : header;

  // ETags should be quoted
  if (!value.startsWith('"') || !value.endsWith('"')) return null;

  return value;
}

/// Check if an ETag matches any in a comma-separated list
/// Supports * wildcard
bool matchesETag(final String etag, final String? header) {
  if (header == null || header.isEmpty) return false;

  // * matches any ETag
  if (header.trim() == '*') return true;

  // Split by comma and check each ETag
  final tags = header.split(',').map((e) => e.trim());

  for (final tag in tags) {
    final parsed = parseETag(tag);
    if (parsed != null && parsed == etag) {
      return true;
    }
  }

  return false;
}

/// Validate If-Match header
/// Returns true if the request should proceed, false if 412 should be returned
bool validateIfMatch(final String etag, final String? ifMatch) {
  if (ifMatch == null) return true;
  return matchesETag(etag, ifMatch);
}

/// Validate If-None-Match header
/// Returns true if the request should proceed, false if 304/412 should be returned
bool validateIfNoneMatch(final String etag, final String? ifNoneMatch) {
  if (ifNoneMatch == null) return true;
  return !matchesETag(etag, ifNoneMatch);
}

/// Validate ETag preconditions and return error Response if validation fails
/// Returns null if validation passes
Response? validateETagPreconditions({
  required final String etag,
  required final Map<String, String> headers,
}) {
  // Check If-None-Match for 304 Not Modified
  if (!validateIfNoneMatch(etag, headers['If-None-Match'])) {
    return Response.notModified();
  }

  // Check If-Match for precondition
  if (!validateIfMatch(etag, headers['If-Match'])) {
    return Response(412, body: 'ETag does not match');
  }

  return null;
}

/// Ensure ETag preconditions are valid
/// Throws ETagValidationException if validation fails
void ensureETagPreconditions({
  required final String etag,
  required final Map<String, String> headers,
}) {
  // Check If-None-Match for 304 Not Modified
  if (!validateIfNoneMatch(etag, headers['If-None-Match'])) {
    throw ETagValidationException.notModified();
  }

  // Check If-Match for precondition
  if (!validateIfMatch(etag, headers['If-Match'])) {
    throw ETagValidationException.preconditionFailed();
  }
}

/// Get file metadata and generate ETag
/// Combines length, modification time retrieval with ETag generation
Future<({String etag, int length, DateTime modified})> getMetadataAndETag(
  final File file,
) async {
  final length = await file.length();
  final modified = await file.lastModified();
  final etag = generateETag(file, length, modified);
  return (etag: etag, length: length, modified: modified);
}
