import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/message_actions.dart';

/// The reaction list groups by emoji, so one emoji with several participants is
/// one row with their names, and the busiest row is on top.
void main() {
  test('reactions group by emoji, most used first', () {
    final rows = MessageActions.groupReactions(
      {'me': '❤️', 'a': '👍', 'b': '👍', 'c': '❤️', 'd': '👍'},
      (id) =>
          {'me': 'Me', 'a': 'Adam', 'b': 'Bea', 'c': 'Cyril', 'd': 'Dana'}[id]!,
    );

    expect(rows.map((row) => row.key), ['👍', '❤️']);
    expect(rows.first.value, ['Adam', 'Bea', 'Dana']);
    expect(rows.last.value, ['Me', 'Cyril']);
  });

  test('an empty map has no rows', () {
    expect(MessageActions.groupReactions(const {}, (id) => id), isEmpty);
  });
}
