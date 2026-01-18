import 'dart:io';

import 'package:file/file.dart';
import 'package:mime_type/mime_type.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/src/exceptions.dart';
import 'package:shelf_dav/src/utils/http_status.dart';
import 'package:xml/xml.dart';
import 'package:shelf_dav/src/xml_templates.dart' as templates;
import 'package:shelf_dav/src/webdav_constants.dart';
import 'package:shelf_dav/src/utils/etag.dart';

/// Validates that a path is within the root directory
bool isPathWithinRoot(
  final FileSystem fs,
  final String path,
  final String rootPath,
) {
  final resolvedPath = fs.path.absolute(fs.path.normalize(path));
  final resolvedRoot = fs.path.absolute(fs.path.normalize(rootPath));
  return resolvedPath.startsWith(resolvedRoot);
}

/// Check if URI path contains traversal sequences
bool containsPathTraversal(final String path) {
  final lowerPath = path.toLowerCase();

  // Check for various path traversal patterns
  if (path.contains('../')) return true;
  if (path.contains('..\\')) return true;
  if (lowerPath.contains('%2e%2e%2f')) return true; // URL encoded ../
  if (lowerPath.contains('%2e%2e/')) return true;
  if (lowerPath.contains('..%2f')) return true;
  if (lowerPath.contains('%2e%2e%5c')) return true; // URL encoded ..\
  if (lowerPath.contains('%252e%252e%252f')) return true; // Double encoded

  // Check for .. in path segments
  final segments = path.split('/');
  for (final segment in segments) {
    if (segment == '..') return true;
    // URL decoded check
    try {
      final decoded = Uri.decodeComponent(segment);
      if (decoded == '..') return true;
    } catch (_) {
      // Invalid encoding, treat as suspicious
      return true;
    }
  }

  return false;
}

Future<void> file(
  final XmlBuilder builder,
  final Context context,
  final Directory root,
  final File file, {
  final Map<String, dynamic>? customProperties,
}) async {
  final stat = await file.stat();
  final etag = generateETag(file, stat.size, stat.modified, quoted: false);

  // Namespaces are a bad idea, and so is using XML like this.
  builder.element(
    'response',
    namespace: 'DAV:',
    nest: () {
      builder.element(
        'href',
        namespace: 'DAV:',
        nest: () {
          builder.text(href(context, root, file));
        },
      );
      builder.element(
        'propstat',
        namespace: 'DAV:',
        nest: () {
          builder.element(
            'prop',
            namespace: 'DAV:',
            nest: () {
              property(builder, 'displayname', context.basename(file.path));
              if (stat.type != FileSystemEntityType.notFound) {
                property(
                  builder,
                  'getlastmodified',
                  HttpDate.format(stat.modified.toUtc()),
                );
                property(
                  builder,
                  'getcontentlength',
                  stat.size.toString(),
                );
                property(
                  builder,
                  'getcontenttype',
                  mime(file.path) ?? 'application/octet-stream',
                );
                property(
                  builder,
                  'getetag',
                  etag,
                );
                builder.element('resourcetype', namespace: 'DAV:');

                // Add custom properties if provided
                if (customProperties != null) {
                  for (final entry in customProperties.entries) {
                    property(builder, entry.key, entry.value.toString());
                  }
                }
              }
            },
          );
          if (stat.type == FileSystemEntityType.notFound) {
            builder.element(
              'status',
              namespace: 'DAV:',
              nest: () {
                builder.text('HTTP/1.1 404 Not Found');
              },
            );
          } else {
            builder.element(
              'status',
              namespace: 'DAV:',
              nest: () {
                builder.text('HTTP/1.1 200 OK');
              },
            );
          }
        },
      );
    },
  );
}

