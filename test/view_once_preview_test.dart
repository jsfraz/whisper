import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/text_envelope.dart';

void main() {
  late Directory dir;
  final now = DateTime(2026, 11, 23, 10);
  const location = LocationRef(50.17595, 14.42);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    dir = Directory.systemTemp.createTempSync('whisper_view_once_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  PrivateMessage locationMessage({required bool viewOnce}) => PrivateMessage(
        '1',
        location.body,
        now,
        now,
        true,
        viewOnce: viewOnce,
        locationJson: jsonEncode(location.toJson()),
      );

  test('a view-once location never previews its coordinates', () {
    final message = locationMessage(viewOnce: true);

    expect(message.preview, 'viewOnceMedia'.tr());

    message.openedAt = now;
    expect(message.preview, 'viewOnceOpened'.tr());
  });

  test('a normal location previews without the pin emoji', () {
    expect(locationMessage(viewOnce: false).preview, '50.17595, 14.42000');
  });

  test('previews drop emojis from the text', () {
    final message = PrivateMessage('1', 'ahoj 😀👍 svět', now, now, true);

    expect(message.preview, 'ahoj svět');
  });

  test('opening a view-once message clears its text and coordinates', () async {
    final message = locationMessage(viewOnce: true);
    await CacheUtils.addPrivateMessages('2', [message]);

    await CacheUtils.markMessageOpened(
        '2', now, now.add(const Duration(minutes: 1)));

    final stored = (await CacheUtils.getPrivateMessages('2')).single;
    expect(stored.openedAt, isNotNull);
    expect(stored.message, isEmpty);
    expect(stored.locationJson, isNull);
    expect(stored.preview, 'viewOnceOpened'.tr());
  });
}
