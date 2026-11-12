import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';

void main() {
  late Directory dir;
  late PrivateMessage keep;
  late PrivateMessage drop;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_delete_message_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    keep = PrivateMessage(
        2, 'keep me', DateTime(2026, 1, 1), DateTime(2026, 1, 1), true);
    drop = PrivateMessage(
        1, 'drop me', DateTime(2026, 1, 2), DateTime(2026, 1, 2), true);
    await CacheUtils.addPrivateMessages(1, [keep, drop]);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('deletePrivateMessage removes only the matching message', () async {
    await CacheUtils.deletePrivateMessage(1, drop);

    final messages = await CacheUtils.getPrivateMessages(1);
    expect(messages.length, 1);
    expect(messages.single.message, 'keep me');
    // The other conversation is untouched
    expect(await CacheUtils.getPrivateMessages(2), isEmpty);
  });
}
