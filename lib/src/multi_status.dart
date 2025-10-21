import 'package:xml/xml.dart';

import 'dav_utils.dart';

/// Represents a single resource status in a Multi-Status response
class ResourceStatus {
  final String href;
  final int statusCode;
  final String? error;

  const ResourceStatus({
    required this.href,
    required this.statusCode,
    this.error,
  });

  factory ResourceStatus.success(final String href) =>
      ResourceStatus(href: href, statusCode: 200);

  factory ResourceStatus.notFound(final String href, {final String? error}) =>
      ResourceStatus(href: href, statusCode: 404, error: error);

  factory ResourceStatus.forbidden(final String href, {final String? error}) =>
      ResourceStatus(href: href, statusCode: 403, error: error);

  factory ResourceStatus.conflict(final String href, {final String? error}) =>
      ResourceStatus(href: href, statusCode: 409, error: error);

  factory ResourceStatus.locked(final String href, {final String? error}) =>
      ResourceStatus(href: href, statusCode: 423, error: error);

  factory ResourceStatus.failed(final String href, {final String? error}) =>
      ResourceStatus(href: href, statusCode: 500, error: error);

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Builder for WebDAV 207 Multi-Status responses
///
/// Used when an operation affects multiple resources and some succeed while others fail.
/// Per RFC 4918, operations like COPY, MOVE, and DELETE on collections should return
/// 207 Multi-Status when partial failures occur.
class MultiStatusBuilder {
  final List<ResourceStatus> _statuses = [];

  /// Add a status for a resource
  void add(final ResourceStatus status) {
    _statuses.add(status);
  }

  /// Add a successful operation
  void addSuccess(final String href) {
    _statuses.add(ResourceStatus.success(href));
  }

  /// Add a failed operation
  void addFailure(
    final String href,
    final int statusCode, {
    final String? error,
  }) {
    _statuses
        .add(ResourceStatus(href: href, statusCode: statusCode, error: error));
  }

  /// Check if there are any failures
  bool get hasFailures => _statuses.any((s) => !s.isSuccess);

  /// Check if all operations succeeded
  bool get allSucceeded => _statuses.every((s) => s.isSuccess);

  /// Get the count of statuses
  int get count => _statuses.length;

  /// Build a 207 Multi-Status XML response
  ///
  /// Example output:
  /// ```xml
  /// <?xml version="1.0" encoding="utf-8" ?>
  /// <D:multistatus xmlns:D="DAV:">
  ///   <D:response>
  ///     <D:href>/container/resource1</D:href>
  ///     <D:status>HTTP/1.1 200 OK</D:status>
  ///   </D:response>
  ///   <D:response>
  ///     <D:href>/container/resource2</D:href>
  ///     <D:status>HTTP/1.1 423 Locked</D:status>
  ///     <D:responsedescription>Resource is locked</D:responsedescription>
  ///   </D:response>
  /// </D:multistatus>
  /// ```
  String build() {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element(
      'multistatus',
      namespace: 'DAV:',
      namespaces: {'D': 'DAV:'},
      nest: () {
        for (final status in _statuses) {
          builder.element(
            'response',
            namespace: 'DAV:',
            nest: () {
              builder.element('href', namespace: 'DAV:', nest: status.href);
              builder.element(
                'status',
                namespace: 'DAV:',
                nest:
                    'HTTP/1.1 ${status.statusCode} ${_statusMessage(status.statusCode)}',
              );
              if (status.error != null) {
                builder.element(
                  'responsedescription',
                  namespace: 'DAV:',
                  nest: status.error,
                );
              }
            },
          );
        }
      },
    );

    return builder.buildDocument().toXmlString(pretty: true);
  }

  static String _statusMessage(final int code) => statusMessage(code);
}
