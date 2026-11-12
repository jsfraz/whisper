import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/klipy_client.dart';

void main() {
  test('parse prefers animated webp and keeps md as the sent format', () {
    const body = '''
{
  "result": true,
  "data": {
    "data": [
      {
        "title": "Hello",
        "slug": "hello-hi-662",
        "file": {
          "hd": {"gif": {"url": "https://x/hd.gif"}},
          "md": {
            "gif": {"url": "https://x/md.gif"},
            "webp": {"url": "https://x/md.webp"}
          },
          "sm": {
            "gif": {"url": "https://x/sm.gif"},
            "webp": {"url": "https://x/sm.webp"}
          }
        }
      },
      {
        "title": "No medium",
        "file": {
          "sm": {"gif": {"url": "https://x/small.gif"}}
        }
      },
      {"title": "Broken", "file": {}},
      "not an object"
    ]
  }
}
''';

    final gifs = KlipyClient.parse(body);

    expect(gifs.length, 2);
    expect(gifs[0].title, 'Hello');
    expect(gifs[0].previewUrl, 'https://x/sm.webp');
    expect(gifs[0].sendUrl, 'https://x/md.webp');
    // Falls back to the small size when there is no medium one.
    expect(gifs[1].previewUrl, 'https://x/small.gif');
    expect(gifs[1].sendUrl, 'https://x/small.gif');
  });

  test('parse returns an empty list for unexpected payloads', () {
    expect(KlipyClient.parse('{}'), isEmpty);
    expect(KlipyClient.parse('{"data": null}'), isEmpty);
  });
}
