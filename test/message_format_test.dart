import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/message_format.dart';

/// Renders the parsed pieces back as text, so a test can assert on the whole
/// message without caring how the parser grouped it.
String flat(List<MessagePiece> pieces) => pieces.map((p) => p.text).join();

List<MessagePiece> styled(List<MessagePiece> pieces, MessageStyle style) =>
    pieces.where((p) => p.style == style).toList();

void main() {
  group('inline styles', () {
    test('bold, italic, strike and mono', () {
      final pieces = parseMessage('a **b** *c* ~~d~~ `e` f');
      expect(flat(pieces), 'a b c d e f');
      expect(styled(pieces, MessageStyle.bold).single.text, 'b');
      expect(styled(pieces, MessageStyle.italic).single.text, 'c');
      expect(styled(pieces, MessageStyle.strike).single.text, 'd');
      expect(styled(pieces, MessageStyle.mono).single.text, 'e');
    });

    test('bold wins over italic at the same position', () {
      final pieces = parseMessage('**bold**');
      expect(pieces.single.style, MessageStyle.bold);
      expect(pieces.single.text, 'bold');
    });

    test('spoiler is its own style', () {
      final pieces = parseMessage('there is ||a secret|| here');
      expect(styled(pieces, MessageStyle.spoiler).single.text, 'a secret');
    });

    test('an unclosed marker stays literal', () {
      expect(flat(parseMessage('**unclosed')), '**unclosed');
      expect(flat(parseMessage('a *b')), 'a *b');
    });

    test('empty markers are literal', () {
      expect(flat(parseMessage('****')), '****');
    });

    test('fenced code block becomes one code piece', () {
      final pieces = parseMessage('before\n```\ncode line\n```\nafter');
      final code = styled(pieces, MessageStyle.code).single;
      expect(code.text, 'code line');
      expect(flat(pieces), 'before\ncode line\nafter');
    });

    test('an unterminated fence runs to the end', () {
      final pieces = parseMessage('x\n```\nstill code');
      expect(styled(pieces, MessageStyle.code).single.text, 'still code');
    });
  });

  group('tappable entities', () {
    test('links keep their address', () {
      final pieces = parseMessage('see https://example.com/a now');
      final link = pieces.singleWhere((p) => p.kind == MessageKind.link);
      expect(link.text, 'https://example.com/a');
    });

    test('a phone number is detected', () {
      final pieces = parseMessage('volej +420 123 456 789 díky');
      final phone = pieces.singleWhere((p) => p.kind == MessageKind.phone);
      expect(phone.text, '+420 123 456 789');
    });

    test('a short number is not a phone number', () {
      final pieces = parseMessage('mám 3 kusy');
      expect(pieces.any((p) => p.kind == MessageKind.phone), isFalse);
    });

    test('a street address with a city is detected', () {
      final pieces = parseMessage('bydlím Karlova 12, Praha');
      final address = pieces.singleWhere((p) => p.kind == MessageKind.address);
      expect(address.text, 'Karlova 12, Praha');
    });

    test('a word followed by a number is not an address', () {
      final pieces = parseMessage('Dnes 3 zprávy');
      expect(pieces.any((p) => p.kind == MessageKind.address), isFalse);
    });

    test('formatting and links combine', () {
      final pieces = parseMessage('**přečti** https://example.com');
      expect(styled(pieces, MessageStyle.bold).single.text, 'přečti');
      expect(pieces.singleWhere((p) => p.kind == MessageKind.link).text,
          'https://example.com');
    });
  });

  group('emoji only', () {
    test('a single emoji', () {
      expect(isEmojiOnly('😀'), isTrue);
      expect(emojiCount('😀'), 1);
    });

    test('a short emoji run', () {
      expect(isEmojiOnly('😀🎉👍'), isTrue);
      expect(emojiCount('😀🎉👍'), 3);
    });

    test('skin tone and variation selectors count as one emoji', () {
      expect(isEmojiOnly('👍🏽'), isTrue);
      expect(isEmojiOnly('❤️'), isTrue);
    });

    test('text with an emoji is not emoji only', () {
      expect(isEmojiOnly('ahoj 😀'), isFalse);
    });

    test('digits alone are not an emoji', () {
      expect(isEmojiOnly('123'), isFalse);
    });

    test('empty text is not an emoji', () {
      expect(isEmojiOnly(''), isFalse);
    });
  });
}
