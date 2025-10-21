// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:webdav_client/webdav_client.dart';

void runFileResourceTests(
  void Function(String name, Future<void> Function(String host)) testServer,
) {
  testServer('read a file', (host) async {
    var client = newClient(
      host,
      user: 'flyzero',
      password: '123456',
      debug: false,
    );
    final response = await client.read("/dav/index.html");
    expect(response.length, greaterThan(0));
  });

  testServer('copy a file', (host) async {
    var client = newClient(
      host,
      user: 'flyzero',
      password: '123456',
      debug: true,
    );
    await client.remove("/dav/index.htm");
    await client.copy("/dav/index.html", "/dav/index.htm", false);
    final a = await client.read("/dav/index.htm");
    final b = await client.read("/dav/index.htm/");
    expect(a.length, greaterThan(0));
    expect(b.length, equals(a.length));
    await client.remove("/dav/index.htm");
  });
}
