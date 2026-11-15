import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/link_utils.dart';

void main() {
  test('text without a link stays plain', () {
    final parts = splitLinks('ahoj, jak je?');
    expect(parts, [(text: 'ahoj, jak je?', url: null)]);
  });

  test('a link in the middle is split out', () {
    final parts = splitLinks('mrkni na https://example.com/a?b=1 a dej vědět');
    expect(parts.map((p) => p.url), [null, 'https://example.com/a?b=1', null]);
    expect(parts.first.text, 'mrkni na ');
    expect(parts.last.text, ' a dej vědět');
  });

  test('a sentence-final dot is not part of the link', () {
    final parts = splitLinks('viz https://example.com.');
    final link = parts.firstWhere((p) => p.url != null);
    expect(link.url, 'https://example.com');
    expect(parts.last, (text: '.', url: null));
  });

  test('several links and http scheme are handled', () {
    final parts = splitLinks('http://a.cz a https://b.cz/x');
    expect(parts.where((p) => p.url != null).map((p) => p.url),
        ['http://a.cz', 'https://b.cz/x']);
  });

  test('text starting with a link produces no empty plain piece', () {
    final parts = splitLinks('https://example.com');
    expect(parts, hasLength(1));
    expect(parts.single.url, 'https://example.com');
  });
}
