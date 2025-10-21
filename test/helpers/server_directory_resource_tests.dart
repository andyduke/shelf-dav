// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:webdav_client/webdav_client.dart';

void runDirectoryResourceTests(
  void Function(String name, Future<void> Function(String host)) testServer,
) {
  testServer('read root directory', (host) async {
    var client = newClient(
      host,
      user: 'flyzero',
      password: '123456',
      debug: false,
    );
    final response = await client.readDir("/dav/");
    expect(response.length, greaterThan(0));
  });
}
