import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';

PrivateMessage message(String senderId, DateTime sentAt, {bool read = false}) {
  return PrivateMessage(senderId, 'text', sentAt, sentAt, read);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_conversation_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    for (final name in ['privateMessages', 'conversations', 'user']) {
      await Hive.openBox(name);
      await Hive.box(name).clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('unread counts only incoming unread messages', () async {
    final base = DateTime(2026, 5, 1, 12);
    await CacheUtils.addPrivateMessages('peer', [
      message('peer', base),
      message('peer', base.add(const Duration(minutes: 1))),
      message('peer', base.add(const Duration(minutes: 2)), read: true),
      message('me', base.add(const Duration(minutes: 3)), read: true),
    ]);

    final counts = await CacheUtils.getUnreadCounts();
    expect(counts['peer'], 2);
    expect(await CacheUtils.firstUnreadSentAt('peer'), base);
  });

  test('a read conversation has no anchor', () async {
    await CacheUtils.addPrivateMessages(
        'peer', [message('peer', DateTime(2026, 5, 1), read: true)]);
    expect(await CacheUtils.firstUnreadSentAt('peer'), isNull);
  });

  test('pin and unpin keep the box clean', () async {
    expect(await CacheUtils.isConversationPinned('peer'), isFalse);

    await CacheUtils.setConversationPinned('peer', true);
    expect(await CacheUtils.isConversationPinned('peer'), isTrue);
    expect(await CacheUtils.getPinnedConversations(), {'peer'});

    await CacheUtils.setConversationPinned('peer', false);
    expect(await CacheUtils.isConversationPinned('peer'), isFalse);
    expect(await CacheUtils.getPinnedConversations(), isEmpty);
    // Unpinning removes the entry instead of storing a false flag.
    expect(Hive.box('conversations').containsKey('peer'), isFalse);
  });

  test('pinned conversations sort before newer ones', () async {
    final base = DateTime(2026, 5, 1, 12);
    await CacheUtils.addPrivateMessages('old', [message('old', base)]);
    await CacheUtils.addPrivateMessages('new', [
      message('new', base.add(const Duration(hours: 1))),
    ]);

    var chats = await CacheUtils.getLatestPrivateMessages();
    expect(chats.keys.first.id, 'new');

    await CacheUtils.setConversationPinned('old', true);
    chats = await CacheUtils.getLatestPrivateMessages();
    expect(chats.keys.first.id, 'old');
  });

  test('deleting a chat drops its pin', () async {
    await CacheUtils.addPrivateMessages(
        'peer', [message('peer', DateTime(2026, 5, 1))]);
    await CacheUtils.setConversationPinned('peer', true);

    await CacheUtils.deletePrivateMessagesWithUser('peer');

    expect(await CacheUtils.getPinnedConversations(), isEmpty);
  });

  test('the chat list gets cursors only from chats with receipts on', () async {
    final readAt = DateTime(2026, 5, 1, 12, 0, 0, 123, 456);
    await CacheUtils.setPeerReadAt('on', readAt);
    await CacheUtils.setReadReceiptsEnabled('on', true);
    await CacheUtils.setPeerReadAt('off', readAt);

    expect(await CacheUtils.peerReadAts(), {'on': readAt});
  });
}