Future<void> directory(
  final XmlBuilder builder,
  final Context context,
  final Directory root,
  final Directory dir,
  final bool top,
  final int depth,
) async {
  if (depth < -1) return;
  final stat = await dir.stat();
  final etag = generateETag(dir, stat.size, stat.modified, quoted: false);

  builder.element(
    'response',
    namespace: 'DAV:',
    nest: () {
      builder.element(
        'href',
        namespace: 'DAV:',
        nest: () {
          builder.text(href(context, root, dir));
        },
      );
      builder.element(
        'propstat',
        namespace: 'DAV:',
        nest: () {
          builder.element(
            'prop',
            namespace: 'DAV:',
            nest: () {
              property(
                builder,
                'displayname',
                top ? '' : context.basename(dir.path),
              );
              if (stat.type != FileSystemEntityType.notFound) {
                property(
                  builder,
                  'getlastmodified',
                  HttpDate.format(stat.modified.toUtc()),
                );
                property(
                  builder,
                  'getetag',
                  etag,
                );
              }
              builder.element(
                'resourcetype',
                namespace: 'DAV:',
                nest: () {
                  builder.element(
                    'collection',
                    attributes: {'xmlns:D': 'DAV:'},
                    namespace: 'DAV:',
                  );
                },
              );
            },
          );
          if (stat.type == FileSystemEntityType.notFound) {
            builder.element(
              'status',
              namespace: 'DAV:',
              nest: () {
                builder.text('HTTP/1.1 404 Not found');
              },
            );
          } else {
            builder.element(
              'status',
              namespace: 'DAV:',
              nest: () {
                builder.text('HTTP/1.1 200 OK');
              },
            );
          }
        },
      );
    },
  );
  if (stat.type != FileSystemEntityType.notFound && depth > 0) {
    // Collect all children first for parallel processing
    final children = await dir.list().toList();

    // Process children in batches for better performance
    const batchSize = 10; // Process 10 entities at a time
    for (var i = 0; i < children.length; i += batchSize) {
      final batch = children.skip(i).take(batchSize);
      await Future.wait(
        batch.map((child) async {
          if (child is File) {
            await file(builder, context, root, child);
          } else if (child is Directory) {
            await directory(builder, context, root, child, false, depth - 1);
          }
        }),
      );
    }
  }
}

void property(final XmlBuilder builder, final String name, final String value) {
  builder.element(
    name,
    namespace: 'DAV:',
    nest: () {
      builder.text(value);
    },
  );
}

String href(
  final Context context,
  final Directory root,
  final FileSystemEntity entity,
) {
  final fs = root.fileSystem;
  final base = root.absolute.path;
  final path = entity.absolute.path;

  // Use fs.path.relative to properly handle platform differences
  final relativePath = fs.path.relative(path, from: base);

  // Convert filesystem path to URL path (always use forward slashes)
  final urlPath = relativePath.split(fs.path.separator).join('/');

  // Canonicalize and ensure proper prefix
  final result = context.canonicalize(context.join(context.current, urlPath));

  return entity is Directory ? '$result/' : result;
}

/// Parse and validate Depth header
/// Returns depth value, or defaultValue if header is null
/// Valid values: "0", "1", "infinity"
/// Per RFC 4918, PROPFIND defaults to infinity, but other methods may use different defaults
int? parseDepth(final String? header, {final int? defaultValue}) {
  if (header == null) return defaultValue;

  final value = header.toLowerCase().trim();
  if (value == 'infinity') {
    return WebDAVConstants.infinity;
  }

  final parsed = int.tryParse(value);
  if (parsed == null) return null;

  // Limit depth to reasonable maximum
  if (parsed < 0 || parsed > 10) return null;

  return parsed;
}

/// Parse depth header with configurable default
/// Per RFC 4918, PROPFIND defaults to infinity, but most other methods default to 0
int depth(final String? header, {final int defaultValue = 0}) =>
    parseDepth(header, defaultValue: defaultValue) ?? defaultValue;

String canonical(final Context context, final Uri uri) {
  final prefix = context.current;
  final path = Uri.decodeComponent(uri.path);
  final relative = path.startsWith(prefix) ? path : '$prefix/$path';
  final canonical = context.canonicalize(relative);
  final stripped = canonical.replaceFirst(prefix, '');
  final result = stripped.startsWith('/') ? stripped.substring(1) : stripped;
  return result;
}

String local(final FileSystem fs, final String path, {final String? rootPath}) {
  if (rootPath != null) {
    return fs.path.join(rootPath, path);
  }
  return fs.path.absolute(path);
}

/// COPY/MOVE request headers as a Dart 3 record
typedef CopyMoveHeaders = ({Uri destination, bool overwrite, int depth});

