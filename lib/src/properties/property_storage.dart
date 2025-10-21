import 'dart:async';

/// Represents a WebDAV property with namespace and value
class DavProperty {
  final String namespace;
  final String name;
  final String value;

  const DavProperty({
    required this.namespace,
    required this.name,
    required this.value,
  });

  String get qualifiedName => namespace.isEmpty ? name : '{$namespace}$name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DavProperty &&
          namespace == other.namespace &&
          name == other.name &&
          value == other.value;

  @override
  int get hashCode => Object.hash(namespace, name, value);

  @override
  String toString() => 'DavProperty($qualifiedName: $value)';
}

/// Abstract interface for storing and retrieving WebDAV properties
///
/// Properties are stored per-resource (file or directory path).
/// Dead properties (custom properties set by clients) are persisted,
/// while live properties (like getcontentlength) are computed on-demand.
abstract class PropertyStorage {
  /// Get all properties for a resource
  Future<Map<String, DavProperty>> getProperties(final String path);

  /// Get a specific property for a resource
  Future<DavProperty?> getProperty(
    final String path,
    final String namespace,
    final String name,
  );

  /// Set a property for a resource
  /// Returns true if successful, false otherwise
  Future<bool> setProperty(
    final String path,
    final DavProperty property,
  );

  /// Remove a property from a resource
  /// Returns true if the property existed and was removed, false otherwise
  Future<bool> removeProperty(
    final String path,
    final String namespace,
    final String name,
  );

  /// Remove all properties for a resource (called when resource is deleted)
  Future<void> removeAllProperties(final String path);

  /// Move all properties from one path to another (called during MOVE operations)
  Future<void> moveProperties(final String from, final String to);

  /// Copy all properties from one path to another (called during COPY operations)
  Future<void> copyProperties(final String from, final String to);

  /// Check if a resource has any properties (efficient check without loading)
  Future<bool> hasProperties(final String path);

  /// Get count of properties for a resource (efficient without loading values)
  Future<int> countProperties(final String path);

  /// Close/cleanup the storage (e.g., close database connections)
  Future<void> close();
}

/// Result of a property operation for use in Multi-Status responses
class PropertyOperationResult {
  final String namespace;
  final String name;
  final bool success;
  final String? error;
  final int statusCode;

  const PropertyOperationResult({
    required this.namespace,
    required this.name,
    required this.success,
    this.error,
    this.statusCode = 200,
  });

  factory PropertyOperationResult.success(
    final String namespace,
    final String name,
  ) =>
      PropertyOperationResult(
        namespace: namespace,
        name: name,
        success: true,
        statusCode: 200,
      );

  factory PropertyOperationResult.failure(
    final String namespace,
    final String name,
    final int statusCode,
    final String error,
  ) =>
      PropertyOperationResult(
        namespace: namespace,
        name: name,
        success: false,
        statusCode: statusCode,
        error: error,
      );
}

/// Helper function to create a qualified property name
String qualifiedPropertyName(final String namespace, final String name) =>
    namespace.isEmpty ? name : '{$namespace}$name';
