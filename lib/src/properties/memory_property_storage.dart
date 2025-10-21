import 'dart:async';
import 'package:shelf_dav/src/properties/property_storage.dart';

/// In-memory property storage implementation
///
/// Properties are stored in memory and lost when the server restarts.
/// Useful for development, testing, or when persistent properties aren't needed.
class MemoryPropertyStorage implements PropertyStorage {
  // Map of path -> (qualified property name -> property)
  final Map<String, Map<String, DavProperty>> _storage = {};

  @override
  Future<Map<String, DavProperty>> getProperties(final String path) async =>
      Map.from(_storage[path] ?? {});

  @override
  Future<DavProperty?> getProperty(
    final String path,
    final String namespace,
    final String name,
  ) async {
    final qualified = qualifiedPropertyName(namespace, name);
    return _storage[path]?[qualified];
  }

  @override
  Future<bool> setProperty(
    final String path,
    final DavProperty property,
  ) async {
    final qualifiedName = property.qualifiedName;
    _storage.putIfAbsent(path, () => {});
    _storage[path]![qualifiedName] = property;
    return true;
  }

  @override
  Future<bool> removeProperty(
    final String path,
    final String namespace,
    final String name,
  ) async {
    final qualified = qualifiedPropertyName(namespace, name);
    final props = _storage[path];
    if (props == null) return false;

    final removed = props.remove(qualified) != null;
    if (props.isEmpty) {
      _storage.remove(path);
    }
    return removed;
  }

  @override
  Future<void> removeAllProperties(final String path) async {
    _storage.remove(path);
  }

  @override
  Future<void> moveProperties(
    final String from,
    final String to,
  ) async {
    final properties = _storage.remove(from);
    if (properties != null && properties.isNotEmpty) {
      _storage[to] = properties;
    }
  }

  @override
  Future<void> copyProperties(
    final String from,
    final String to,
  ) async {
    final properties = _storage[from];
    if (properties != null && properties.isNotEmpty) {
      _storage[to] = Map.from(properties);
    }
  }

  @override
  Future<bool> hasProperties(final String path) async {
    final props = _storage[path];
    return props != null && props.isNotEmpty;
  }

  @override
  Future<int> countProperties(final String path) async {
    final props = _storage[path];
    return props?.length ?? 0;
  }

  @override
  Future<void> close() async {}

  /// Get the number of resources with properties (for debugging/testing)
  int get resourceCount => _storage.length;

  /// Get the total number of properties across all resources (for debugging/testing)
  int get propertyCount =>
      _storage.values.fold(0, (sum, props) => sum + props.length);

  /// Clear all properties (for testing)
  void clear() {
    _storage.clear();
  }
}
