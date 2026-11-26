import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/utils/cache_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_device_sync_test');
    Hive.init(dir.path);
    // The device id lives in secure storage, which a unit test has to fake.
    final secureStorage = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'read':
            return secureStorage[args['key']];
          case 'write':
            secureStorage[args['key'] as String] = args['value'] as String;
            return null;
          case 'delete':
            secureStorage.remove(args['key']);
            return null;
        }
        return null;
      },
    );
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('the device id is created once and reused', () async {
    final first = await CacheUtils.getOrCreateDeviceId();
    expect(first, isNotEmpty);
    // A second login must reuse it, otherwise a revocation cannot target it.
    expect(await CacheUtils.getOrCreateDeviceId(), first);
  });

  test('the device label is a readable platform name', () {
    expect(CacheUtils.deviceLabel, isNotEmpty);
    expect(CacheUtils.devicePlatform, Platform.operatingSystem);
  });

  test('the archive cursor starts at zero and never moves backwards', () async {
    expect(await CacheUtils.getSyncSeq(), 0);

    await CacheUtils.setSyncSeq(10);
    expect(await CacheUtils.getSyncSeq(), 10);

    // Two overlapping sync answers may arrive out of order; the stale one must
    // not rewind the cursor, or the same messages would be fetched again.
    await CacheUtils.setSyncSeq(4);
    expect(await CacheUtils.getSyncSeq(), 10);

    await CacheUtils.setSyncSeq(12);
    expect(await CacheUtils.getSyncSeq(), 12);
  });
}
