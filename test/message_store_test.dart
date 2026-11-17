import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

PrivateMessage message(String senderId, String text, DateTime sentAt,
    {int sendStatus = SendStatus.sent}) {
  return PrivateMessage(senderId, text, sentAt, sentAt, true,
      mediaTypeStr: MediaType.image.name,
      downloadStatus: MediaDownloadStatus.ready,
      sendStatus: sendStatus);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_message_store_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    await Hive.openBox('pendingSends');
    await Hive.box('pendingSends').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('one key per message: adding a message does not rewrite the chat',
      () async {
    final base = DateTime(2026, 1, 1);
    for (var i = 0; i < 5; i++) {
      await CacheUtils.addPrivateMessages(
          'conv', [message('peer', 'msg $i', base.add(Duration(minutes: i)))]);
    }

    final box = Hive.box('privateMessages');
    expect(box.length, 5, reason: 'every message has its own entry');
    for (final key in box.keys) {
      expect(CacheUtils.conversationOfKey(key), 'conv');
    }
    final stored = await CacheUtils.getPrivateMessages('conv');
    expect(stored.map((m) => m.message),
        ['msg 0', 'msg 1', 'msg 2', 'msg 3', 'msg 4']);
  });

  test('a redelivered message is stored once', () async {
    final sentAt = DateTime(2026, 1, 1);
    final first = message('peer', 'hello', sentAt);
    await CacheUtils.addPrivateMessages('conv', [first]);
    // The server re-sends what was not acknowledged yet.
    await CacheUtils.addPrivateMessages(
        'conv', [message('peer', 'hello', sentAt)]);

    final stored = await CacheUtils.getPrivateMessages('conv');
    expect(stored.length, 1);
  });

  test('deleting the last message of a chat leaves no empty conversation',
      () async {
    final sentAt = DateTime(2026, 1, 2);
    final only = message('peer', 'only one', sentAt);
    await CacheUtils.addPrivateMessages('conv', [only]);

    await CacheUtils.deletePrivateMessage('conv', only);

    expect(await CacheUtils.getPrivateMessages('conv'), isEmpty);
    // This used to throw on `messages.last` and blank the whole chat list.
    expect(await CacheUtils.getLatestPrivateMessages(), isEmpty);
  });

  test('the conversation list shows the newest message per chat', () async {
    final base = DateTime(2026, 2, 1);
    await CacheUtils.addPrivateMessages('a', [
      message('a', 'old', base),
      message('a', 'new', base.add(const Duration(minutes: 5))),
    ]);
    await CacheUtils.addPrivateMessages('b', [
      message('b', 'other', base.add(const Duration(minutes: 1))),
    ]);

    final chats = await CacheUtils.getLatestPrivateMessages();
    final byId = {
      for (final entry in chats.entries) entry.key.id: entry.value.message
    };
    expect(byId['a'], 'new');
    expect(byId['b'], 'other');
  });

  test('a legacy conversation list is migrated into per-message keys',
      () async {
    // Format written by older versions: one list under the user id.
    await Hive.box('privateMessages').put('legacy', [
      message('legacy', 'first', DateTime(2026, 3, 1)),
      message('legacy', 'second', DateTime(2026, 3, 1, 1)),
    ]);

    final chats = await CacheUtils.getLatestPrivateMessages();
    expect(chats.keys.single.id, 'legacy');
    expect(chats.values.single.message, 'second');

    final box = Hive.box('privateMessages');
    expect(box.containsKey('legacy'), isFalse);
    expect(
        box.keys
            .whereType<String>()
            .every((key) => CacheUtils.conversationOfKey(key) == 'legacy'),
        isTrue);
  });

  test('the delivery ack flips the message to sent and clears the marker',
      () async {
    final sentAt = DateTime(2026, 4, 1);
    final outgoing =
        message('peer', 'pending', sentAt, sendStatus: SendStatus.sending);
    await CacheUtils.addPrivateMessages('peer', [outgoing]);
    await CacheUtils.addPendingSend('peer', sentAt);

    expect((await CacheUtils.getPendingSends())['peer'], hasLength(1));

    await CacheUtils.markMessageSent('peer', sentAt);

    final stored = await CacheUtils.getPrivateMessages('peer');
    expect(stored.single.sendStatus, SendStatus.sent);
    expect(await CacheUtils.getPendingSends(), isEmpty);
    expect(Hive.box('pendingSends').isEmpty, isTrue);
  });

  test('a retried message gets a fresh timestamp and keeps its content',
      () async {
    final oldSentAt = DateTime(2026, 4, 3);
    final failed =
        message('peer', 'retry me', oldSentAt, sendStatus: SendStatus.failed);
    await CacheUtils.addPrivateMessages('peer', [failed]);
    await CacheUtils.addPendingSend('peer', oldSentAt);

    final moved = await CacheUtils.retimestampMessage('peer', failed);

    expect(moved, isNotNull);
    expect(moved!.sentAt.isAfter(oldSentAt), isTrue);
    final box = Hive.box('privateMessages');
    expect(box.containsKey(CacheUtils.messageKey('peer', oldSentAt)), isFalse,
        reason: 'the old key is gone, the message is not stored twice');
    final stored = await CacheUtils.getPrivateMessages('peer');
    expect(stored.single.message, 'retry me');
    expect(stored.single.sentAt, moved.sentAt);
    // The marker under the old key is dropped; ChatSender adds it back.
    expect(Hive.box('pendingSends').isEmpty, isTrue);
  });

  test('an unacknowledged message stays pending for a resend', () async {
    final sentAt = DateTime(2026, 4, 2);
    await CacheUtils.addPrivateMessages('peer',
        [message('peer', 'no ack', sentAt, sendStatus: SendStatus.sending)]);
    await CacheUtils.addPendingSend('peer', sentAt);

    final pending = await CacheUtils.getPendingSends();
    expect(pending['peer']!.single.message, 'no ack');
  });
}