/// Parse COPY/MOVE request headers with host/prefix validation
/// Returns null if headers are invalid or destination is outside served namespace
///
/// Parameters:
/// - headers: Request headers
/// - requestUri: The original request URI (to extract host/scheme/port)
/// - prefix: The WebDAV mount prefix (e.g., '/dav')
CopyMoveHeaders? parseCopyMoveHeaders(
  final Map<String, String> headers, {
  final Uri? requestUri,
  final String? prefix,
}) {
  final dest = headers['Destination'];
  if (dest == null || dest.isEmpty) return null;

  // Security: Check for path traversal BEFORE parsing (which normalizes)
  if (containsPathTraversal(dest)) {
    return null;
  }

  // Validate and parse destination URI
  final Uri destination;
  try {
    destination = Uri.parse(dest);
    if (destination.path.isEmpty) return null;

    // Security: Check again AFTER parsing to catch normalized traversal attempts
    if (containsPathTraversal(destination.path)) {
      return null;
    }
    // WebDAV Destination must be an absolute URI (RFC 4918 Section 10.3)
    // It must have a scheme (http/https) or be a valid absolute path starting with /
    if (!destination.hasAbsolutePath && destination.scheme.isEmpty) {
      return null;
    }

    // If destination has a host and we have request context, validate it's the same server
    if (requestUri != null && destination.hasScheme) {
      if (destination.scheme != requestUri.scheme ||
          destination.host != requestUri.host ||
          destination.port != requestUri.port) {
        return null; // Cross-host operations not allowed
      }
    }

    // If prefix is provided, ensure destination path starts with it
    if (prefix != null && prefix.isNotEmpty) {
      if (!destination.path.startsWith(prefix)) {
        return null; // Destination outside served namespace
      }
    }
  } on FormatException {
    return null;
  }

  final overwrite = (headers['Overwrite'] ?? 'T').trim().toUpperCase() == 'T';
  final depthValue = parseDepth(headers['Depth']) ?? WebDAVConstants.infinity;

  return (
    destination: destination,
    overwrite: overwrite,
    depth: depthValue,
  );
}

/// Validate COPY/MOVE destination and overwrite conditions
/// Returns error Response if validation fails, null if valid
Response? validateCopyMove({
  required final Uri uri,
  required final String source,
  required final String destination,
  required final bool exists,
  required final bool overwrite,
}) {
  if (uri.path.isEmpty) {
    return Response(HttpStatus.forbidden, body: 'Missing Destination header');
  }

  if (destination == source) {
    return Response(
      HttpStatus.forbidden,
      body: 'Source and destination are the same',
    );
  }

  if (exists && !overwrite) {
    return Response(
      HttpStatus.preconditionFailed,
      body: 'Destination exists and Overwrite is F',
    );
  }

  return null;
}

/// Ensure COPY/MOVE destination and overwrite conditions are valid
/// Throws CopyMoveValidationException if validation fails
void ensureCopyMove({
  required final Uri uri,
  required final String source,
  required final String destination,
  required final bool exists,
  required final bool overwrite,
}) {
  if (uri.path.isEmpty) {
    throw CopyMoveValidationException.missingDestination();
  }

  if (destination == source) {
    throw CopyMoveValidationException.sameSourceDestination();
  }

  if (exists && !overwrite) {
    throw CopyMoveValidationException.destinationExists();
  }
}

/// Parse and validate COPY/MOVE headers, throwing exception on failure
/// Throws CopyMoveValidationException if parsing or validation fails
CopyMoveHeaders parseCopyMoveHeadersOrThrow(
  final Map<String, String> headers, {
  final Uri? uri,
  final String? prefix,
}) {
  final result = parseCopyMoveHeaders(headers, requestUri: uri, prefix: prefix);
  if (result == null) {
    throw CopyMoveValidationException.invalidDestination();
  }
  return result;
}

/// Returns HTTP status message for status code (optimized via templates)
String statusMessage(final int code) => templates.statusMessage(code);

/// Validate that parent directory exists for target path
/// Returns Response with conflict error if parent doesn't exist, null if valid
Future<Response?> validateParentExists(
  final FileSystemEntity target,
) async {
  final parent = target.parent;
  if (!await parent.exists()) {
    return Response(
      HttpStatus.conflict,
      body: 'Parent collection does not exist',
    );
  }
  return null;
}

/// Ensure parent directory exists for target path
/// Throws ParentValidationException if parent doesn't exist
Future<void> ensureParentExists(
  final FileSystemEntity target,
) async {
  final parent = target.parent;
  if (!await parent.exists()) {
    throw ParentValidationException();
  }
}
