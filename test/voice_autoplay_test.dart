import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/voice_autoplay.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_voice_autoplay_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    VoiceAutoplay.request.value = null;
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  PrivateMessage voice(DateTime sentAt, {String? path = '/tmp/voice'}) =>
      PrivateMessage('1', '', sentAt, sentAt, true,
          mediaTypeStr: 'voice', localPath: path, durationMs: 1000);

  test('the next voice message in the chat is requested', () async {
    final first = DateTime(2026, 1, 1, 10);
    final second = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [voice(first), voice(second)]);

    await VoiceAutoplay.next('1', first);

    expect(VoiceAutoplay.request.value, CacheUtils.messageKey('1', second));
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

    await VoiceAutoplay.next('1', first);

    expect(VoiceAutoplay.request.value, CacheUtils.messageKey('1', second));
  });

  test('a voice message without a local copy is skipped and the end stops',
      () async {
    final first = DateTime(2026, 1, 1, 10);
    final missing = DateTime(2026, 1, 1, 10, 1);
    await CacheUtils.addPrivateMessages('1', [
      voice(first),
      voice(missing, path: null),
    ]);

    await VoiceAutoplay.next('1', first);

    expect(VoiceAutoplay.request.value, isNull);
  });
}
