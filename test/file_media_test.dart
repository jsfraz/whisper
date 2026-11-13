import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/message_notifier.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

PrivateMessage media(String type, String? path, DateTime sentAt,
    {String? fileName, int size = 1024}) {
  return PrivateMessage(1, '', sentAt, sentAt, false,
      mediaTypeStr: type,
      localPath: path,
      mediaSize: size,
      fileName: fileName,
      downloadStatus: MediaDownloadStatus.ready);
}

void main() {
  group('detectType', () {
    test('documents become files', () {
      expect(MediaUtils.detectType('/tmp/invoice.pdf'), MediaType.file);
      expect(MediaUtils.detectType('/tmp/archive.zip'), MediaType.file);
    });

    test('known media keeps its own type', () {
      expect(MediaUtils.detectType('/tmp/photo.png'), MediaType.image);
      expect(MediaUtils.detectType('/tmp/anim.gif'), MediaType.gif);
      expect(MediaUtils.detectType('/tmp/clip.mp4'), MediaType.video);
      expect(MediaUtils.detectType('/tmp/song.mp3'), MediaType.voice);
    });
  });

  test('baseName keeps the name with its extension', () {
    expect(
        MediaUtils.baseName('/data/user/0/files/invoice.pdf'), 'invoice.pdf');
    expect(MediaUtils.baseName('no-slash.txt'), 'no-slash.txt');
  });

  test('text previews are limited to text extensions', () {
    expect(MediaUtils.isTextFile('notes.txt'), isTrue);
    expect(MediaUtils.isTextFile('DATA.CSV'), isTrue);
    expect(MediaUtils.isTextFile('invoice.pdf'), isFalse);
    expect(MediaUtils.isTextFile('README'), isFalse);
    expect(MediaUtils.isTextFile(null), isFalse);
  });

  test('sizes are formatted for the bubble', () {
    expect(MediaUtils.formatBytes(512), '512 B');
    expect(MediaUtils.formatBytes(2048), '2.0 KB');
    expect(MediaUtils.formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('a document without a caption previews its name', () {
    final message = media('file', '/tmp/invoice.pdf', DateTime(2026, 11, 13),
        fileName: 'invoice.pdf');
    expect(message.preview, 'invoice.pdf');
    expect(message.mediaType, MediaType.file);
  });

  test('shared media keeps documents, still drops voice', () {
    final now = DateTime(2026, 11, 13, 12);
    final viewable = MessageNotifier.viewableMedia([
      media('file', '/tmp/a.pdf', now, fileName: 'a.pdf'),
      media('voice', '/tmp/b.m4a', now.subtract(const Duration(minutes: 1))),
    ]);
    expect(viewable.map((m) => m.fileName), ['a.pdf']);
  });

  test('the file name survives a Hive round trip', () async {
    final dir = Directory.systemTemp.createTempSync('whisper_file_media_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());

    final message =
        media('file', null, DateTime(2026, 11, 13), fileName: 'a.pdf');
    await CacheUtils.addPrivateMessages(7, [message]);
    final stored = await CacheUtils.getPrivateMessages(7);

    expect(stored.single.fileName, 'a.pdf');
    expect(stored.single.mediaTypeStr, 'file');

    await Hive.close();
    dir.deleteSync(recursive: true);
  });
}
