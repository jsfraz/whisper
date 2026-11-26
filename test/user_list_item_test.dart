import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/presence.dart';
import 'package:shept/widgets/user_list_item.dart';

Widget app() => MaterialApp(
      home: Scaffold(
        body: UserListItem(User('1', 'peer', 'key', false), () {}),
      ),
    );

/// The presence dot is the only green circle on the row.
final dot = find.byWidgetPredicate((widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration as BoxDecoration).color == const Color(0xFF2E7D32));

void main() {
  final presence = PresenceNotifier.instance;

  setUp(() {
    presence.clear();
    presence.presenceTtl = const Duration(milliseconds: 30);
  });
  tearDown(presence.clear);

  testWidgets('a known online peer gets the badge', (tester) async {
    await tester.pumpWidget(app());
    expect(dot, findsNothing);

    presence.applyPresence('1', online: true);
    await tester.pump();
    expect(dot, findsOneWidget);
    presence.clear();
  });

  testWidgets('an offline peer has no badge and no unknown status', (
    tester,
  ) async {
    presence.applyPresence('1', online: false);
    await tester.pumpWidget(app());
    expect(dot, findsNothing);
  });
}
