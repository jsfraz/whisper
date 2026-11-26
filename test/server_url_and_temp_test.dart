import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/media_utils.dart';
import 'package:shept/utils/utils.dart';

void main() {
  group('server url policy', () {
    test('https is always allowed', () {
      expect(Utils.isAllowedServerUrl('https://chat.example.com'), isTrue);
      expect(Utils.isAllowedServerUrl('https://192.168.1.2:8081'), isTrue);
    });

    test('plain http is a debug-only convenience', () {
      // Unit tests run in debug mode, so this asserts the debug branch.
      expect(Utils.isAllowedServerUrl('http://192.168.1.118:8080'), isTrue);
    });

    test('anything that is not a server address is refused', () {
      expect(Utils.isAllowedServerUrl(''), isFalse);
      expect(Utils.isAllowedServerUrl('not a url'), isFalse);
      expect(Utils.isAllowedServerUrl('ftp://example.com'), isFalse);
      expect(Utils.isAllowedServerUrl('file:///etc/passwd'), isFalse);
      expect(Utils.isAllowedServerUrl('https://'), isFalse);
    });
  });

  group('plaintext temp media', () {
    test('only the app temp files are swept', () {
      expect(MediaUtils.isTempMediaName('shept_media_abc.mp4'), isTrue);
      expect(MediaUtils.isTempMediaName('shept_send_abc.gif'), isTrue);
      expect(MediaUtils.isTempMediaName('shared_prefs.xml'), isFalse);
      expect(MediaUtils.isTempMediaName('shept.sqlite'), isFalse);
    });
  });
}
