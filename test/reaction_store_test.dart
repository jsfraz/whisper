import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';

/// Giving a reaction is a local write after the server call: if the key does
/// not match, the badge never appears even though the server took the request.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_reaction_store');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(PrivateMessageAdapter());
    }
  });

  setUp(() async {
    for (final name in ['privateMessages', 'conversations', 'user']) {
      await Hive.openBox(name);
      await Hive.box(name).clear();
    }
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('a reaction lands on the stored message', () async {
    final sentAt = DateTime(2026, 11, 20, 12, 0, 0, 123, 456);
    await CacheUtils.addPrivateMessages(
        'peer', [PrivateMessage('me', 'ahoj', sentAt, sentAt, true)]);

    await CacheUtils.setMessageReaction('peer', sentAt, 'me', '❤️');
    final stored = await CacheUtils.getPrivateMessages('peer');
    expect(stored.single.reactions, {'me': '❤️'});

    // Same emoji again is the caller's toggle; null removes it.
    await CacheUtils.setMessageReaction('peer', sentAt, 'me', null);
    expect(
        (await CacheUtils.getPrivateMessages('peer')).single.reactions, isNull);
  });
}
