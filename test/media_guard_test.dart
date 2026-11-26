import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';

PrivateMessage media(DateTime sentAt,
    {String? mediaId, String? localPath, String? albumItemPath}) {
  final message = PrivateMessage('peer', '', sentAt, sentAt, true,
      mediaId: mediaId,
      mediaTypeStr: albumItemPath == null ? MediaType.image.name : null,
      localPath: localPath);
  if (albumItemPath != null) {
    message.setAlbum([
      AlbumItem(
          mediaId: mediaId!,
          type: MediaType.image.name,
          size: 1,
          localPath: albumItemPath),
    ]);
  }
  return message;
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_media_guard_test');
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

  final base = DateTime(2026, 6, 1, 12);

  test('a downloaded attachment counts as local', () async {
    await CacheUtils.addPrivateMessages(
        'peer', [media(base, mediaId: 'm1', localPath: '/tmp/a.bin')]);
    expect(await CacheUtils.hasMediaLocally('peer', 'm1'), isTrue);
  });

  test('a placeholder waiting for download does not', () async {
    await CacheUtils.addPrivateMessages('peer', [media(base, mediaId: 'm2')]);
    expect(await CacheUtils.hasMediaLocally('peer', 'm2'), isFalse);
  });

  test('an album item counts when it has a local file', () async {
    await CacheUtils.addPrivateMessages(
        'peer', [media(base, mediaId: 'm3', albumItemPath: '/tmp/a.bin')]);
    expect(await CacheUtils.hasMediaLocally('peer', 'm3'), isTrue);
  });

  test('another conversation does not count', () async {
    await CacheUtils.addPrivateMessages(
        'peer', [media(base, mediaId: 'm4', localPath: '/tmp/a.bin')]);
    expect(await CacheUtils.hasMediaLocally('other', 'm4'), isFalse);
  });

  test('an empty store reports nothing local', () async {
    expect(await CacheUtils.hasMediaLocally('peer', 'nope'), isFalse);
  });
}
