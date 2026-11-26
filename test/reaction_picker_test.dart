import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/models/profile.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/message_actions.dart';
import 'package:shept/utils/singleton.dart';

/// The reaction row marks the emoji this user already picked, so a second tap
/// reads as "take mine back".
void main() {
  final peer = User('2', 'peer', '', false);

  setUpAll(() {
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  testWidgets('my own reaction is the only highlighted emoji', (tester) async {
    final message = PrivateMessage(
        '2', 'ahoj', DateTime(2026), DateTime(2026), true,
        mediaId: null)
      ..id = 'm-1'
      ..reactions = {'1': '❤️', '2': '👍'};

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => MessageActions.showSheet(context, message, peer.id,
                onSelect: () {}),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Six emoji in the row; exactly the heart carries a background.
    final marked = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((button) => button.style != null)
        .toList();
    expect(marked, hasLength(1));
    expect((marked.single.icon as Text).data, '❤️');
    // The row is the way a reaction is given: every chip has to be actionable,
    // not decoration. (Tapping one would call the API, so only the wiring is
    // checked here.)
    expect(
      tester
          .widgetList<IconButton>(find.byType(IconButton))
          .every((button) => button.onPressed != null),
      isTrue,
    );
  });
}
