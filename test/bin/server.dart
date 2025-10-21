// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf_static/shelf_static.dart' as shelf_static;
import 'package:shelf_dav/shelf_dav.dart';

import '../helpers/filesystem_utils.dart';

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '9090');
  final cascade = Cascade().add(_staticHandler).add(_router.call);
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  var handler = const Pipeline()
      .addMiddleware(
        (handler) => (request) async {
          final response = await handler(request);
          print(response.headers);
          print(response.statusCode);
          return response;
        },
      )
      .addHandler(cascade.handler);
  final server = await shelf_io.serve(
    handler,
    // logRequests().addHandler(ShelfDAV(_filesystem).router), //cascade.handler),
    InternetAddress.anyIPv4, // Allows external connections
    port,
  );

  print('Serving at http://${server.address.host}:${server.port}');
  _watch.start();
}

final _staticHandler = shelf_static.createStaticHandler(
  'test/resources/public',
  defaultDocument: 'index.html',
);
final _filesystem = createMemoryFileSystem();

// Router instance to handler requests.
final _router = shelf_router.Router()
  ..get('/info', _infoHandler)
  ..mount('/dav/', ShelfDAV('/dav', _filesystem.currentDirectory).router.call);

String _jsonEncode(Object? data) =>
    const JsonEncoder.withIndent(' ').convert(data);

const _jsonHeaders = {
  'content-type': 'application/json',
};

final _watch = Stopwatch();

int _requestCount = 0;

final _dartVersion = () {
  final version = Platform.version;
  return version.substring(0, version.indexOf(' '));
}();

Response _infoHandler(Request request) => Response(
      200,
      headers: {
        ..._jsonHeaders,
        'Cache-Control': 'no-store',
      },
      body: _jsonEncode(
        {
          'runtime': _dartVersion,
          'uptime': _watch.elapsed.toString(),
          'requests': ++_requestCount,
        },
      ),
    );
