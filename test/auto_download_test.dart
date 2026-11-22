import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/utils/auto_download.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_auto_download_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    await Hive.openBox('settings');
    await Hive.box('settings').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  MediaReference reference(MediaType type, int size) =>
      MediaReference('id', Uint8List(32), type, size);

  test('a voice message is always fetched, whatever the network', () async {
    await CacheUtils.setAutoDownloadPolicy(AutoDownloadPolicy.never);

    expect(
        await AutoDownload.allows(reference(MediaType.voice, 5 << 20)), isTrue);
    expect(await AutoDownload.allows(reference(MediaType.sticker, 5 << 20)),
        isTrue);
  });

  test('a large photo is not fetched under the never policy', () async {
    await CacheUtils.setAutoDownloadPolicy(AutoDownloadPolicy.never);

    expect(await AutoDownload.allows(reference(MediaType.image, 4 << 20)),
        isFalse);
  });

  test('a small attachment is fetched even under the never policy', () async {
    await CacheUtils.setAutoDownloadPolicy(AutoDownloadPolicy.never);

    expect(await AutoDownload.allows(reference(MediaType.image, 1024)), isTrue);
  });

  test('the default policy is Wi-Fi only', () async {
    expect(await CacheUtils.getAutoDownloadPolicy(), AutoDownloadPolicy.wifi);
  });
}
