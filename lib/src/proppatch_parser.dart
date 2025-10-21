import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';

import 'dav_utils.dart';

/// Represents a PROPPATCH operation (set or remove)
class PropPatchOperation {
  final bool isSet; // true for set, false for remove
  final String namespace;
  final String name;
  final String? value; // null for remove operations

  const PropPatchOperation({
    required this.isSet,
    required this.namespace,
    required this.name,
    this.value,
  });

  @override
  String toString() =>
      isSet ? 'SET {$namespace}$name = $value' : 'REMOVE {$namespace}$name';
}

/// Parse PROPPATCH request body XML
///
/// Example XML:
/// ```xml
/// <?xml version="1.0" ?>
/// <D:propertyupdate xmlns:D="DAV:" xmlns:Z="http://example.com/ns/">
///   <D:set>
///     <D:prop>
///       <Z:author>Jane Doe</Z:author>
///       <Z:status>draft</Z:status>
///     </D:prop>
///   </D:set>
///   <D:remove>
///     <D:prop>
///       <Z:expired-date/>
///     </D:prop>
///   </D:remove>
/// </D:propertyupdate>
/// ```
class PropPatchParser {
  static final _logger = Logger('PropPatchParser');

  /// Parse the PROPPATCH XML body
  static List<PropPatchOperation> parse(final String xmlBody) {
    final operations = <PropPatchOperation>[];

    try {
      final document = XmlDocument.parse(xmlBody);
      final root = document.rootElement;

      for (final child in root.childElements) {
        final localName = child.localName.toLowerCase();
        final isSet = localName == 'set';
        final isRemove = localName == 'remove';

        if (!isSet && !isRemove) continue;

        for (final propElement in child.childElements) {
          if (propElement.localName.toLowerCase() != 'prop') continue;

          for (final property in propElement.childElements) {
            final namespace = property.namespaceUri ?? '';
            final name = property.localName;
            final value = isSet ? property.innerText : null;

            operations.add(
              PropPatchOperation(
                isSet: isSet,
                namespace: namespace,
                name: name,
                value: value,
              ),
            );
          }
        }
      }
    } catch (e) {
      _logger.warning('PROPPATCH XML parse error: $e');
      return [];
    }

    return operations;
  }

  /// Generate a 207 Multi-Status response for PROPPATCH
  static String generateMultiStatusResponse(
    final String href,
    final List<PropertyOperationResult> results,
  ) {
    final byStatus = <int, List<PropertyOperationResult>>{};
    for (final result in results) {
      byStatus.putIfAbsent(result.statusCode, () => []).add(result);
    }

    final namespaces = <String, String>{'DAV:': 'D'};
    var prefixCounter = 0;
    for (final result in results) {
      if (result.namespace.isNotEmpty &&
          result.namespace != 'DAV:' &&
          !namespaces.containsKey(result.namespace)) {
        namespaces[result.namespace] = 'ns$prefixCounter';
        prefixCounter++;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.write('<D:multistatus xmlns:D="DAV:"');

    namespaces.forEach((uri, prefix) {
      if (prefix != 'D') {
        buffer.write(' xmlns:$prefix="$uri"');
      }
    });
    buffer.writeln('>');

    buffer.writeln('  <D:response>');
    buffer.writeln('    <D:href>$href</D:href>');

    byStatus.forEach((statusCode, props) {
      buffer.writeln('    <D:propstat>');
      buffer.writeln('      <D:prop>');

      for (final prop in props) {
        final prefix =
            namespaces[prop.namespace.isEmpty ? 'DAV:' : prop.namespace] ?? 'D';
        buffer.writeln('        <$prefix:${prop.name}/>');
      }

      buffer.writeln('      </D:prop>');
      buffer.writeln(
        '      <D:status>HTTP/1.1 $statusCode ${_statusMessage(statusCode)}</D:status>',
      );

      if (statusCode != 200 && props.first.error != null) {
        buffer.writeln(
          '      <D:responsedescription>${props.first.error}</D:responsedescription>',
        );
      }

      buffer.writeln('    </D:propstat>');
    });

    buffer.writeln('  </D:response>');
    buffer.writeln('</D:multistatus>');

    return buffer.toString();
  }

  static String _statusMessage(final int code) => statusMessage(code);
}
