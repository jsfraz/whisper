import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/chat_scroll.dart';

void main() {
  group('windowForAddition', () {
    test('includes the target plus a margin of newer messages', () {
      // 100 messages, target at 40, 5 above it: 100 - 40 + 5.
      expect(windowForAddition(100, 40), 65);
    });

    test('the newest message needs only the margin', () {
      expect(windowForAddition(100, 99), 6);
    });

    test('the oldest message needs the whole conversation', () {
      expect(windowForAddition(100, 0), 100);
    });

    test('never asks for more than there is', () {
      expect(windowForAddition(3, 0), 3);
    });
  });

  group('nextJumpOffset', () {
    test('moves one viewport towards newer messages', () {
      expect(nextJumpOffset(1000, 600), 400);
    });

    test('stops at the newest message instead of going negative', () {
      expect(nextJumpOffset(200, 600), 0);
    });

    test('returns the same offset when already at the newest message', () {
      expect(nextJumpOffset(0, 600), 0);
    });
  });
}
