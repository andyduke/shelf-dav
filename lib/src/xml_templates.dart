/// Pre-compiled XML templates for common WebDAV responses
library;

/// Uses string templates instead of XmlBuilder for better performance.
/// All templates are const for compile-time optimization.

/// XML declaration
const xmlDeclaration = '<?xml version="1.0" encoding="utf-8"?>';

/// Namespace declarations
const davNamespace = 'xmlns:D="DAV:"';

/// Multistatus wrapper
String multistatus(final String content) => '''$xmlDeclaration
<D:multistatus $davNamespace>
$content</D:multistatus>''';

/// Response wrapper
String response(final String href, final String propstats) => '''  <D:response>
    <D:href>$href</D:href>
$propstats  </D:response>''';

/// Propstat for success
String propstatSuccess(final String props) => '''    <D:propstat>
      <D:prop>
$props      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>''';

/// Propstat for failure
String propstatFailure(
  final String props,
  final int code,
  final String message,
) =>
    '''    <D:propstat>
      <D:prop>
$props      </D:prop>
      <D:status>HTTP/1.1 $code $message</D:status>
    </D:propstat>''';

/// Common properties
String propContentLength(final int size) =>
    '        <D:getcontentlength>$size</D:getcontentlength>';

String propLastModified(final String date) =>
    '        <D:getlastmodified>$date</D:getlastmodified>';

String propETag(final String etag) => '        <D:getetag>$etag</D:getetag>';

const propResourceTypeFile = '        <D:resourcetype/>';

const propResourceTypeCollection =
    '        <D:resourcetype><D:collection/></D:resourcetype>';

/// Custom property
String customProp(
  final String namespace,
  final String name,
  final String value,
) {
  if (namespace.isEmpty || namespace == 'DAV:') {
    return '        <D:$name>${_escapeXml(value)}</D:$name>';
  }
  return '        <Z:$name xmlns:Z="$namespace">${_escapeXml(value)}</Z:$name>';
}

/// Build complete file response
String fileResponse({
  required final String href,
  required final int size,
  required final String modified,
  required final String etag,
  final List<String> customProps = const [],
}) {
  final props = [
    propContentLength(size),
    propLastModified(modified),
    propETag(etag),
    propResourceTypeFile,
    ...customProps,
  ].join('\n');

  return response(href, propstatSuccess(props));
}

/// Build complete directory response
String directoryResponse({
  required final String href,
  required final String modified,
  final List<String> customProps = const [],
}) {
  final props = [
    propLastModified(modified),
    propResourceTypeCollection,
    ...customProps,
  ].join('\n');

  return response(href, propstatSuccess(props));
}

/// Escape XML special characters
String _escapeXml(final String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Build 207 Multi-Status response with failures
String multiStatusWithFailures(
  final Map<String, ({int code, String error})> failures,
) {
  final responses = <String>[];

  for (final entry in failures.entries) {
    responses.add(
      response(
        entry.key,
        propstatFailure('', entry.value.code, entry.value.error),
      ),
    );
  }

  return multistatus(responses.join('\n'));
}

/// Build OPTIONS response headers
const optionsHeaders = {
  'DAV': '1, 2',
  'Allow':
      'OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, COPY, MOVE, MKCOL, PROPFIND, PROPPATCH, LOCK, UNLOCK',
  'MS-Author-Via': 'DAV',
};

/// Common HTTP status messages (for performance)
const statusMessages = <int, String>{
  200: 'OK',
  201: 'Created',
  204: 'No Content',
  207: 'Multi-Status',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  409: 'Conflict',
  412: 'Precondition Failed',
  413: 'Payload Too Large',
  415: 'Unsupported Media Type',
  423: 'Locked',
  500: 'Internal Server Error',
  501: 'Not Implemented',
  507: 'Insufficient Storage',
};

/// Get status message for code
String statusMessage(final int code) => statusMessages[code] ?? 'Unknown';
