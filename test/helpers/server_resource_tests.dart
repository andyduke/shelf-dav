import 'package:http/http.dart';
import 'package:test/test.dart';

void runServerResourceTests(
  void Function(String name, Future<void> Function(String host)) testServer,
) {
  testServer('info', (host) async {
    final response = await get(Uri.parse('$host/info'));
    print(response);
    expect(response.statusCode, 200);
  });

  testServer('404', (host) async {
    var response = await get(Uri.parse('$host/not_here'));
    print(response);
    expect(response.statusCode, 404);
    expect(response.body, 'Route not found');
  });
}
