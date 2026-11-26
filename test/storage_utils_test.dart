import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept/utils/storage_utils.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_storage_test');
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

  PrivateMessage attachment(String text, DateTime sentAt, String? path,
          {int size = 1000}) =>
      PrivateMessage('1', text, sentAt, sentAt, true,
          mediaTypeStr: 'image', localPath: path, mediaSize: size);

  test('usage sums only attachments that still have a local copy', () async {
    final file = File('${dir.path}/a')..writeAsBytesSync([1, 2, 3]);
    await CacheUtils.addPrivateMessages('1', [
      attachment('on disk', DateTime.now(), file.path),
      attachment('gone', DateTime.now(), null, size: 5000),
    ]);

    final usage = await StorageUtils.usageByConversation();

    expect(usage.single.attachments, 1);
    expect(usage.single.bytes, greaterThanOrEqualTo(1000));
  });

  test('purge drops the file and marks the attachment expired', () async {
    final file = File('${dir.path}/b')..writeAsBytesSync([1, 2, 3]);
    await CacheUtils.addPrivateMessages('1', [
      attachment(
          'old', DateTime.now().subtract(const Duration(days: 40)), file.path),
    ]);

    final freed = await StorageUtils.purgeOlderThanDays(30);

    expect(freed, greaterThanOrEqualTo(1000));
    expect(file.existsSync(), isFalse);
    final stored = (await CacheUtils.getPrivateMessages('1')).single;
    expect(stored.localPath, isNull);
    expect(stored.downloadStatus, MediaDownloadStatus.expired);
  });

  test('purge keeps the media of recent messages', () async {
    final file = File('${dir.path}/c')..writeAsBytesSync([1, 2, 3]);
    await CacheUtils.addPrivateMessages(
        '1', [attachment('new', DateTime.now(), file.path)]);

    await StorageUtils.purgeOlderThanDays(30);

    expect(file.existsSync(), isTrue);
  });
}
