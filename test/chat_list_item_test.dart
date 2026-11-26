import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/models/profile.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/singleton.dart';
import 'package:shept/widgets/chat_list_item.dart';

Widget app(PrivateMessage last, {DateTime? peerReadAt}) {
  return MaterialApp(
    home: Scaffold(
      body: ChatListItem(User('1', 'peer', 'key', false), last, () {},
          peerReadAt: peerReadAt),
    ),
  );
}

void main() {
  setUp(() {
    Singleton().profile = Profile('http://localhost',
        User('me', 'me', 'key', false), 'key', 'private-key', '', '', true);
  });

  final sentAt = DateTime(2026, 5, 1, 12);
  PrivateMessage own() => PrivateMessage('me', 'text', sentAt, sentAt, false);
  PrivateMessage theirs() => PrivateMessage('1', 'text', sentAt, sentAt, false);

  testWidgets('an own message carries the tick once the cursor covers it',
      (tester) async {
    await tester.pumpWidget(app(own(), peerReadAt: sentAt));
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('no tick while the cursor is behind the message', (tester) async {
    await tester.pumpWidget(
        app(own(), peerReadAt: sentAt.subtract(const Duration(seconds: 1))));
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('an incoming message never carries the tick', (tester) async {
    await tester.pumpWidget(app(theirs(), peerReadAt: sentAt));
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('receipts off means no tick', (tester) async {
    await tester.pumpWidget(app(own()));
    expect(find.byIcon(Icons.done_all), findsNothing);
  });
}
