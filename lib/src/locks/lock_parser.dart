import 'package:xml/xml.dart';
import '../webdav_constants.dart';
import 'lock_storage.dart';

/// Parse LOCK request body XML
class LockParser {
  /// Parse lock scope from XML
  static LockScope? parseScope(final XmlDocument doc) {
    final element = doc.findAllElements('lockscope').firstOrNull;
    if (element == null) return null;

    if (element.findElements('exclusive').isNotEmpty) {
      return LockScope.exclusive;
    }
    if (element.findElements('shared').isNotEmpty) {
      return LockScope.shared;
    }

    return null;
  }

  /// Parse lock type from XML
  static LockType? parseType(final XmlDocument doc) {
    final element = doc.findAllElements('locktype').firstOrNull;
    if (element == null) return null;

    if (element.findElements('write').isNotEmpty) {
      return LockType.write;
    }

    return null;
  }

  /// Parse owner from XML
  static String? parseOwner(final XmlDocument doc) {
    final element = doc.findAllElements('owner').firstOrNull;
    if (element == null) return null;

    final href = element.findElements('href').firstOrNull;
    if (href != null) {
      return href.innerText;
    }

    return element.innerText.trim();
  }

  /// Parse timeout from header
  /// Format: "Second-3600" or "Infinite"
  static Duration? parseTimeout(final String? header) {
    if (header == null || header.isEmpty) return null;

    final value = header.toLowerCase().trim();
    if (value == 'infinite') return null;

    if (value.startsWith('second-')) {
      final seconds = int.tryParse(value.substring(7));
      if (seconds != null) {
        return Duration(seconds: seconds);
      }
    }

    return null;
  }

  /// Generate lock discovery XML
  static String generateLockDiscovery(final DavLock lock, final String href) {
    final scope = lock.scope == LockScope.exclusive ? 'exclusive' : 'shared';
    final depth = lock.depth == WebDAVConstants.infinity
        ? 'infinity'
        : lock.depth.toString();
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<D:prop xmlns:D="DAV:">');
    buffer.writeln('  <D:lockdiscovery>');
    buffer.writeln('    <D:activelock>');
    buffer.writeln('      <D:locktype><D:write/></D:locktype>');
    buffer.writeln('      <D:lockscope><D:$scope/></D:lockscope>');
    buffer.writeln('      <D:depth>$depth</D:depth>');
    if (lock.owner != null) {
      buffer.writeln('      <D:owner>${lock.owner}</D:owner>');
    }
    if (lock.expires != null) {
      final remaining = lock.expires!.difference(DateTime.now()).inSeconds;
      buffer.writeln('      <D:timeout>Second-$remaining</D:timeout>');
    } else {
      buffer.writeln('      <D:timeout>Infinite</D:timeout>');
    }
    buffer.writeln('      <D:locktoken>');
    buffer.writeln('        <D:href>${lock.token}</D:href>');
    buffer.writeln('      </D:locktoken>');
    buffer.writeln('      <D:lockroot>');
    buffer.writeln('        <D:href>$href</D:href>');
    buffer.writeln('      </D:lockroot>');
    buffer.writeln('    </D:activelock>');
    buffer.writeln('  </D:lockdiscovery>');
    buffer.writeln('</D:prop>');

    return buffer.toString();
  }
}
