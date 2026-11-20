import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/models/profile.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/singleton.dart';
import 'package:whisper/widgets/chat_bubble.dart';
import 'package:whisper/widgets/media_bubble.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

/// A reaction is toggled on an attachment all the time. When the bubble's clip
/// wrapper came and went with it, the attachment was mounted again from
/// scratch: the decoded frame went away and the photo blinked white before it
/// came back.
void main() {
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==');
  final key = List<int>.generate(32, (i) => i + 1);
  final peer = User('2', 'peer', '', false);
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('whisper_reaction_rebuild');
    Singleton().boxCollectionKey = key;
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  tearDownAll(() async {
    MediaUtils.clearDecryptCache();
    await dir.delete(recursive: true);
  });

  Widget app(PrivateMessage message) => MaterialApp(
        home: Scaffold(
          body: Center(
            child:
                ChatBubble(null, message, null, peer, accentColor: Colors.blue),
          ),
        ),
      );

  testWidgets('reacting to an attachment keeps its image mounted',
      (tester) async {
    final path = '${dir.path}/photo';
    await tester.runAsync(() async {
      await File(path).writeAsBytes(
          await MediaUtils.encryptWith(Uint8List.fromList(png), key));
    });
    final message = PrivateMessage(
      '2',
      '',
      DateTime(2026),
      DateTime(2026),
      true,
      mediaId: 'media-1',
      mediaTypeStr: MediaType.image.name,
      localPath: path,
      width: 100,
      height: 100,
    );

    await tester.pumpWidget(app(message));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(Image), findsOneWidget);
    final before = tester.state(find.byType(MediaBubble));

    // What CacheUtils.setMessageReaction does: same object, a new badge.
    message.reactions = {'1': '👍'};
    await tester.pumpWidget(app(message));
    await tester.pump(const Duration(milliseconds: 16));

    expect(identical(tester.state(find.byType(MediaBubble)), before), isTrue,
        reason: 'the attachment must not be re-mounted by a reaction');
    expect(find.text('👍'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
