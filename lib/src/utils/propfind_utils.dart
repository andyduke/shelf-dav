import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:xml/xml.dart';

/// Build a complete PROPFIND multi-status response from response elements
/// This utility reduces XML boilerplate duplication between file and directory resources
Response buildPropfindResponse(final XmlBuilder responses) {
  final builder = XmlBuilder(optimizeNamespaces: true)
    ..declaration(version: '1.0', encoding: 'UTF-8')
    ..namespace('DAV:', 'D');

  builder.element(
    'multistatus',
    namespace: 'DAV:',
    attributes: {'xmlns:D': 'DAV:'},
    nest: () {
      for (final node in responses.buildDocument().children) {
        builder.xml(node.toXmlString());
      }
    },
  );

  return Response(
    207,
    body: builder.buildDocument().toXmlString(pretty: true),
    headers: {'Content-type': 'application/xml'},
  );
}

/// Build response headers with standard file metadata
Map<String, String> buildMetadataHeaders({
  required final String etag,
  required final DateTime modified,
  final int? length,
  final String? contentType,
  final String? location,
}) {
  final headers = <String, String>{
    'ETag': etag,
    'Last-Modified': HttpDate.format(modified),
  };

  if (length != null) {
    headers['Content-Length'] = length.toString();
  }

  if (contentType != null) {
    headers['Content-Type'] = contentType;
  }

  if (location != null) {
    headers['Location'] = location;
  }

  return headers;
}
