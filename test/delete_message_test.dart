import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';

void main() {
  late Directory dir;
  late PrivateMessage keep;
  late PrivateMessage drop;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_delete_message_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    keep = PrivateMessage(
        '2', 'keep me', DateTime(2026, 1, 1), DateTime(2026, 1, 1), true);
    drop = PrivateMessage(
        '1', 'drop me', DateTime(2026, 1, 2), DateTime(2026, 1, 2), true);
    await CacheUtils.addPrivateMessages('1', [keep, drop]);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('deletePrivateMessage removes only the matching message', () async {
    await CacheUtils.deletePrivateMessage('1', drop);

    final messages = await CacheUtils.getPrivateMessages('1');
    expect(messages.length, 1);
    expect(messages.single.message, 'keep me');
    // The other conversation is untouched
    expect(await CacheUtils.getPrivateMessages('2'), isEmpty);
  });

  test('delete for everyone keeps a tombstone instead of a gap', () async {
    final media = PrivateMessage(
        '1', 'with a photo', DateTime(2026, 1, 3), DateTime(2026, 1, 3), false,
        mediaTypeStr: 'image', localPath: dir.path, reactions: {'1': '👍'});
    await CacheUtils.addPrivateMessages('1', [media]);

    final at = DateTime(2026, 1, 4);
    await CacheUtils.markMessageDeleted('1', media.sentAt, at);

    final messages = await CacheUtils.getPrivateMessages('1');
    final tombstone =
        messages.firstWhere((message) => message.sentAt == media.sentAt);
    expect(tombstone.isDeleted, isTrue);
    expect(tombstone.deletedAt, at);
    expect(tombstone.message, isEmpty);
    expect(tombstone.isMedia, isFalse);
    expect(tombstone.reactions, isNull);
    // Nothing left to read, so it cannot raise a badge.
    expect(tombstone.read, isTrue);
    expect(messages.length, 3);
  });
}
