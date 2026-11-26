import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/models/profile.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/singleton.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept/utils/media_autoplay.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_media_autoplay_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
    // isMe compares against the signed-in user.
    Singleton().profile =
        Profile('', User('me', 'me', '', false), '', '', '', '', false);
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    MediaAutoplay.request.value = null;
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  PrivateMessage voice(DateTime sentAt,
          {String? path = '/tmp/voice', String sender = 'peer'}) =>
      PrivateMessage(sender, '', sentAt, sentAt, true,
          mediaTypeStr: 'voice', localPath: path, durationMs: 1000);

  PrivateMessage note(DateTime sentAt,
          {String? path = '/tmp/note', String sender = 'peer'}) =>
      PrivateMessage(sender, '', sentAt, sentAt, true,
          mediaTypeStr: 'video',
          localPath: path,
          durationMs: 1000,
          mediaRefJson: '{"videoNote":true}');

  test('the next voice message in the chat is requested', () async {
    final first = DateTime(2026, 1, 1, 10);
    final second = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [voice(first), voice(second)]);

    await MediaAutoplay.next('1', first);

    expect(MediaAutoplay.request.value, CacheUtils.messageKey('1', second));
  });

  test('a text message between two voice messages is skipped', () async {
    final first = DateTime(2026, 1, 1, 10);
    final text = DateTime(2026, 1, 1, 10, 1);
    final second = DateTime(2026, 1, 1, 10, 2);
    await CacheUtils.addPrivateMessages('1', [
      voice(first),
      PrivateMessage('1', 'hello', text, text, true),
      voice(second),
    ]);

    await MediaAutoplay.next('1', first);

    expect(MediaAutoplay.request.value, CacheUtils.messageKey('1', second));
  });

  test('a voice message without a local copy is skipped and the end stops',
      () async {
    final first = DateTime(2026, 1, 1, 10);
    final missing = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [
      voice(first),
      voice(missing, path: null),
    ]);

    await MediaAutoplay.next('1', first);

    expect(MediaAutoplay.request.value, isNull);
  });

  test('playback stops instead of playing our own voice message', () async {
    final first = DateTime(2026, 1, 1, 10);
    final mine = DateTime(2026, 1, 1, 10, 1);
    final later = DateTime(2026, 1, 1, 10, 2);
    await CacheUtils.addPrivateMessages('1', [
      voice(first),
      voice(mine, sender: 'me'),
      voice(later),
    ]);

    await MediaAutoplay.next('1', first);

    expect(MediaAutoplay.request.value, isNull);
  });

  test('the next round note in the chat is requested', () async {
    final first = DateTime(2026, 1, 1, 10);
    final second = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [note(first), note(second)]);

    await MediaAutoplay.nextRoundNote('1', first);

    expect(MediaAutoplay.request.value, CacheUtils.messageKey('1', second));
  });

  test('a plain video between two round notes is skipped', () async {
    final first = DateTime(2026, 1, 1, 10);
    final plain = DateTime(2026, 1, 1, 10, 1);
    final second = DateTime(2026, 1, 1, 10, 2);
    await CacheUtils.addPrivateMessages('1', [
      note(first),
      PrivateMessage('peer', '', plain, plain, true,
          mediaTypeStr: 'video', localPath: '/tmp/video'),
      note(second),
    ]);

    await MediaAutoplay.nextRoundNote('1', first);

    expect(MediaAutoplay.request.value, CacheUtils.messageKey('1', second));
  });

  test('a round note without a local copy is skipped and the end stops',
      () async {
    final first = DateTime(2026, 1, 1, 10);
    final missing = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [
      note(first),
      note(missing, path: null),
    ]);

    await MediaAutoplay.nextRoundNote('1', first);

    expect(MediaAutoplay.request.value, isNull);
  });

  test('the round note chain stops at our own note', () async {
    final first = DateTime(2026, 1, 1, 10);
    final mine = DateTime(2026, 1, 1, 10, 1);
    final later = DateTime(2026, 1, 1, 10, 2);
    await CacheUtils.addPrivateMessages('1', [
      note(first),
      note(mine, sender: 'me'),
      note(later),
    ]);

    await MediaAutoplay.nextRoundNote('1', first);

    expect(MediaAutoplay.request.value, isNull);
  });

  test('the voice chain does not pick up a round note', () async {
    final first = DateTime(2026, 1, 1, 10);
    final round = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [voice(first), note(round)]);

    await MediaAutoplay.next('1', first);

    expect(MediaAutoplay.request.value, isNull);
  });
}
