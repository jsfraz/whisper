import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';

/// The local side of the lifecycle: an edit rewrites the stored text, a
/// reaction is a per-user map, a pin lives on the chat, and the mutation cursor
/// only moves forward. All four are what sync and live frames write into.
void main() {
  late Directory dir;
  const peer = 'peer-id';

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_lifecycle_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(PrivateMessageAdapter());
    }
  });

  setUp(() async {
    for (final box in ['privateMessages', 'conversations', 'settings']) {
      await Hive.openBox(box);
      await Hive.box(box).clear();
    }
    final sentAt = DateTime(2026, 11, 19, 12);
    await CacheUtils.addPrivateMessages(peer, [
      PrivateMessage(peer, 'before', sentAt, sentAt, true)..id = 'message-id',
    ]);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('an edit replaces the text and marks the message', () async {
    final editedAt = DateTime(2026, 11, 19, 12, 5);
    await CacheUtils.markMessageEdited(
        peer, DateTime(2026, 11, 19, 12), 'after', editedAt);

    final message = (await CacheUtils.getPrivateMessages(peer)).single;
    expect(message.message, 'after');
    expect(message.isEdited, isTrue);
    expect(message.editedAt, editedAt);
  });

  test('a reaction is set per user, replaced and removed', () async {
    final sentAt = DateTime(2026, 11, 19, 12);
    await CacheUtils.setMessageReaction(peer, sentAt, 'me', '👍');
    await CacheUtils.setMessageReaction(peer, sentAt, 'peer-id', '❤️');

    var message = (await CacheUtils.getPrivateMessages(peer)).single;
    expect(message.reactions, {'me': '👍', 'peer-id': '❤️'});
    expect(message.reactionEmojis, ['❤️', '👍']);

    // The same user reacting again replaces the emoji instead of adding one.
    await CacheUtils.setMessageReaction(peer, sentAt, 'me', '😂');
    message = (await CacheUtils.getPrivateMessages(peer)).single;
    expect(message.reactions, {'me': '😂', 'peer-id': '❤️'});

    await CacheUtils.setMessageReaction(peer, sentAt, 'me', null);
    message = (await CacheUtils.getPrivateMessages(peer)).single;
    expect(message.reactions, {'peer-id': '❤️'});

    await CacheUtils.setMessageReaction(peer, sentAt, 'peer-id', null);
    message = (await CacheUtils.getPrivateMessages(peer)).single;
    expect(message.reactions, isNull);
  });

  test('pins are shared state of the chat and can be replaced', () async {
    await CacheUtils.setConversationPinned(peer, true);
    await CacheUtils.setMessagePinned(
        peer, 'message-id', DateTime(2026, 11, 19, 12, 6));

    var pins = await CacheUtils.getPinnedMessages(peer);
    expect(pins.keys, ['message-id']);
    // The chat being pinned to the top of the list is a different flag and must
    // survive.
    expect(await CacheUtils.isConversationPinned(peer), isTrue);

    // A server page is authoritative: anything missing was unpinned elsewhere.
    await CacheUtils.replacePinnedMessages(peer, {});
    pins = await CacheUtils.getPinnedMessages(peer);
    expect(pins, isEmpty);

    await CacheUtils.setMessagePinned(peer, 'message-id', null);
    expect(await CacheUtils.getPinnedMessages(peer), isEmpty);
  });

  test('the mutation cursor never moves backwards', () async {
    await CacheUtils.setSyncEventSeq(5);
    await CacheUtils.setSyncEventSeq(3);
    expect(await CacheUtils.getSyncEventSeq(), 5);
  });
}
