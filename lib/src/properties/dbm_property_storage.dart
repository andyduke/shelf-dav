import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:libdbm/libdbm.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';

/// DBM-based property storage implementation using libdbm
///
/// Properties are stored in a persistent key-value database.
/// Each resource path maps to a JSON-encoded map of properties.
/// This provides fast, persistent storage across server restarts.
class DbmPropertyStorage implements PropertyStorage {
  final PersistentMap<String, String> _db;
  final String _prefix;

  /// Create a DBM property storage
  /// [path] - path to the database file
  /// [prefix] - optional prefix for all keys (useful for namespacing)
  DbmPropertyStorage(
    final String path, {
    final String prefix = 'prop:',
  })  : _db = PersistentMap<String, String>(
          HashDBM(File(path).openSync(mode: FileMode.append)),
          (key) => Uint8List.fromList(utf8.encode(key)),
          (bytes) => utf8.decode(bytes),
          (value) => Uint8List.fromList(utf8.encode(value)),
          (bytes) => utf8.decode(bytes),
        ),
        _prefix = prefix;

  /// Create from existing PersistentMap instance
  DbmPropertyStorage.fromDb(
    this._db, {
    final String prefix = 'prop:',
  }) : _prefix = prefix;

  /// Get the underlying database (useful for sharing between storage implementations)
  PersistentMap<String, String> get db => _db;

  String _key(final String path) => '$_prefix$path';

  @override
  Future<Map<String, DavProperty>> getProperties(final String path) async {
    final key = _key(path);
    final value = _db[key];

    if (value == null) {
      return {};
    }

    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final result = <String, DavProperty>{};

      json.forEach((qualifiedName, propData) {
        if (propData is Map<String, dynamic>) {
          result[qualifiedName] = DavProperty(
            namespace: propData['namespace'] as String? ?? '',
            name: propData['name'] as String,
            value: propData['value'] as String,
          );
        }
      });

      return result;
    } catch (e) {
      // If data is corrupted, return empty map
      return {};
    }
  }

  @override
  Future<DavProperty?> getProperty(
    final String path,
    final String namespace,
    final String name,
  ) async {
    final properties = await getProperties(path);
    final qualifiedName = qualifiedPropertyName(namespace, name);
    return properties[qualifiedName];
  }

  @override
  Future<bool> setProperty(
    final String path,
    final DavProperty property,
  ) async {
    final properties = await getProperties(path);
    properties[property.qualifiedName] = property;
    await _save(path, properties);
    return true;
  }

  @override
  Future<bool> removeProperty(
    final String path,
    final String namespace,
    final String name,
  ) async {
    final properties = await getProperties(path);
    final qualifiedName = qualifiedPropertyName(namespace, name);
    final removed = properties.remove(qualifiedName) != null;

    if (removed) {
      if (properties.isEmpty) {
        _db.remove(_key(path));
      } else {
        await _save(path, properties);
      }
    }

    return removed;
  }

  @override
  Future<void> removeAllProperties(final String path) async {
    _db.remove(_key(path));
  }

  @override
  Future<void> moveProperties(
    final String from,
    final String to,
  ) async {
    final properties = await getProperties(from);
    if (properties.isNotEmpty) {
      await _save(to, properties);
      _db.remove(_key(from));
    }
  }

  @override
  Future<void> copyProperties(
    final String from,
    final String to,
  ) async {
    final properties = await getProperties(from);
    if (properties.isNotEmpty) {
      await _save(to, properties);
    }
  }

  @override
  Future<bool> hasProperties(final String path) async =>
      _db.containsKey(_key(path));

  @override
  Future<int> countProperties(final String path) async {
    final properties = await getProperties(path);
    return properties.length;
  }

  @override
  Future<void> close() async => _db.close();

  Future<void> _save(
    final String path,
    final Map<String, DavProperty> properties,
  ) async {
    final json = <String, dynamic>{};
    properties.forEach((key, prop) {
      json[key] = {
        'namespace': prop.namespace,
        'name': prop.name,
        'value': prop.value,
      };
    });

    _db[_key(path)] = jsonEncode(json);
  }
}
