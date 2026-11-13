import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/utils/cache_utils.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_chat_theme_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('per-chat theme is stored, read and cleared', () async {
    expect(await CacheUtils.getChatTheme('7'), isNull);

    await CacheUtils.setChatTheme('7', const Color(0xFF3366CC));
    expect(await CacheUtils.getChatTheme('7'), const Color(0xFF3366CC));

    // Another chat is not affected
    expect(await CacheUtils.getChatTheme('8'), isNull);

    await CacheUtils.clearChatTheme('7');
    expect(await CacheUtils.getChatTheme('7'), isNull);
  });
}
