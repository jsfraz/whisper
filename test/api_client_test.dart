import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:whisper/utils/singleton.dart';

void main() {
  // The generated client has no timeout of its own; the app has to install a
  // transport that gives up on a stalled server instead of hanging a future.
  test('the api client uses an explicit http transport', () {
    final api = Singleton.createApiClient('https://chat.example.com');

    expect(api.basePath, 'https://chat.example.com');
    expect(api.client, isA<IOClient>());
  });
}
