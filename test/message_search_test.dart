import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/message_search.dart';

PrivateMessage text(String body, DateTime sentAt, {String? fileName}) {
  return PrivateMessage('peer', body, sentAt, sentAt, true, fileName: fileName);
}

MessageHit hit(String conversation, PrivateMessage message) =>
    MessageHit(conversation, message);

/// Renders a highlighted line back to text, marking matches in brackets, so a
/// test can assert on the split without inspecting styles.
String marked(String text, String needle) => highlightParts(text, needle)
    .map((part) => part.match ? '[${part.text}]' : part.text)
    .join();

void main() {
  final base = DateTime(2026, 6, 1, 12);

  group('text matching', () {
    test('is case-insensitive and matches inside a word', () {
      final query = MessageSearchQuery(text: 'AHOJ');
      expect(query.matches(hit('a', text('tak ahoj tam', base))), isTrue);
      expect(query.matches(hit('a', text('nic', base))), isFalse);
    });

    test('an empty query matches everything', () {
      const query = MessageSearchQuery();
      expect(query.isEmpty, isTrue);
      expect(query.matches(hit('a', text('cokoli', base))), isTrue);
    });

    test('an attachment is findable by its file name', () {
      final query = MessageSearchQuery(text: 'smlouva');
      final message = text('', base, fileName: 'Smlouva-2026.pdf');
      expect(query.matches(hit('a', message)), isTrue);
    });

    test('the conversation filter scopes the search', () {
      final query = MessageSearchQuery(text: 'ahoj', conversationId: 'b');
      expect(query.matches(hit('a', text('ahoj', base))), isFalse);
      expect(query.matches(hit('b', text('ahoj', base))), isTrue);
    });
  });

  group('result ordering', () {
    test('newest first and capped', () {
      final hits = [
        for (var i = 0; i < searchResultLimit + 5; i++)
          hit('a', text('ahoj', base.add(Duration(minutes: i)))),
      ];
      final result =
          filterMessages(hits, const MessageSearchQuery(text: 'ahoj'));
      expect(result.length, searchResultLimit);
      expect(result.first.message.sentAt.isAfter(result.last.message.sentAt),
          isTrue);
    });
  });

  group('snippet', () {
    test('short text is returned as it is', () {
      expect(snippet('ahoj', 'ahoj'), 'ahoj');
    });

    test('long text is cut around the match', () {
      final long = '${'a' * 100} hledané ${'b' * 100}';
      final value = snippet(long, 'hledané', radius: 10);
      expect(value.startsWith('…'), isTrue);
      expect(value.endsWith('…'), isTrue);
      expect(value, contains('hledané'));
      expect(value.length, lessThan(long.length));
    });

    test('a missing needle still returns a short window', () {
      final value = snippet('a' * 200, 'nic');
      expect(value.endsWith('…'), isTrue);
      expect(value.length, 81);
    });
  });

  group('highlighting', () {
    test('no needle is a single plain run', () {
      expect(highlightParts('ahoj', '').single.match, isFalse);
    });

    test('every occurrence is marked, case-insensitively', () {
      expect(marked('Ahoj ahoj AHoj', 'ahoj'), '[Ahoj] [ahoj] [AHoj]');
    });

    test('the text around the matches is preserved', () {
      expect(marked('tak ahoj tam', 'ahoj'), 'tak [ahoj] tam');
    });

    test('a needle that is not there changes nothing', () {
      final parts = highlightParts('tak ahoj tam', 'nic');
      expect(parts.single.text, 'tak ahoj tam');
      expect(parts.single.match, isFalse);
    });
  });
}
