import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/models/profile.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/utils/singleton.dart';
import 'package:whisper/widgets/media_bubble.dart';

Widget app(PrivateMessage message, {String peer = 'peer'}) => MaterialApp(
      home: Scaffold(
        body: MediaBubble(
          message: message,
          bubbleColor: Colors.grey,
          textColor: Colors.black,
          onRetry: () {},
          canRetry: false,
          conversationUserId: peer,
        ),
      ),
    );

PrivateMessage once({bool mine = false, DateTime? openedAt}) {
  final at = DateTime(2026, 5, 1, 12);
  return PrivateMessage(
    mine ? 'me' : 'peer',
    '',
    at,
    at,
    true,
    mediaTypeStr: 'image',
    downloadStatus: MediaDownloadStatus.pending,
    viewOnce: true,
    openedAt: openedAt,
  );
}

void main() {
  setUp(() {
    Singleton().profile = Profile('http://localhost',
        User('me', 'me', 'key', false), 'key', 'private-key', '', '', true);
  });

  testWidgets('the receiver can still open an unopened attachment', (
    tester,
  ) async {
    await tester.pumpWidget(app(once()));
    expect(find.text('viewOnceOpen'), findsNothing);
    expect(find.text('viewOnceLoad'), findsOneWidget);
  });

  testWidgets('an opened attachment is a read-only tombstone', (tester) async {
    await tester.pumpWidget(app(once(openedAt: DateTime(2026, 5, 1, 12, 5))));
    expect(find.text('viewOnceOpened'), findsOneWidget);
    expect(find.text('viewOnceLoad'), findsNothing);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('the sender never gets a way to open its own attachment', (
    tester,
  ) async {
    await tester.pumpWidget(app(once(mine: true)));
    expect(find.text('viewOnceSent'), findsOneWidget);
    expect(find.text('viewOnceOpen'), findsNothing);
    expect(find.text('viewOnceLoad'), findsNothing);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('the sender sees the opened state once the peer opened it', (
    tester,
  ) async {
    await tester.pumpWidget(
        app(once(mine: true, openedAt: DateTime(2026, 5, 1, 12, 5))));
    expect(find.text('viewOnceOpenedByPeer'), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('the self-chat can still open its own attachment', (
    tester,
  ) async {
    await tester.pumpWidget(app(once(mine: true), peer: 'me'));
    expect(find.text('viewOnceLoad'), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
  });

  testWidgets('a downloaded album is ready to open, not stuck on download', (
    tester,
  ) async {
    // An album keeps its copies per item: the message itself has no localPath.
    final album = once();
    album.setAlbum([
      AlbumItem(mediaId: 'a', type: 'image', size: 10, localPath: '/a'),
      AlbumItem(mediaId: 'b', type: 'video', size: 20, localPath: '/b'),
    ]);
    await tester.pumpWidget(app(album));
    expect(find.text('viewOnceOpen'), findsOneWidget);
    expect(find.text('viewOnceLoad'), findsNothing);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
  });

  testWidgets('an album missing a copy still offers the download', (
    tester,
  ) async {
    final album = once();
    album.setAlbum([
      AlbumItem(mediaId: 'a', type: 'image', size: 10, localPath: '/a'),
      AlbumItem(mediaId: 'b', type: 'video', size: 20),
    ]);
    await tester.pumpWidget(app(album));
    expect(find.text('viewOnceLoad'), findsOneWidget);
  });
}
