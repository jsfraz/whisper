import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/utils/live_location.dart';
import 'package:whisper/utils/presence.dart';
import 'package:whisper/widgets/live_location_bubble.dart';

void main() {
  final peer = User('2', 'peer', '', false);
  final presence = PresenceNotifier.instance;

  setUp(presence.clear);
  tearDown(presence.clear);

  testWidgets('no session means no bubble', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LiveLocationBubble(peer))));
    expect(find.byType(InkWell), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the peer sharing location shows one bubble with time left', (
    tester,
  ) async {
    presence.applyLiveLocation(
      peer.id,
      LiveLocationPoint(50.08, 14.42,
          until: DateTime.now().add(const Duration(minutes: 5))),
    );
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LiveLocationBubble(peer))));
    await tester.pump();

    expect(find.textContaining('liveLocationTheirs'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);

    // Unmount and drop the session: both own timers.
    await tester.pumpWidget(const SizedBox());
    presence.clear();
  });
}
