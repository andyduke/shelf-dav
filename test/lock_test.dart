import 'package:file/memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_dav/shelf_dav.dart';
import 'package:test/test.dart';

void main() {
  group('Lock Storage', () {
    late MemoryLockStorage storage;

    setUp(() {
      storage = MemoryLockStorage();
    });

    tearDown(() async {
      await storage.close();
    });

    test('creates exclusive lock', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
        owner: 'user@example.com',
      );

      expect(lock, isNotNull);
      expect(lock!.token, startsWith('opaquelocktoken:'));
      expect(lock.scope, equals(LockScope.exclusive));
      expect(lock.type, equals(LockType.write));
      expect(lock.owner, equals('user@example.com'));
    });

    test('creates shared lock', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.shared,
        type: LockType.write,
      );

      expect(lock, isNotNull);
      expect(lock!.scope, equals(LockScope.shared));
    });

    test('prevents conflicting exclusive locks', () async {
      final lock1 = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      expect(lock1, isNotNull);

      // Try to create another exclusive lock
      final lock2 = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      expect(lock2, isNull);
    });

    test('allows multiple shared locks', () async {
      final lock1 = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.shared,
        type: LockType.write,
      );

      final lock2 = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.shared,
        type: LockType.write,
      );

      expect(lock1, isNotNull);
      expect(lock2, isNotNull);
    });

    test('prevents exclusive lock when shared lock exists', () async {
      final shared = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.shared,
        type: LockType.write,
      );

      expect(shared, isNotNull);

      final exclusive = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      expect(exclusive, isNull);
    });

    test('retrieves lock by token', () async {
      final created = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      final retrieved = await storage.getLock(created!.token);

      expect(retrieved, isNotNull);
      expect(retrieved!.token, equals(created.token));
      expect(retrieved.path, equals(created.path));
    });

    test('returns null for non-existent token', () async {
      final lock = await storage.getLock('opaquelocktoken:nonexistent');
      expect(lock, isNull);
    });

    test('removes lock', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      expect(lock, isNotNull);

      final removed = await storage.removeLock(lock!.token);
      expect(removed, isTrue);

      final retrieved = await storage.getLock(lock.token);
      expect(retrieved, isNull);
    });

    test('checks if resource is locked', () async {
      expect(await storage.isLocked('/test.txt'), isFalse);

      await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      expect(await storage.isLocked('/test.txt'), isTrue);
    });

    test('validates lock token for modification', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      // Without token
      expect(await storage.canModify('/test.txt', null), isFalse);

      // With correct token
      expect(await storage.canModify('/test.txt', lock!.token), isTrue);

      // With wrong token
      expect(await storage.canModify('/test.txt', 'wrong-token'), isFalse);
    });

    test('handles lock timeout', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
        timeout: const Duration(milliseconds: 100),
      );

      expect(lock, isNotNull);
      expect(lock!.isValid, isTrue);

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 150));

      expect(lock.isExpired, isTrue);
      expect(lock.isValid, isFalse);

      // Should return null for expired lock
      final retrieved = await storage.getLock(lock.token);
      expect(retrieved, isNull);
    });

    test('refreshes lock timeout', () async {
      final lock = await storage.createLock(
        path: '/test.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
        timeout: const Duration(seconds: 1),
      );

      expect(lock, isNotNull);

      final refreshed = await storage.refreshLock(
        lock!.token,
        const Duration(seconds: 10),
      );

      expect(refreshed, isNotNull);
      expect(refreshed!.token, equals(lock.token));
      expect(refreshed.expires, isNot(equals(lock.expires)));
    });

    test('removes expired locks', () async {
      // Create expired lock
      await storage.createLock(
        path: '/test1.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
        timeout: const Duration(milliseconds: 50),
      );

      // Create valid lock
      final valid = await storage.createLock(
        path: '/test2.txt',
        scope: LockScope.exclusive,
        type: LockType.write,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await storage.removeExpiredLocks();

      expect(await storage.isLocked('/test1.txt'), isFalse);
      expect(await storage.isLocked('/test2.txt'), isTrue);
      expect(await storage.getLock(valid!.token), isNotNull);
    });
  });

  group('Lock HTTP Operations', () {
    late ShelfDAV dav;
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
      final dir = fs.directory('/webdav');
      dir.createSync();

      // Create test file
      fs.file('/webdav/test.txt').writeAsStringSync('test content');

      final config = DAVConfig(
        prefix: '/dav',
        root: dir,
        enableLocking: true,
      );

      dav = ShelfDAV.withConfig(config);
    });

    tearDown(() async {
      await dav.close();
    });

    test('LOCK creates exclusive lock', () async {
      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>
    <D:href>http://example.org/~ejw/contact.html</D:href>
  </D:owner>
</D:lockinfo>''';

      final request = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final response = await dav.handler(request);

      expect(response.statusCode, equals(200));
      expect(
        response.headers['Content-Type'],
        contains('application/xml'),
      );
      expect(response.headers['Lock-Token'], isNotNull);
      expect(response.headers['Lock-Token'], startsWith('<opaquelocktoken:'));
      expect(response.headers['Lock-Token'], endsWith('>'));

      final body = await response.readAsString();
      expect(body, contains('<D:lockdiscovery'));
      expect(body, contains('<D:activelock>'));
      expect(body, contains('<D:exclusive/>'));
    });

    test('LOCK with timeout', () async {
      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      final request = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
        headers: {'Timeout': 'Second-3600'},
      );

      final response = await dav.handler(request);

      expect(response.statusCode, equals(200));

      final body = await response.readAsString();
      expect(body, contains('<D:timeout>'));
    });

    test('LOCK returns 423 for locked resource', () async {
      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      // First lock
      final request1 = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final response1 = await dav.handler(request1);
      expect(response1.statusCode, equals(200));

      // Second lock attempt
      final request2 = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final response2 = await dav.handler(request2);
      expect(response2.statusCode, equals(423));
    });

    test('UNLOCK removes lock', () async {
      // Create lock first
      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      final lock = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final locked = await dav.handler(lock);
      expect(locked.statusCode, equals(200));

      final lockToken = locked.headers['Lock-Token']!;

      // Unlock
      final unlock = Request(
        'UNLOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Lock-Token': lockToken},
      );

      final unlocked = await dav.handler(unlock);
      expect(unlocked.statusCode, equals(204));

      // Should be able to lock again
      final lock2 = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final locked2 = await dav.handler(lock2);
      expect(locked2.statusCode, equals(200));
    });

    test('UNLOCK without Lock-Token returns 400', () async {
      final request = Request(
        'UNLOCK',
        Uri.parse('http://localhost/dav/test.txt'),
      );

      final response = await dav.handler(request);
      expect(response.statusCode, equals(400));
    });

    test('UNLOCK with invalid token returns 409', () async {
      final request = Request(
        'UNLOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Lock-Token': '<opaquelocktoken:invalid>'},
      );

      final response = await dav.handler(request);
      expect(response.statusCode, equals(409));
    });

    test('LOCK on non-existent resource', () async {
      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      final request = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/nonexistent.txt'),
        body: lockXml,
      );

      final response = await dav.handler(request);

      // Should succeed and create lock
      expect(response.statusCode, equals(200));
      expect(response.headers['Lock-Token'], isNotNull);
    });

    test('LOCK with depth infinity', () async {
      // Create directory
      fs.directory('/webdav/folder').createSync();

      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      final request = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/folder/'),
        body: lockXml,
        headers: {'Depth': 'infinity'},
      );

      final response = await dav.handler(request);

      expect(response.statusCode, equals(200));

      final body = await response.readAsString();
      expect(body, contains('<D:depth>infinity</D:depth>'));
    });

    test('LOCK/UNLOCK disabled by default returns 405', () async {
      final config = DAVConfig(
        prefix: '/dav',
        root: fs.directory('/webdav'),
        enableLocking: false,
      );

      final dav = ShelfDAV.withConfig(config);
      addTearDown(() async => dav.close());

      final lockXml = '''<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D='DAV:'>
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
</D:lockinfo>''';

      final lock = Request(
        'LOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        body: lockXml,
      );

      final locked = await dav.handler(lock);
      expect(locked.statusCode, equals(405));

      final unlock = Request(
        'UNLOCK',
        Uri.parse('http://localhost/dav/test.txt'),
        headers: {'Lock-Token': '<opaquelocktoken:test>'},
      );

      final unlocked = await dav.handler(unlock);
      expect(unlocked.statusCode, equals(405));
    });
  });
}
