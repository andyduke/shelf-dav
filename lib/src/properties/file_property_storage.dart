import 'dart:async';
import 'dart:convert';
import 'package:file/file.dart';
import 'package:shelf_dav/src/properties/property_storage.dart';

/// File-based property storage implementation
///
/// Properties are stored in hidden JSON files next to the resource:
/// - For file: /path/to/file.txt -> /path/to/.file.txt.properties
/// - For directory: /path/to/dir -> /path/to/.dir.properties
///
/// This allows properties to persist across server restarts and
/// be backed up with the files themselves.
class FilePropertyStorage implements PropertyStorage {
  final FileSystem _filesystem;
  final String suffix;

  FilePropertyStorage(
    this._filesystem, {
    this.suffix = '.properties',
  });

  @override
  Future<Map<String, DavProperty>> getProperties(final String path) async {
    final file = _properties(path);
    if (!await file.exists()) {
      return {};
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final result = <String, DavProperty>{};

      json.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = DavProperty(
            namespace: value['namespace'] as String? ?? '',
            name: value['name'] as String,
            value: value['value'] as String,
          );
        }
      });

      return result;
    } catch (e) {
      // If file is corrupted, return empty map
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
    final qualifiedName = _qualifiedName(namespace, name);
    return properties[qualifiedName];
  }

  @override
  Future<bool> setProperty(
    final String path,
    final DavProperty property,
  ) async {
    final properties = await getProperties(path);
    properties[property.qualifiedName] = property;
    await _saveProperties(path, properties);
    return true;
  }

  @override
  Future<bool> removeProperty(
    final String path,
    final String namespace,
    final String name,
  ) async {
    final properties = await getProperties(path);
    final qualifiedName = _qualifiedName(namespace, name);
    final removed = properties.remove(qualifiedName) != null;

    if (removed) {
      if (properties.isEmpty) {
        await _deletePropertyFile(path);
      } else {
        await _saveProperties(path, properties);
      }
    }

    return removed;
  }

  @override
  Future<void> removeAllProperties(final String path) async {
    await _deletePropertyFile(path);
  }

  @override
  Future<void> moveProperties(
    final String from,
    final String to,
  ) async {
    final source = _properties(from);
    if (await source.exists()) {
      final destination = _properties(to);
      // Ensure parent directory exists
      final parent = destination.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await source.rename(destination.path);
    }
  }

  @override
  Future<void> copyProperties(
    final String from,
    final String to,
  ) async {
    final source = _properties(from);
    if (await source.exists()) {
      final destination = _properties(to);
      // Ensure parent directory exists
      final parent = destination.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await source.copy(destination.path);
    }
  }

  @override
  Future<bool> hasProperties(final String path) async {
    final file = _properties(path);
    return file.exists();
  }

  @override
  Future<int> countProperties(final String path) async {
    final properties = await getProperties(path);
    return properties.length;
  }

  @override
  Future<void> close() async {}

  File _properties(final String path) {
    final file = _filesystem.file(path);
    final parent = file.parent;
    final basename = file.basename;
    final hidden = '.$basename$suffix';
    return parent.childFile(hidden);
  }

  Future<void> _saveProperties(
    final String path,
    final Map<String, DavProperty> properties,
  ) async {
    final file = _properties(path);
    final parent = file.parent;

    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final json = <String, dynamic>{};
    properties.forEach((key, prop) {
      json[key] = {
        'namespace': prop.namespace,
        'name': prop.name,
        'value': prop.value,
      };
    });

    final content = jsonEncode(json);
    await file.writeAsString(content);
  }

  Future<void> _deletePropertyFile(final String path) async {
    final file = _properties(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _qualifiedName(final String namespace, final String name) =>
      qualifiedPropertyName(namespace, name);
}
